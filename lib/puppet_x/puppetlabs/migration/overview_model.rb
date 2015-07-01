require_relative 'model_object'
require_relative 'overview_model/query'
require_relative 'overview_model/factory'
require_relative 'overview_model/report'

module PuppetX::Puppetlabs::Migration
  module OverviewModel
    # Abstract base class for all entities in the overview model.
    #
    # @abstract
    #
    # @api public
    class Entity
      include ModelObject

      def self.from_hash(hash)
        instance = allocate
        instance.initialize_from_hash(hash)
        instance.freeze
      end

      # Returns the last segment of the qualified class name
      #
      # @return [String] the name of the class without the module prefix
      # @api public
      def self.simple_name
        name.rpartition(DOUBLE_COLON)[2]
      end

      # @api private
      def self.many_relationship(name)
        @relationships[name]
      end

      # @api private
      def self.init_relationships
        @relationships = many_rels_hash
      end

      # @api private
      def self.many_rels_hash
        EMPTY_HASH
      end

      def id
        @_id
      end

      def initialize(id)
        @_id = id
      end

      def hash
        @_id.hash
      end

      def <=>(o)
        o.is_a?(Entity) ? @_id <=> o.id : nil
      end

      def eql?(o)
        o.is_a?(Entity) && @_id == o.id
      end

      alias == eql?

      # Returns the id of the target entity in the relationship identified by the given _name_ or `nil`
      # if no such relationship exists. An existing relationship with an undefined value is represented
      # by the constant `UNDEFINED_ID`.
      #
      # @param name [Symbol]
      # @return [Method,nil] the get method or array with get method and symbol, or nil
      #
      # @api private
      def one_relationship(name)
      end

      # Returns an object that can be used when retrieving the target collection of the relationship denoted
      # by the given _name_ or `nil` if no such relationship exists.
      #
      # The returned object is either the {UnboundMethod} that, when bound to entities of the target
      # class will yield the id that should be compared with the id of the source entity, or
      # an array where the first element is the method and subsequent elements may be either {UnboundMethod}
      # instances of symbols.
      #
      # The array form is used when traversing though intermediate tables. An {UnboundMethod} is used in the same
      # way as the non-array form and the symbol denotes the method to use to retrieve the final id from the
      # previously found entities (or entities).
      #
      # @param name [Symbol]
      # @return [UnboundMethod,Array<UnboundMethod,Symbol>,nil] the get method or array with get method and symbol, or nil
      #
      # @api private
      def many_relationship(name)
        self.class.many_relationship(name)
      end
    end

    # Represents an immutable snapshot of a collection of entities. Serves as the "database" when doing queries
    #
    # @api public
    class Overview
      include ModelObject

      def self.from_hash(hash)
        instance = allocate
        instance.initialize_from_hash(hash)
        instance.freeze
      end

      attr_reader :entities

      # @param entities [Hash<Integer,Entity] the entities contained in this overview
      #
      # @api public
      def initialize(entities)
        @entities = entities.freeze
      end

      def to_hash
        { :entities => Hash[@entities.map { |k, v| [k, [v.class.simple_name, v.to_hash]] }] }
      end

      def [](id)
        @entities[id]
      end

      # Returns an array of wrappers for all contained entities of the given class
      #
      # @param entity_class [Class<Entity>] an {Entity} subclass
      # @return [WrappingArray<Wrapper>] the wrapped entities
      #
      # @api public
      def of_class(entity_class)
        Query::WrappingArray.new(raw_of_class(entity_class).map { |entity| Query::Wrapper.new(self, entity) })
      end

      # Returns an array of all contained entities of the given class
      #
      # @param entity_class [Class<Entity>] an {Entity} subclass
      # @return [Array<Entity>] the entities
      #
      # @api public
      def raw_of_class(entity_class)
        @entities.values.select {|e| e.is_a?(entity_class)}
      end

      def initialize_from_hash(hash)
        entities = {}
        emap = hash['entities'] || hash[:entities]
        if emap.is_a?(Hash)
          mod = OverviewModel
          emap.each do |id, ea|
            id = id.to_i # since JSON converts integer keys to strings
            eclass = mod.const_get(ea[0])
            entities[id] = eclass.from_hash(ea[1].merge('_id' => id))
          end
        end
        @entities = entities.freeze
      end
    end

    # An entity with a name
    #
    # @abstract
    # @api public
    class NamedEntity < Entity
      attr_reader :name

      def initialize(id, name)
        super(id)
        @name = name
      end

      def <=>(o)
        o.is_a?(NamedEntity) ? @name <=> o.name : super
      end
    end

    # A Node in the overview report represents a Catalog delta produced on a specific node
    #
    # @api public
    class Node < NamedEntity
      attr_reader :timestamp
      attr_reader :severity
      attr_reader :exit_code

      # @api private
      def initialize(id, name, timestamp, severity, exit_code)
        super(id, name)
        @timestamp = timestamp
        @severity = severity
        @exit_code = exit_code
      end

      # @api private
      def self.many_rels_hash
        {
          :baseline_compilation => [Compilation.instance_method(:node_id), Query::MemberEqualFilter.new(:baseline?, true), Query::ScalarValue],
          :preview_compilation => [Compilation.instance_method(:node_id), Query::MemberEqualFilter.new(:baseline?, false), Query::ScalarValue],
          :baseline_env => [Compilation.instance_method(:node_id), Query::MemberEqualFilter.new(:baseline?, true), :environment_id, Query::ScalarValue],
          :preview_env => [Compilation.instance_method(:node_id), Query::MemberEqualFilter.new(:baseline?, false), :environment_id, Query::ScalarValue],
          :log_entries => [Compilation.instance_method(:node_id), LogEntry.instance_method(:compilation_id)],
          :baseline_log_entries => [Compilation.instance_method(:node_id), Query::MemberEqualFilter.new(:baseline?, true), LogEntry.instance_method(:compilation_id)],
          :preview_log_entries => [Compilation.instance_method(:node_id), Query::MemberEqualFilter.new(:baseline?, false), LogEntry.instance_method(:compilation_id)],
          :issues => [IssueOnNode.instance_method(:node_id), :node_issue_id],

          # for access to the intermediate entity that represents the many-to-many relationship. Used
          # by the {Query::NodeExtractor} but otherwise not normally used.
          :issues_on_node => IssueOnNode.instance_method(:node_id)
        }
      end
    end

    # @api public
    class Environment < NamedEntity
      def self.many_rels_hash
        {
          :compilations => Compilation.instance_method(:environment_id),
          :baseline_compilations => [Compilation.instance_method(:environment_id), Query::MemberEqualFilter.new(:baseline?, true)],
          :preview_compilations => [Compilation.instance_method(:environment_id), Query::MemberEqualFilter.new(:baseline?, false)],
          :nodes =>  [Compilation.instance_method(:environment_id), :node_id],
          :baseline_nodes => [Compilation.instance_method(:environment_id), Query::MemberEqualFilter.new(:baseline?, true), :node_id],
          :preview_nodes => [Compilation.instance_method(:environment_id), Query::MemberEqualFilter.new(:baseline?, false), :node_id]
        }
      end
    end

    # @api public
    class ResourceType < NamedEntity
      def self.many_rels_hash
        { :resources => Resource.instance_method(:resource_type_id) }
      end
    end

    # @api public
    class Attribute < NamedEntity
      def self.many_rels_hash
        { :issues => AttributeIssue.instance_method(:attribute_id) }
      end
    end

    # @api public
    class SourceFile < Entity
      attr_reader :path

      def initialize(id, path)
        super(id)
        @path = path
      end

      def self.many_rels_hash
        { :locations => Location.instance_method(:file_id) }
      end
    end

    # @api public
    class Location < Entity
      attr_reader :file_id
      attr_reader :line
      attr_reader :pos

      def initialize(id, file_id, line, pos)
        super(id)
        @file_id = file_id
        @line = line
        @pos = pos
      end

      def one_relationship(name)
        file_id || UNDEFINED_ID if name == :file
      end

      def self.many_rels_hash
        {
          :resources => ResourceIssue.instance_method(:location_id),
          :preview_resources => ResourceConflict.instance_method(:preview_location_id),
          :log_entries => LogEntry.instance_method(:location_id)
        }
      end

      def lp_string
        if @line.nil?
          '--'
        elsif @pos.nil?
          @line.to_s
        else
          "#{@line}:#{@pos}"
        end
      end
    end

    class Compilation < Entity
      attr_reader :node_id
      attr_reader :environment_id
      attr_reader :baseline

      def initialize(id, node_id, environment_id, baseline)
        super(id)
        @node_id = node_id
        @environment_id = environment_id
        @baseline = baseline
      end

      def one_relationship(name)
        case name
        when :node
          node_id || UNDEFINED_ID
        when :environment
          environment_id || UNDEFINED_ID
        end
      end

      def baseline?
        @baseline
      end

      def self.many_rels_hash
        {
          :log_entries => LogEntry.instance_method(:compilation_id)
        }
      end
    end

    class LogLevel < NamedEntity
      def self.many_rels_hash
        {
          :issues => LogIssue.instance_method(:level_id),
          :log_entries => [LogIssue.instance_method(:level_id), LogMessage.instance_method(:issue_id), LogEntry.instance_method(:message_id) ]
        }
      end
    end

    class LogIssue < NamedEntity
      attr_reader :level_id

      def initialize(id, issue, level_id)
        super(id, issue)
        @level_id = level_id
      end

      def one_relationship(name)
        case name
        when :level
          level_id || UNDEFINED_ID
        end
      end

      def self.many_rels_hash
        {
          :messages => LogMessage.instance_method(:issue_id),
          :log_entries => [LogMessage.instance_method(:issue_id), LogEntry.instance_method(:message_id) ]
        }
      end
    end

    class LogMessage < Entity
      attr_reader :message
      attr_reader :issue_id

      def initialize(id, issue_id, message)
        super(id)
        @issue_id = issue_id
        @message = message
      end

      def one_relationship(name)
        case name
        when :issue
          issue_id || UNDEFINED_ID
        end
      end

      def self.many_rels_hash
        {
          :log_entries => LogEntry.instance_method(:message_id),
        }
      end
    end

    class LogEntry < Entity
      attr_reader :compilation_id
      attr_reader :location_id
      attr_reader :message_id
      attr_reader :timestamp

      def initialize(id, compilation_id, timestamp, message_id, location_id)
        super(id)
        @compilation_id = compilation_id
        @timestamp = timestamp
        @message_id = message_id
        @location_id = location_id
      end

      def one_relationship(name)
        case name
        when :compilation
          compilation_id || UNDEFINED_ID
        when :message
          message_id || UNDEFINED_ID
        when :location
          location_id || UNDEFINED_ID
        end
      end
    end

    # @api public
    class Resource < NamedEntity
      attr_reader :resource_type_id

      def initialize(id, title, resource_type_id)
        super(id, title)
        @resource_type_id = resource_type_id
      end

      def one_relationship(name)
        case name
        when :resource_type, :type
          resource_type_id || UNDEFINED_ID
        end
      end

      def self.many_rels_hash
        {
          :source_edges => EdgeIssue.instance_method(:source_id),
          :target_edges => EdgeIssue.instance_method(:target_id),
          :issues => ResourceIssue.instance_method(:resource_id)
        }
      end

      alias title name
    end

    # Represents a many-to-many relationship between a {Node} and a {NodeIssue}. This class
    # and its attributes are normally invisible during query traversal.
    #
    # @api public
    class IssueOnNode < Entity
      attr_reader :node_id
      attr_reader :node_issue_id

      def initialize(id, node_id, node_issue_id)
        super(id)
        @node_id = node_id
        @node_issue_id = node_issue_id
      end

      def one_relationship(name)
        case name
        when :node
          @node_id || UNDEFINED_ID
        when :node_issue, :issue
          @node_issue_id || UNDEFINED_ID
        end
      end
    end

    # Any issue directly associated with a {Node}, i.e. an {EdgeIssue} or a {ResourceIssue}.
    #
    # @abstract
    # @api public
    class NodeIssue < Entity
      def self.many_rels_hash
        { :nodes => [IssueOnNode.instance_method(:node_issue_id), :node_id] }
      end
    end

    # @abstract
    # @api public
    class EdgeIssue < NodeIssue
      attr_reader :source_id
      attr_reader :target_id

      # @param id [Integer] The id of the created instance
      # @param source_id [Integer] The resource id of the source
      # @param target_id [Integer] The resource id of the target
      #
      def initialize(id, source_id, target_id)
        super(id)
        @source_id = source_id
        @target_id = target_id
      end

      def one_relationship(name)
        case name
        when :source
          source_id || UNDEFINED_ID
        when :target
          target_id || UNDEFINED_ID
        end
      end
    end

    # @api public
    class EdgeMissing < EdgeIssue
    end

    # @api public
    class EdgeAdded < EdgeIssue
    end

    # @abstract
    # @api public
    class ResourceIssue < NodeIssue
      attr_reader :location_id
      attr_reader :resource_id

      # @param id [Integer] The id of the created instance
      # @param resource_id [Integer] The id of the resource
      # @param location_id [Integer] The id of the location
      #
      def initialize(id, resource_id, location_id)
        super(id)
        @resource_id = resource_id
        @location_id = location_id
      end

      def one_relationship(name)
        case name
        when :location
          location_id || UNDEFINED_ID
        when :resource
          resource_id || UNDEFINED_ID
        end
      end

      def compliant?
        false
      end
    end

    # @api public
    class ResourceMissing < ResourceIssue
    end

    # @api public
    class ResourceAdded < ResourceIssue
      def compliant?
        true
      end
    end

    # @api public
    class ResourceConflict < ResourceIssue
      attr_reader :preview_location_id

      def initialize(id, resource_id, baseline_location_id, preview_location_id, compliant)
        super(id, resource_id, baseline_location_id)
        @preview_location_id = preview_location_id
        @compliant = compliant
      end

      def compliant?
        @compliant
      end

      def self.many_rels_hash
        NodeIssue.many_rels_hash.merge(:attribute_issues => AttributeIssue.instance_method(:resource_conflict_id))
      end

      def one_relationship(name)
        case name
        when :baseline_location, :location
          location_id || UNDEFINED_ID
        when :preview_location
          preview_location_id || UNDEFINED_ID
        else
          super
        end
      end
    end

    # @abstract
    # @api public
    class AttributeIssue < Entity
      attr_reader :resource_conflict_id
      attr_reader :attribute_id
      attr_reader :value

      def initialize(id, resource_conflict_id, attribute_id, value)
        super(id)
        @resource_conflict_id = resource_conflict_id
        @attribute_id = attribute_id
        @value = value
      end

      def one_relationship(name)
        case name
        when :attribute
          @attribute_id || UNDEFINED_ID
        when :resource_conflict
          @resource_conflict_id || UNDEFINED_ID
        end
      end

      def compliant?
        false
      end
    end

    # @api public
    class AttributeMissing < AttributeIssue
    end

    # @api public
    class AttributeAdded < AttributeIssue
      def compliant?
        true
      end
    end

    # @api public
    class AttributeConflict < AttributeIssue
      attr_reader :preview_value

      def initialize(id, resource_conflict_id, attribute_id, baseline_value, preview_value, compliant)
        super(id, resource_conflict_id, attribute_id, baseline_value)
        @preview_value = preview_value
        @compliant = compliant
      end

      alias baseline_value value

      def compliant?
        @compliant
      end
    end

    # Initialize all relationships
    constants.each { |n| c = const_get(n); c.init_relationships if c.is_a?(Class) && c < Entity }
  end
end

