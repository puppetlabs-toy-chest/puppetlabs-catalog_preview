require_relative 'model_object'

module PuppetX::Puppetlabs::Migration::CatalogDeltaModel
  class DeltaEntity
    include PuppetX::Puppetlabs::Migration::ModelObject

    def self.from_hash(hash)
      instance = allocate
      instance.initialize_from_hash(hash)
      instance
    end
  end

  # Denotes a line in a file
  #
  # @api public
  class Location < DeltaEntity
    # @!attribute [r] file
    #   @api public
    #   @return [String] the file name
    attr_reader :file

    # @!attribute [r] line
    #   @api public
    #   @return [Integer]
    attr_reader :line

    # @param file [String] the file name
    # @param line [Integer] the line in the file
    def initialize(file, line)
      @file = assert_type(String, file)
      @line = assert_type(Integer, line)
    end
  end

  # An element in the model that contains an Integer _diff_id_
  #
  # @abstract
  # @api public
  class Diff < DeltaEntity
    # @!attribute [r] diff_id
    #   @api public
    #   @return [Integer] the id of this element
    attr_reader :diff_id

    # Assigns id numbers to this object and contained objects. The id is incremented
    # once for each assignment that is made.
    #
    # @param id [Integer] The id to set
    # @return [Integer] The incremented id
    #
    # @api private
    def assign_ids(id)
      @diff_id = id
      id + 1
    end

    # Calls #assign_ids(id) all elements in the array while keeping track of the assigned id
    #
    # @param start [Integer] The first id to assign
    # @param array [Array<Diff>] The elements that will receive a new id
    # @return [Integer] The incremented id
    #
    # @api private
    def assign_ids_on_each(start, array)
      array.nil? ? start : array.inject(start) { |n, a| a.assign_ids(n) }
    end
    private :assign_ids_on_each
  end

  # A Resource Attribute. Attributes stems from parameters, and information encoded in the resource (i.e. `exported`
  # or `tags`)
  #
  # @api public
  class Attribute < Diff

    SET_ATTRIBUTES = %w(before after subscribe notify tags).freeze

    # @!attribute [r] name
    #   @api public
    #   @return [String] the attribute name
    attr_reader :name

    # @!attribute [r] value
    #   @api public
    #   @return [Object] the attribute value
    attr_reader :value

    # @param name [String] the attribute name
    # @param value [Object] the attribute value
    def initialize(name, value)
      @name = assert_type(String, name)
      if SET_ATTRIBUTES.include?(name)
        value = [value] unless value.is_a?(Array)
        value = Set.new(value)
      end
      @value = value
    end
  end

  # A Catalog Edge
  #
  # @api public
  class Edge < Diff
    # @!attribute [r] source
    #   @api public
    #   @return [String] the edge source
    attr_reader :source

    # @!attribute [r] target
    #   @api public
    #   @return [String] the edge target
    attr_reader :target

    # @param source [String]
    # @param target [String]
    def initialize(source, target)
      @source = assert_type(String, source)
      @target = assert_type(String, target)
    end

    def ==(other)
      other.instance_of?(Edge) && source == other.source && target == other.target
    end
  end

  # Represents a conflicting attribute, i.e. an attribute that has the same name but different
  # values in the compared catalogs.
  #
  # @api public
  class AttributeConflict < Diff
    # @!attribute [r] name
    #   @api public
    #   @return [String] the attribute name
    attr_reader :name

    # @!attribute [r] baseline_value
    #   @api public
    #   @return [Object] the attribute value in the baseline catalog
    attr_reader :baseline_value

    # @!attribute [r] preview_value
    #   @api public
    #   @return [Object] the attribute value in the preview catalog
    attr_reader :preview_value

    # @api public
    # @return [Boolean] `true` if the preview value is considered compliant with the baseline value
    def compliant?
      @compliant
    end

    # @param name [String]
    # @param baseline_value [Object]
    # @param preview_value [Object]
    # @param compliant [Boolean]
    def initialize(name, baseline_value, preview_value, compliant)
      @name = name
      @baseline_value = baseline_value
      @preview_value = preview_value
      @compliant = compliant
    end
  end

  # Represents a resource in the Catalog.
  #
  # @api public
  class Resource < Diff
    # @!attribute [r] location
    #   @api public
    #   @return [Location] the resource location
    attr_reader :location

    # @!attribute [r] type
    #   @api public
    #   @return [String] the resource type
    attr_reader :type

    # @!attribute [r] title
    #   @api public
    #   @return [String] the resource title
    attr_reader :title

    # @!attribute [r] attributes
    #   The attributes property is a Hash during delta creation. When the creation is finished
    #   it will either be set to `nil` if the production was non-verbose or converted to an
    #   `Array` if the production was verbose.
    #
    #   @api public
    #   @return [Array<Attribute>,Hash<String,Attribute>,nil] the attributes of this resource
    attr_reader :attributes

    # @param location [Location]
    # @param type [String]
    # @param title [String]
    # @param attributes [Array<Attribute>]
    def initialize(location, type, title, attributes)
      @location = location
      @type = assert_type(String, type)
      @title = assert_type(String, title)
      @attributes = attributes
    end

    # Returns the key that uniquely identifies the Resource. The key is used when finding
    # added, missing, equal, and conflicting resources in the compared catalogs.
    #
    # @return [String] resource key constructed from type and title
    # @api public
    def key
      "#{@type}{#{@title}}]"
    end

    def assign_ids(start)
      @attributes = @attributes.values if @attributes.is_a?(Hash)
      assign_ids_on_each(super(start), @attributes)
    end

    # Set the _attributes_ instance variable to `nil`. This is done for all resources
    # in the delta unless the production is flagged as verbose
    #
    # @api private
    def clear_attributes
      @attributes = nil
    end

    def initialize_from_hash(hash)
      hash.each_pair do |k, v|
        k = :"@#{k}"
        instance_variable_set(k,
          case k
          when :@location
            Location.from_hash(v)
          when :@attributes
            v.map { |rh| Attribute.from_hash(rh) }
          else
            v
          end)
      end
    end
  end

  # Represents a resource conflict between a resource in the baseline and a resource with the
  # same type and title in the preview
  #
  # @api public
  class ResourceConflict < Diff
    # @!attribute [r] baseline_location
    #   @api public
    #   @return [Location] the baseline resource location
    attr_reader :baseline_location

    # @!attribute [r] preview_location
    #   @api public
    #   @return [Location] the preview resource location
    attr_reader :preview_location

    # @!attribute [r] type
    #   @api public
    #   @return [String] the resource type
    attr_reader :type

    # @!attribute [r] title
    #   @api public
    #   @return [String] the resource title
    attr_reader :title

    # @!attribute [r] added_attributes
    #   @api public
    #   @return [Array<Attribute>] attributes added in preview resource
    attr_reader :added_attributes

    # @!attribute [r] missing_attributes
    #   @api public
    #   @return [Array<Attribute>] attributes only present in baseline resource
    attr_reader :missing_attributes

    # @!attribute [r] conflicting_attributes
    #   @api public
    #   @return [Array<AttributeConflict>] attributes that are in conflict between baseline and preview
    attr_reader :conflicting_attributes

    # @!attribute [r] equal_attribute_count
    #   @api public
    #   @return [Integer] number of equal attributes
    attr_reader :equal_attribute_count

    # @!attribute [r] added_attribute_count
    #   @api public
    #   @return [Integer] number of added attributes
    attr_reader :added_attribute_count

    # @!attribute [r] missing_attribute_count
    #   @api public
    #   @return [Integer] number of missing attributes
    attr_reader :missing_attribute_count

    # @!attribute [r] conflicting_attribute_count
    #   @api public
    #   @return [Integer] number of conflicting attributes
    attr_reader :conflicting_attribute_count

    # @param baseline_location [Location]
    # @param preview_location [Location]
    # @param type [String]
    # @param title [String]
    # @param equal_attribute_count [Integer]
    # @param added_attributes [Array<Attribute>]
    # @param missing_attributes [Array<Attribute>]
    # @param conflicting_attributes [Array<AttributeConflict>]
    def initialize(baseline_location, preview_location, type, title, equal_attribute_count, added_attributes, missing_attributes, conflicting_attributes)
      @baseline_location = baseline_location
      @preview_location = preview_location
      @type = type
      @title = title
      @equal_attribute_count = equal_attribute_count
      @added_attributes = added_attributes
      @added_attribute_count = added_attributes.size
      @missing_attributes = missing_attributes
      @missing_attribute_count = missing_attributes.size
      @conflicting_attributes = conflicting_attributes
      @conflicting_attribute_count = conflicting_attributes.size
    end

    def assign_ids(start)
      start = super
      start = assign_ids_on_each(start, added_attributes)
      start = assign_ids_on_each(start, missing_attributes)
      assign_ids_on_each(start, conflicting_attributes)
    end

    def compliant?
      @missing_attribute_count == 0 && @conflicting_attributes.all? { |ca| ca.compliant? }
    end

    def initialize_from_hash(hash)
      hash.each_pair do |k, v|
        k = :"@#{k}"
        instance_variable_set(k,
          case k
          when :@baseline_location, :@preview_location
            Location.from_hash(v)
          when :@added_attributes, :@missing_attributes
            v.map { |rh| Attribute.from_hash(rh) }
          when :@conflicting_attributes
            v.map { |rh| AttributeConflict.from_hash(rh) }
          else
            v
          end)
      end
    end
  end

  # Represents a delta between two catalogs
  #
  # @api public
  class CatalogDelta < Diff
    # @!attribute [r] baseline_env
    #   @api public
    #   @return [String] name of baseline environment
    attr_reader :baseline_env

    # @!attribute [r] preview_env
    #   @api public
    #   @return [String] name of preview environment
    attr_reader :preview_env

    def self.from_hash(hash)
      instance = allocate
      instance.initialize_from_hash(hash)
      instance
    end

    # @api public
    # @return [Boolean] `true` if tags are ignored when comparing resources
    def tags_ignored?
      @tags_ignored
    end

    # @api public
    # @return [Boolean] `true` if string/numeric diffs were ignored when comparing resources
    def string_numeric_diff_ignored?
      @string_numeric_diff_ignored
    end

    # @api public
    # @return [Boolean] `true` if preview is compliant with baseline
    def preview_compliant?
      @preview_compliant
    end

    # @api public
    # @return [Boolean] `true` if preview is equal to baseline
    def preview_equal?
      @preview_equal
    end

    # @api public
    # @return [Boolean] `true` if baseline version is equal to preview version
    def version_equal?
      @version_equal
    end

    # @!attribute [r] baseline_resource_count
    #   @api public
    #   @return [Integer] number of resources in baseline
    attr_reader :baseline_resource_count

    # @!attribute [r] preview_resource_count
    #   @api public
    #   @return [Integer] number of resources in preview
    attr_reader :preview_resource_count

    # @!attribute [r] equal_resource_count
    #   @api public
    #   @return [Integer] number of resources that are equal between baseline and preview
    attr_reader :equal_resource_count

    # @!attribute [r] added_resource_count
    #   @api public
    #   @return [Integer] number of resources added in preview
    attr_reader :added_resource_count

    # @!attribute [r] missing_resource_count
    #   @api public
    #   @return [Integer] number of resources only present in baseline
    attr_reader :missing_resource_count

    # @!attribute [r] conflicting_resource_count
    #   @api public
    #   @return [Integer] number of resources in conflict between baseline and preview
    attr_reader :conflicting_resource_count

    # @!attribute [r] added_edge_count
    #   @api public
    #   @return [Integer] number of edges added in preview
    attr_reader :added_edge_count

    # @!attribute [r] missing_edge_count
    #   @api public
    #   @return [Integer] number of edges only present in baseline
    attr_reader :missing_edge_count

    # @!attribute [r] equal_resource_count
    #   @api public
    #   @return [Integer] total number of attributes that are equal between baseline and preview
    attr_reader :equal_attribute_count

    # @!attribute [r] added_resource_count
    #   @api public
    #   @return [Integer] total number of resource attributes added in preview
    attr_reader :added_attribute_count

    # @!attribute [r] missing_resource_count
    #   @api public
    #   @return [Integer] total number of resource attributes only present in baseline
    attr_reader :missing_attribute_count

    # @!attribute [r] conflicting_resource_count
    #   @api public
    #   @return [Integer] total number of resource attributes in conflict between baseline and preview
    attr_reader :conflicting_attribute_count

    # @!attribute [r] baseline_edge_count
    #   @api public
    #   @return [Integer] number of edges in baseline
    attr_reader :baseline_edge_count

    # @!attribute [r] preview_edge_count
    #   @api public
    #   @return [Integer] number of edges in preview
    attr_reader :preview_edge_count

    # @!attribute [r] missing_resources
    #   @api public
    #   @return [Array<Resource>] resources only present in baseline
    attr_reader :missing_resources

    # @!attribute [r] added_resources
    #   @api public
    #   @return [Array<Resource>] resources added in preview
    attr_reader :added_resources

    # @!attribute [r] conflicting_resources
    #   @api public
    #   @return [Array<ResourceConflict>] resources in conflict between baseline and preview
    attr_reader :conflicting_resources

    # @!attribute [r] missing_edges
    #   @api public
    #   @return [Array<Edge>] edges only present in baseline
    attr_reader :missing_edges

    # @!attribute [r] added_edges
    #   @api public
    #   @return [Array<Edge>] edges added in preview
    attr_reader :added_edges

    # @!attribute [r] produced_by
    #   @api public
    #   @return [String] name and version of tool that produced this delta"
    attr_reader :produced_by

    # @!attribute [r] timestamp
    #   @api public
    #   @return [String] when preview run began. In ISO 8601 format with 9 characters second-fragment
    attr_reader :timestamp

    # @!attribute [r] baseline_catalog
    #   @api public
    #   @return [String] the file name of the baseline catalog
    attr_reader :baseline_catalog

    # @!attribute [r] baseline_catalog
    #   @api public
    #   @return [String] the file name of the preview catalog
    attr_reader :preview_catalog

    # @!attribute [r] node_name
    #   @api public
    #   @return [String] the name of the node for which the baseline and preview catalogs were compiled
    attr_reader :node_name

    # Creates a new delta between the two catalog hashes _baseline_ and _preview_. The delta will be produced
    # without considering differences in resource tagging if _ignore_tags_ is set to `true`. The _verbose_
    # flag controls whether or not attributes will be included in missing and added resources in the delta.
    #
    # @param baseline [Hash<Symbol,Object>] the hash representing the baseline catalog
    # @param preview [Hash<Symbol,Object] the hash representing the preview catalog
    # @param options [Hash<Symbol,Object>] preview options
    # @param timestamp [String] when preview run began. In ISO 8601 format with 9 characters second-fragment
    #
    # @api public
    def initialize(baseline, preview, options, timestamp)
      @produced_by      = 'puppet preview 3.8.0'
      @timestamp        = timestamp
      @baseline_catalog = options[:baseline_catalog]
      @preview_catalog  = options[:preview_catalog]
      @node_name        = options[:node]
      @tags_ignored     = options[:skip_tags]
      @string_numeric_diff_ignored = options[:migration_checker] && !options[:diff_string_numeric]

      baseline = assert_type(Hash, baseline, {})
      preview = assert_type(Hash, preview, {})

      @baseline_env     = baseline['environment']
      @preview_env      = preview['environment']
      @version_equal    = baseline['version'] == preview['version']

      baseline_resources = create_resources(baseline)
      @baseline_resource_count = baseline_resources.size


      preview_resources = create_resources(preview)
      @preview_resource_count = preview_resources.size

      @added_resources = preview_resources.reject { |key,_| baseline_resources.include?(key) }.values
      @added_resource_count = @added_resources.size
      @added_attribute_count = @added_resources.inject(0) { |count, r| count + r.attributes.size }

      @missing_resources = baseline_resources.reject { |key,_| preview_resources.include?(key) }.values
      @missing_resource_count = @missing_resources.size
      @missing_attribute_count = @missing_resources.inject(0) { |count, r| count + r.attributes.size }

      @equal_resource_count = 0
      @equal_attribute_count = 0
      @conflicting_attribute_count = 0

      @conflicting_resources = []
      baseline_resources.each_pair do |key,br|
        pr = preview_resources[key]
        next if pr.nil?
        conflict = create_resource_conflict(br, pr)
        if conflict.nil?
          # Resources are equal
          @equal_resource_count += 1
          @equal_attribute_count += br.attributes.size
        else
          @conflicting_resources << conflict
          @equal_attribute_count += conflict.equal_attribute_count
          @conflicting_attribute_count += conflict.conflicting_attributes.size
          @added_attribute_count += conflict.added_attributes.size
          @missing_attribute_count += conflict.missing_attributes.size
        end
      end
      @conflicting_resource_count = @conflicting_resources.size

      baseline_edges = create_edges(baseline)
      @baseline_edge_count = baseline_edges.size

      preview_edges = create_edges(preview)
      @preview_edge_count = preview_edges.size

      @added_edges = preview_edges.reject { |edge| baseline_edges.include?(edge) }
      @added_edge_count = @added_edges.size
      @missing_edges = baseline_edges.reject { |edge| preview_edges.include?(edge) }
      @missing_edge_count = @missing_edges.size

      @preview_compliant = @missing_resources.empty? && @missing_edges.empty? && @conflicting_resources.all? { |cr| cr.compliant? }
      @preview_equal = @preview_compliant && @conflicting_resources.empty? && @added_resources.empty? && @added_edges.empty?

      unless options[:verbose_diff]
        # Clear attributes in the added and missing resources array
        @added_resources.each { |r| r.clear_attributes }
        @missing_resources.each { |r| r.clear_attributes }
      end

      assign_ids(1)
    end

    def initialize_from_hash(hash)
      hash.each_pair do |k, v|
        k = :"@#{k}"
        instance_variable_set(k,
          case k
          when :@added_resources, :@missing_resources
            v.map { |rh| Resource.from_hash(rh) }
          when :@conflicting_resources
            v.map { |rh| ResourceConflict.from_hash(rh) }
          when :@added_edges, :@missing_edges
            v.map { |rh| Edge.from_hash(rh) }
          else
            v
          end)
      end
    end

    def assign_ids(start)
      start = 1
      start = assign_ids_on_each(start, added_resources)
      start = assign_ids_on_each(start, missing_resources)
      start = assign_ids_on_each(start, conflicting_resources)
      start = assign_ids_on_each(start, added_edges)
      assign_ids_on_each(start, missing_edges)
    end

    # @param br [Resource] Baseline resource
    # @param pr [Resource] Preview resource
    # @return [ResourceConflict]
    # @api private
    def create_resource_conflict(br, pr)
      added_attributes = pr.attributes.reject { |key, _| br.attributes.include?(key) }.values
      missing_attributes = br.attributes.reject { |key, _| pr.attributes.include?(key) }.values
      conflicting_attributes = []
      br.attributes.each_pair do |key,ba|
        pa = pr.attributes[key]
        next if pa.nil? || tags_ignored? && key == 'tags'
        conflict = create_attribute_conflict(ba, pa)
        conflicting_attributes << conflict unless conflict.nil?
      end
      if added_attributes.empty? && missing_attributes.empty? && conflicting_attributes.empty?
        nil
      else
        equal_attributes_count = br.attributes.size - conflicting_attributes.size
        ResourceConflict.new(br.location, pr.location, br.type, br.title, equal_attributes_count, added_attributes, missing_attributes, conflicting_attributes)
      end
    end
    private :create_resource_conflict

    # @param ba [Attribute]
    # @param pa [Attribute]
    # @return [AttributeConflict,nil]
    # @api private
    def create_attribute_conflict(ba, pa)
      bav = ba.value
      pav = pa.value
      values_equal?(bav, pav) ? nil : AttributeConflict.new(ba.name, bav, pav, compliant?(bav, pav))
    end
    private :create_attribute_conflict

    # Compares the two values for equality taking #string_to_numeric_diff? into account if set
    #
    # @param bav [Object] value of baseline attribute
    # @param pav [Object] value of preview attribute
    # @return [Boolean] the result of the comparison
    def values_equal?(bav, pav)
      bav == pav || string_numeric_diff_ignored? && bav.is_a?(String) && pav.is_a?(Numeric) && to_number_or_nil(bav) == pav
    end
    private :values_equal?

    # Coerce value to a number, or return `nil` if it isn't one
    #
    # @param value [String] The value to convert
    # @return [Numeric,nil] the number or `nil`
    # @api private
    def to_number_or_nil(value)
      # case/when copied from Puppet::Parser::Scope::number?
      case value
      when /^-?\d+(:?\.\d+|(:?\.\d+)?e\d+)$/
        value.to_f
      when /^0x[0-9a-f]+$/i
        value.to_i(16)
      when /^0[0-7]+$/
        value.to_i(8)
      when /^-?\d+$/
        value.to_i
      else
        nil
      end
    end
    private :to_number_or_nil

    # Answers the question, is _bav_ and _pav_ compliant?
    # Sets are compliant if _pav_ is a subset of _bav_
    # Arrays are compliant if _pav_ contains all non unique values in _bav_. Order is insignificant
    # Hashes are compliant if _pav_ has at least the same set of keys as _bav_, and the values are compliant
    # All other values are compliant if the values are equal
    #
    # @param bav [Object] value of baseline attribute
    # @param pav [Object] value of preview attribute
    # @return [Boolean] the result of the comparison
    # @api private
    def compliant?(bav, pav)
      if bav.is_a?(Set) && pav.is_a?(Set)
        bav.subset?(pav)
      elsif bav.is_a?(Array) && pav.is_a?(Array)
        return false if pav.size < bav.size
        cp = pav.clone
        bav.each do |be|
          ix = cp.index(be)
          return false if ix.nil?
          cp.delete_at(ix)
        end
        true
      elsif bav.is_a?(Hash) && pav.is_a?(Hash)
        # Double negation here since Hash doesn't have an all? method
        !bav.any? {|k,v| !(pav.include?(k) && compliant?(v, pav[k])) }
      else
        values_equal?(bav, pav)
      end
    end

    # @param hash [Hash] a Catalog hash
    # @return [Hash<String,Resource>] a Hash of Resource objects keyed by the Resource#key
    # @api private
    def create_resources(hash)
      result = {}
      assert_type(Array, hash['resources'], []).each do |rh|
        resource = create_resource(rh)
        result[resource.key] = resource
      end
      result
    end
    private :create_resources

    # @param resource [Hash] a Resource hash
    # @return [Resource]
    # @api private
    def create_resource(resource)
      Resource.new(create_location(resource), resource['type'], resource['title'], create_attributes(resource))
    end
    private :create_resource

    # @param hash [Hash] a Catalog hash
    # @return [Array<Edge>]
    # @api private
    def create_edges(hash)
      assert_type(Array, hash['edges'], []).map { |eh| create_edge(assert_type(Hash, eh, {})) }
    end
    private :create_edges

    # @param hash [Hash] an Edge hash
    # @return [Edge]
    # @api private
    def create_edge(hash)
      Edge.new(hash['source'], hash['target'])
    end
    private :create_edge

    # @param elem [Hash] a Location hash
    # @return [Location]
    # @api private
    def create_location(elem)
      file = elem['file']
      line = elem['line']
      file.nil? && line.nil? ? nil : Location.new(file, line)
    end
    private :create_location

    # @param resource [Array<Hash>] a Resource hash
    # @return [Hash<String,Attribute>]
    # @api private
    def create_attributes(resource)
      attrs = {}
      attrs['tags'] = Attribute.new('tags', assert_type(Array, resource['tags'], []))
      attrs['@@'] = Attribute.new('@@', assert_boolean(resource['exported'], false))
      assert_type(Hash, resource['parameters'], {}).each_pair { |name, value| attrs[name] = Attribute.new(name, value)}
      attrs
    end
    private :create_attributes
  end
end

