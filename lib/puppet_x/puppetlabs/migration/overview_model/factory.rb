module PuppetX::Puppetlabs::Migration
  module OverviewModel
    # Builds {OverviewModel::Overview} instances by merging instances of {PuppetX::Puppetlabs::Migration::CatalogDeltaModel::CatalogDelta}
    # @api public
    class Factory
      # Creates and optionally initializes a new instance.
      #
      # @param origin [Factory]
      #
      # @api public
      def initialize(origin = nil)
        @maps_per_class = {}
        if origin.nil?
          @entities = {}
        else
          @entities = origin.entities.clone
          @entities.each { |entity| add_entity(entity) }
        end
      end

      # Returns the entity instance that corresponds to the given _id_
      #
      # @param id [Integer] The id to lookup
      # @return [Entity] entity with the given _id_ or _nil_ if no such entity exists
      #
      # @api public
      def [](id)
        @entities[id]
      end

      # Creates an overview of the factory's current entity content
      #
      # @return [Overview] the created overview
      def create_overview
        Overview.new(@entities.clone)
      end

      # Creates a factory with a snapshot of this factory's current entity content
      #
      # @return [Factory] the created factory
      #
      # @api public
      def clone
        Factory.new(self)
      end

      # Adds all issues from the given _catalog_delta_ to the overview
      #
      # @param catalog_delta [CatalogDeltaModel::CatalogDelta] the delta to add
      # @param baseline_log [Array<Hash<String,Object>>] log from the baseline compilation
      # @param preview_log [Array<Hash<String,Object>>] log from the preview compilation
      # @return [Factory] itself
      #
      # @api public
      def merge(catalog_delta, baseline_log = nil, preview_log = nil)
        node_id = node(catalog_delta, baseline_log, preview_log)
        catalog_delta.added_resources.each do |ar|
          node_issue(node_id, resource_issue(ar, ResourceAdded))
        end

        catalog_delta.missing_resources.each do |mr|
          node_issue(node_id, resource_issue(mr, ResourceMissing))
        end

        catalog_delta.conflicting_resources.each do |cr|
          resource_conflict_id = resource_conflict_issue(cr)
          node_issue(node_id, resource_conflict_id)
          cr.added_attributes.each do |aa|
            attribute_issue(resource_conflict_id, aa, AttributeAdded)
          end
          cr.missing_attributes.each do |ma|
            attribute_issue(resource_conflict_id, ma, AttributeMissing)
          end
          cr.conflicting_attributes.each do |ca|
            attribute_conflict_issue(resource_conflict_id, ca)
          end
        end

        catalog_delta.added_edges.each do |ae|
          node_issue(node_id, edge_issue(ae, EdgeAdded))
        end

        catalog_delta.missing_edges.each do |me|
          node_issue(node_id, edge_issue(me, EdgeMissing))
        end
        self
      end

      # Adds a failing node described by the given arguments to to the overview
      #
      # @param node_name [String] name of node
      # @param env [String] name of environment where compilation failed
      # @param timestamp [String] timestamp of the failure (produced with {DateTime#iso8601(9)})
      # @param exit_code [Integer] the exit code
      # @param log [Array<Hash<String,Object>>] log from the failing compilation
      # @return [Factory] itself
      #
      # @api public
      def merge_failure(node_name, env, timestamp, exit_code, log = nil)
        node_id = complex_key_entity(Node, node_name, timestamp, :error, exit_code) { |node| node.timestamp == timestamp }
        is_baseline = exit_code == BASELINE_FAILED
        compilation_id = complex_key_entity(Compilation, node_id, environment(env), is_baseline)  { |comp| comp.baseline? == is_baseline }
        add_log_entries(compilation_id, log) unless log.nil?
        self
      end

      # Adds log entries from the given _log_ to the {Compilation} identified by _compilation_id
      #
      # @param compilation_id [Integer] id of the Compliation
      # @param log [Array<Hash<String,Object>>] log for the given compilation
      def add_log_entries(compilation_id, log)
        log.each do |entry|
          level_id = single_key_entity(LogLevel, entry['level'])
          issue_id = complex_key_entity(LogIssue, entry['issue_code'], level_id) { |li| li.level_id == level_id }
          message = entry['message']
          message_id = complex_key_entity(LogMessage, issue_id, message) { |lm| lm.message == message }
          location_id = location(entry['file'], entry['line'], entry['pos'])
          complex_key_entity(LogEntry, compilation_id, entry['time'], message_id, location_id)  do |le|
            le.message_id == message_id && le.location_id == location_id
          end
        end
      end

      # Returns the id of the {Environment} entity that corresponds to the given name. A new
      # entity will be created if needed.
      #
      # @param name [String]
      # @return [Integer] id of found or created entity
      #
      # @api public
      def environment(name)
        single_key_entity(Environment, name)
      end

      # Returns the id of the {Resource} entity that corresponds to the given resource. A new
      # entity will be created if needed.
      #
      # @param type_name [String]
      # @return [Integer] id of found or created entity
      #
      # @api public
      def resource_type(type_name)
        single_key_entity(ResourceType, type_name)
      end

      # Returns the id of the {Attribute} entity that corresponds to the given name. A new
      # entity will be created if needed.
      #
      # @param name [String] name of attribute
      # @return [Integer] id of found or created entity
      #
      # @api public
      def attribute(name)
        single_key_entity(Attribute, name)
      end

      # Returns the id of the {SourceFile} entity that corresponds to the given path. A new
      # entity will be created if needed.
      #
      # @param path [String] path of the file
      # @return [Integer] id of found or created entity
      #
      # @api public
      def file(path)
        single_key_entity(SourceFile, path)
      end

      # Returns the id of the {IssueOnNode} entity that corresponds to the given arguments. A new
      # entity will be created if needed.
      #
      # @param node_id [Integer] id of a {Node}
      # @param node_issue_id [Integer] id of {NodeIssue}.
      # @return [Integer] id of found or created entity
      #
      # @api public
      def node_issue(node_id, node_issue_id)
        complex_key_entity(IssueOnNode, node_id, node_issue_id) { |n| n.node_issue_id == node_issue_id }
      end

      # Returns the id of the {Node} entity that corresponds to the given _catalog_delta_. A new
      # entity will be created if needed.
      #
      # @param catalog_delta [CatalogDeltaModel::CatalogDelta] the delta to add
      # @param baseline_log [Array<Hash<Symbol,Object>>] log from the baseline compilation
      # @param preview_log [Array<Hash<Symbol,Object>>] log from the preview compilation
      # @return [Integer] id of found or created entity
      #
      # @api public
      def node(catalog_delta, baseline_log, preview_log)
        baseline_env_id = environment(catalog_delta.baseline_env)
        preview_env_id = environment(catalog_delta.preview_env)
        severity =
            if catalog_delta.preview_equal?
              :equal
            elsif catalog_delta.preview_compliant?
              :compliant
            else
              :conflicting
            end
        timestamp = catalog_delta.timestamp

        node_id = complex_key_entity(Node, catalog_delta.node_name,timestamp, severity, 0) do |node|
          node.timestamp == timestamp
        end

        baseline_compilation_id = complex_key_entity(Compilation, node_id, baseline_env_id, true) { |comp| comp.baseline? }
        add_log_entries(baseline_compilation_id, baseline_log) unless baseline_log.nil?
        preview_compilation_id = complex_key_entity(Compilation, node_id, preview_env_id, false) { |comp| !comp.baseline? }
        add_log_entries(preview_compilation_id, preview_log) unless preview_log.nil?

        node_id
      end

      # Returns the id of the {Location} entity that corresponds to the given _loc_. A new
      # entity will be created if needed.
      #
      # @param loc [CatalogDeltaModel::Location]
      # @return [Integer] id of found or created entity
      #
      # @api public
      def location_from_delta(loc)
        loc.nil? ? nil : location(loc.file, loc.line, nil)
      end

      # Returns the id of the {Location} entity that corresponds to the given parameters. A new
      # entity will be created if needed.
      #
      # @param file [String] name of file
      # @param line [Integer] line in file
      # @param pos [Integer] position on line
      # @return [Integer] id of found or created entity
      #
      # @api public
      def location(file, line, pos)
        complex_key_entity(Location, file(file), line, pos) { |l| l.line == line && l.pos == pos }
      end

      # Returns the id of the {Resource} entity that corresponds to the given arguments. A new
      # entity will be created if needed.
      #
      # @param resource_string [String] a resource reference in the format 'type[title]'
      # @return [Integer] id of found or created entity
      #
      # @api public
      def resource_from_string(resource_string)
        if resource_string =~ /^([^\[\]]+)\[(.+)\]$/m
          resource($2, $1)
        else
          raise ArgumentError, "Bad resource reference '#{resource_string}'"
        end
      end

      # Returns the id of the {Resource} entity that corresponds to the given arguments. A new
      # entity will be created if needed.
      #
      # @param title [String] the resource title
      # @param type [String] the resource type
      # @return [Integer] id of found or created entity
      #
      # @api public
      def resource(title, type)
        resource_type_id = resource_type(type)
        complex_key_entity(Resource, title, resource_type_id) { |r| r.resource_type_id == resource_type_id }
      end

      # Returns the id of the {AttributeIssue} entity that corresponds to the given arguments. A new
      # entity will be created if needed.
      #
      # @param resource_conflict_id [Integer] id of the resource conflict that contains this attribute
      # @param attribute [CatalogDeltaModel::Attribute]
      # @param issue_class [Class]
      # @return [Integer] id of found or created entity
      #
      # @api public
      def attribute_issue(resource_conflict_id, attribute, issue_class)
        attribute_id = attribute(attribute.name)
        value = attribute.value
        complex_key_entity(issue_class, resource_conflict_id, attribute_id, value) { |ac| ac.attribute_id == attribute_id && ac.value == value }
      end

      # Returns the id of the {AttributeConflict} entity that corresponds to the given arguments. A new
      # entity will be created if needed.
      #
      # @param resource_conflict_id [Integer] id of the resource conflict that contains this attribute
      # @param attribute_conflict [CatalogDeltaModel::AttributeConflict]
      # @return [Integer] id of found or created entity
      #
      # @api public
      def attribute_conflict_issue(resource_conflict_id, attribute_conflict)
        attribute_id = attribute(attribute_conflict.name)
        baseline_value = attribute_conflict.baseline_value
        preview_value = attribute_conflict.preview_value
        complex_key_entity(AttributeConflict, resource_conflict_id, attribute_id, baseline_value, preview_value, attribute_conflict.compliant?) do |ac|
          ac.attribute_id == attribute_id && ac.value == baseline_value && ac.preview_value == preview_value
        end
      end

      # Returns the id of the {ResourceIssue} entity that corresponds to the given arguments. A new
      # entity will be created if needed.
      #
      # @param resource [CatalogDeltaModel::Resource]
      # @param issue_class [Class]
      # @return [Integer] id of found or created entity
      #
      # @api public
      def resource_issue(resource, issue_class)
        resource_id = resource(resource.title, resource.type)
        location_id = location_from_delta(resource.location)
        complex_key_entity(issue_class, resource_id, location_id) { |i| i.location_id == location_id }
      end

      # Returns the id of the {ResourceIssue} entity that corresponds to the given arguments. A new
      # entity will be created if needed.
      #
      # @param resource_conflict [CatalogDeltaModel::ResourceConflict]
      # @return [Integer] id of found or created entity
      #
      # @api public
      def resource_conflict_issue(resource_conflict)
        resource_id = resource(resource_conflict.title, resource_conflict.type)
        baseline_location_id = location_from_delta(resource_conflict.baseline_location)
        preview_location_id = location_from_delta(resource_conflict.preview_location)
        complex_key_entity(ResourceConflict, resource_id, baseline_location_id, preview_location_id, resource_conflict.compliant?) do |i|
          i.location_id == baseline_location_id && i.preview_location_id == preview_location_id
        end
      end

      # @param edge [CatalogDeltaModel::Edge] the edge
      # @param issue_class [Class] a subclass of {EdgeIssue}
      # @return [Integer] id of found or created entity
      #
      # @api public
      def edge_issue(edge, issue_class)
        source_id = resource_from_string(edge.source)
        target_id = resource_from_string(edge.target)
        complex_key_entity(issue_class, source_id, target_id) { |i| i.target_id == target_id }
      end

      private

      # Add an existing entity into the current index
      #
      # @param entity [Entity] the entity to merge
      #
      # @api private
      def add_entity(entity)
        hfc = hash_for_class(entity.class)
        key = secondary_key(entity)
        if simple_key(entity)
          hfc[key] = entity
        else
          arr = hfc[key]
          if arr.nil?
            hfc[key] = [entity]
          else
            arr << entity
          end
        end
      end

      # @param entity [Entity] the entity to check
      # @return [Object] the value of the secondary key
      #
      # @api private
      def secondary_key(entity)
        case entity
          when IssueOnNode
            entity.node_id
          when Location
            entity.file_id
          when AttributeIssue
            entity.attribute_id
          when ResourceIssue
            entity.resource_id
          when EdgeIssue
            entity.source_id
          when SourceFile
            entity.path
          else
            entity.name
        end
      end

      # @param entity [Entity] the entity to check
      # @return [Boolean] true if the given entity has one property aside from its id
      #
      # @api private
      def simple_key(entity)
        case entity
          when Environment, ResourceType, Attribute, SourceFile
            true
          else
            false
        end
      end

      # Find or create an instance of a single key `Entity` subclass. A single key
      # entity is an entity that has only one attribute of type Integer or String
      # in addition to its id.
      #
      # @param entity_class [Class] A single key Entity subclass
      # @param key [String|Integer] The name to assign to the created entity
      # @return [Integer] id of found or created entity
      #
      # @api private
      def single_key_entity(entity_class, key)
        entities = hash_for_class(entity_class)
        entity = entities[key] ||= new_entity(entity_class, key)
        entity.id
      end

      # Find or create an instance of an `Entity` subclass using a complex key.
      #
      # The lookup will use the given _key_ to lookup an array in the hash that
      # represents the cache for the given _entity_class_. The array will be
      # created if needed. The lookup will then call `find` on the array with
      # the given _block_. If an entry is found, it will be returned, otherwise
      # a new entry will be created and added to the array by passing the given
      # arguments to the method {#new_entity}
      #
      # @param entity_class [Class] An Entity subclass
      # @param key [String|Integer] The first key
      # @return [Integer] id of found or created entity
      #
      # @api private
      def complex_key_entity(entity_class, key, *others, &block)
        hfc = hash_for_class(entity_class)
        entities = hfc[key] ||= []
        entity = entities.find &block
        if entity.nil?
          entity = new_entity(entity_class, key, *others)
          entities << entity
        end
        entity.id
      end

      # Returns the hash that represents the cache for the given _entity_class_. The hash will
      # be created if needed.
      #
      # @param entity_class [Class]
      # @return [Hash<Object,Object>] hash the given class
      #
      # @api private
      def hash_for_class(entity_class)
        @maps_per_class[entity_class] ||= {}
      end

      # Creates an entity by sending a unique integer id together
      # with the given _args_ to the `new` method of the given _entity_class_.
      # @param entity_class [Class] the class of the instance to be created
      # @param *args [Object] arguments sent to the constructor
      # @return [Entity] the created instance
      #
      # @api private
      def new_entity(entity_class, *args)
        id = @entities.size
        @entities[id] = entity_class.new(id, *args).freeze
      end
    end
  end
end