module PuppetX::Puppetlabs::Migration::OverviewModel
  module Query
    # Wraps an {Entity} and gives it the ability to navigate its relationships as they were
    # normal attributes of the class.
    #
    # @api private
    class Wrapper
      attr_reader :entity

      # Create a new wrapper for the given _entity_ that uses the given _overview_
      # to lookup its id references
      #
      # @param overview [#raw_of_class,#[]] the overview used for lookups
      # @param entity [Entity] the entity to wrap
      #
      def initialize(overview, entity)
        @overview = overview
        @entity = entity
      end

      def id
        @entity.id
      end

      def hash
        @entity.hash
      end

      def <=>(other)
        other.is_a?(Wrapper) ? @entity <=> other.entity : nil
      end

      def ==(other)
        self.class.equal?(other.class) && @entity.equal?(other.entity)
      end

      alias eql? ==

      def method_missing(name, *args)
        super unless args.empty?
        if many = @entity.many_relationship(name)
          entities = resolve_next(@entity, many)
          entities.nil? ? EMPTY_ARRAY : entities.map { |entity| Wrapper.new(@overview, entity) }
        elsif one = @entity.one_relationship(name)
          one == UNDEFINED_ID ? nil : Wrapper.new(@overview, @overview[one])
        else
          @entity.send(name)
        end
      end

      def resolve_next(base, nxt)
        return base.map { |entity| resolve_next(entity, nxt) } if base.is_a?(Array)

        case nxt
        when Symbol
          id = base.send(nxt)
          id.nil? ? nil : @overview[id]
        when Array
          nxt.inject(base) do |entity, n|
            break nil if entity.nil?
            resolve_next(entity, n)
          end
        when UnboundMethod
          id = base.id
          @overview.raw_of_class(nxt.owner).select { |entity| nxt.bind(entity).call == id }
        else
          nil
        end
      end
    end

    # Wraps an {Array<Wrapper>} and gives it the ability to navigate its relationships as they were
    # normal attributes of the class. Also ensures that any method that returns a subset of the array
    # is wrapped
    #
    # @api private
    class WrappingArray < Array
      def of_class(eclass)
        select { |entity| entity.entity.is_a?(eclass) }
      end

      def +(other_ary)
        wrap(super)
      end

      def &(other_ary)
        wrap(super)
      end

      def |(other_ary)
        wrap(super)
      end

      def -(other_ary)
        wrap(super)
      end

      def [](*args)
        wrap(super)
      end

      def compact
        wrap(super)
      end

      def drop(n)
        wrap(super)
      end

      def first(*args)
        wrap(super)
      end

      def flatten
        wrap(super)
      end

      def partition
        parts = super
        [wrap(parts[0]), wrap(parts[1])]
      end

      def reject
        wrap(super)
      end

      def reverse
        wrap(super)
      end

      def pop(*args)
        wrap(super)
      end

      def slice(*args)
        wrap(super)
     end

      def select
        wrap(super)
      end

      def sort
        wrap(super)
      end

      def sort_by
        wrap(super)
      end

      def take(n)
        wrap(super)
      end

      def uniq
        wrap(super)
      end

      def method_missing(name, *args)
        super unless args.empty?
        arr = map { |entity| entity.send(name) }
        arr.compact!
        arr.flatten!
        arr.uniq!
        WrappingArray.new(arr)
      end

      def wrap(x)
        x.nil? || x.is_a?(Wrapper) ? x : WrappingArray.new(x)
      end
      private :wrap
    end

    # Performs traversal of all relationships of a node and collects all entities that are traversed.
    # The collection is then be used to create a new {Overview} that represents that node and all its
    # dependencies.
    #
    class NodeExtractor
      def initialize
        @entities = {}
      end

      # Add the given node and all entities reached when performing recursive traversal of all
      # its dependencies
      #
      # @param node [Wrapper] the node to add
      # @return [NodeExtractor] itself
      def add_node(node)
        add(node)
        add(node.baseline_env)
        add(node.preview_env)
        node.issues_on_node.each { |issue_on_node| traverse_IssueOnNode(issue_on_node) }
        self
      end

      # Creates an overview of the factory's current entity content
      #
      # @return [Overview] the created overview
      def create_overview
        Overview.new(@entities)
      end

      private

      def traverse_IssueOnNode(issue_on_node)
        add(issue_on_node)

        issue = issue_on_node.issue
        add(issue)
        case issue.entity
        when EdgeIssue
          traverse_Resource(issue.source)
          traverse_Resource(issue.target)
        when ResourceConflict
          traverse_Resource(issue.resource)
          traverse_Location(issue.baseline_location)
          traverse_Location(issue.preview_location)
          issue.attribute_issues.each {|ai| traverse_AttributeIssue(ai) }
        when ResourceIssue
          traverse_Resource(issue.resource)
          traverse_Location(issue.location)
        end
      end

      def traverse_Resource(resource)
        add(resource)
        add(resource.type)
      end

      def traverse_Location(location)
        add(location)
        add(location.file)
      end

      def traverse_AttributeIssue(ai)
        add(ai)
        add(ai.attribute)
      end

      def add(wrapped_entity)
        entity = wrapped_entity.entity
        @entities[entity.id] = entity
      end
    end
  end
end
