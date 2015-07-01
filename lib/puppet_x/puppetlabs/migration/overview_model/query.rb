module PuppetX::Puppetlabs::Migration
module OverviewModel
  module Query
    # @abstract
    class RelationalStep
      # Evaluates the filter on the given _entity_ and returns the result
      #
      # @param instance [Entity] the entity to use when evaluating
      # @return [Object] the result of the evaluation
      def evaluate(instance)
        nil
      end
    end

    # Returns the first element of a collection
    #
    class ScalarValue < RelationalStep
      # @param collection [Array<Entity>] The collection
      # @return [Entity,nil] The entity or nil
      def evaluate(collection)
        collection.is_a?(Array) ? collection.first : nil
      end
    end

    # A filter that checks if the given _member_ has the given _value_
    #
    class MemberEqualFilter < RelationalStep
      # @param member [Symbol] name of the member method
      # @param value [Object] expected value of the member
      def initialize(member, value)
        @member = member
        @value = value
      end

      # @param instance [Entity] The instance to check
      # @return [Entity,nil] The entity or nil
      def evaluate(instance)
        instance.send(@member) == @value ? instance : nil
      end
    end

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
        raise ArgumentError unless entity.is_a?(Entity)
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

      def is_scalar(relationship)
        relationship.is_a?(Array) && relationship.last.is_a?(ScalarValue)
      end

      # Clobbered by test framework unless present (adding respond_to_missing? doesn't help)
      def message
        dispatch(:message)
      end

      # Clobbered by test framework unless present (adding respond_to_missing? doesn't help)
      def exit_code
        @entity.exit_code
      end

      def method_missing(name, *args)
        args.empty? ? dispatch(name) : super
      end

      def respond_to_missing?(name, include_private)
        !(@entity.many_relationship(name).nil? && @entity.one_relationship(name).nil? && !@entity.respond_to?(name))
      end

      def dispatch(name)
        if many = @entity.many_relationship(name)
          result = resolve_next(@entity, many)
          if is_scalar(many)
            result.nil? ? nil : Wrapper.new(@overview, result)
          else
            if result.is_a?(Array)
              WrappingArray.from_entities(@overview, result)
            else
              EMPTY_ARRAY
            end
          end
        elsif one = @entity.one_relationship(name)
          one == UNDEFINED_ID ? nil : Wrapper.new(@overview, @overview[one])
        else
          @entity.send(name)
        end
      end

      def resolve_next(base, nxt)
        if base.is_a?(Array)
          result = base.map { |entity| resolve_next(entity, nxt) }
          result.compact!
          result
        else
          case nxt
          when Symbol
            id = base.send(nxt)
            id.nil? ? nil : @overview[id]
          when RelationalStep
            nxt.evaluate(base)
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
    end

    # Wraps an {Array<Wrapper>} and gives it the ability to navigate its relationships as they were
    # normal attributes of the class. Also ensures that any method that returns a subset of the array
    # is wrapped
    #
    # @api private
    class WrappingArray < Array
      def self.from_entities(overview, entities)
        entities.flatten!
        entities.uniq!
        entities.compact!
        new(entities.map { |entity| Wrapper.new(overview, entity) })
      end

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

      # Should not be needed but Minitest::Assertions adds this method even though
      # respond_to_missing? is implemented
      def message
        dispatch(:message)
      end

      def exit_code
        dispatch(:exit_code)
      end

      def respond_to_missing?(name, include_private)
        true # We dispatch all unknown messages to each instance
      end

      def method_missing(name, *args)
        args.empty? ? dispatch(name) : super
      end

      def dispatch(name)
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
end

