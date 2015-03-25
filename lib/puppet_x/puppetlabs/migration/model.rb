module PuppetX::Puppetlabs::Migration::Model
  # Denotes a line in a file
  class Location
    attr_reader :file, :line, :pos

    # @param file [String]
    # @param line [Integer]
    # @param pos [Integer]
    def initialize(file, line)
      @file = file
      @line = line
    end
  end

  # The super class of all elements in the CatalogDelta model
  #
  class Diff
    attr_reader :diff_id

    # @return [Hash<Symbol,Object>] A Symbol keyed hash that corresponds to this object
    def to_hash
      hash = {}
      instance_variables.each do |iv|
        val = hashify(instance_variable_get(iv))
        hash[:"#{iv.to_s[1..-1]}"] = val unless val.nil?
      end
      hash
    end

    def hashify(val)
      case val
      when Diff
        val.to_hash
      when Hash
        Hash.new(val.each_pair {|k, v| [k, hashify(v)]})
      when Array
        val.map {|v| hashify(v) }
      else
        val
      end
    end

    # Assigns id numbers to this object and contained objects. The id is incremented
    # once for each assignment that is made.
    #
    # @param id [Integer] The id to set
    # @return [Integer] The incremented id
    def assign_ids(id)
      @diff_id = id
      id + 1
    end

    def assign_ids_on_each(start, array)
      array.nil? ? start : array.inject(start) { |n, a| a.assign_ids(n) }
    end

    def assert_type(expected_type, value, default = nil)
      value = default if value.nil?
      raise ArgumentError "Expected an instance of #{expected_type.name}. Got #{value.class.name}" unless value.nil? || value.is_a?(expected_type)
      value
    end

    def assert_boolean(value, default)
      value = default if value.nil?
      raise ArgumentError "Expected an instance of Boolean. Got #{value.class.name}" unless value == true || value == false
      value
    end
  end

  class Attribute < Diff
    attr_reader :name, :value

    # @param name [String]
    # @param value [String]
    def initialize(name, value)
      @name = name
      @value = value
    end
  end

  class Edge < Diff
    attr_reader :source, :target

    def initialize(source, target)
      @source = source
      @target = target
    end

    def ==(other)
      other.instance_of?(Edge) && source == other.source && target == other.target
    end
  end

  class AttributeConflict < Diff
    attr_reader :name, :baseline_value, :preview_value, :compliant

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

  class Resource < Diff
    attr_reader :location, :type, :title, :attributes

    # @param location [Location]
    # @param type [String]
    # @param title [String]
    # @param attributes [Array<Attribute>]
    def initialize(location, type, title, attributes)
      @location = location
      @type = type
      @title = title
      @attributes = attributes
    end

    def clear_attributes
      @attributes = nil
    end

    # @return [String] resource key constructed from type and title
    def key
      "#{@type}{#{@title}}]"
    end

    def assign_ids(start)
      assign_ids_on_each(super(start), attributes)
    end
  end

  class ResourceConflict < Diff
    attr_reader :baseline_location, :preview_location, :type, :title
    attr_reader :added_attributes, :missing_attributes, :conflicting_attributes
    attr_reader :equal_attribute_count, :added_attribute_count, :missing_attribute_count, :conflicting_attribute_count

    # @param baseline_location [Location]
    # @param preview_location [Location]
    # @param type [String]
    # @param title [String]
    # @param equal_attribute_count [Integer]
    # @param added_attributes [Array<Attribute>]
    # @param missing_attributes [Array<Attribute>]
    # @param conflicting_attributes [Array<AttributeConfict>]
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
      start = super(start)
      start = assign_ids_on_each(start, added_attributes)
      start = assign_ids_on_each(start, missing_attributes)
      start = assign_ids_on_each(start, conflicting_attributes)
      start
    end
  end

  class CatalogDelta < Diff
    attr_reader :baseline_env, :preview_env, :tags_ignored
    attr_reader :baseline_resource_count, :preview_resource_count, :added_resource_count, :missing_resource_count, :conflicting_resource_count
    attr_reader :preview_compliant, :preview_equal, :version_equal
    attr_reader :missing_resources, :added_resources, :conflicting_resources
    attr_reader :missing_edges, :added_edges
    attr_reader :baseline_edge_count, :preview_edge_count

    def initialize(baseline, preview, ignore_tags, verbose)
      baseline = assert_type(Hash, baseline, {})
      preview = assert_type(Hash, preview, {})

      @baseline_env = baseline['environment']
      @preview_env = preview['environment']
      @version_equal = baseline['version'] == preview['version']
      @tags_ignored = tags_ignored

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
        next if br.nil?
        conflict = create_resource_conflict(br, pr, ignore_tags)
        if conflict.nil?
          # Resources are equal
          @equal_resource_count += 1
          @equal_attribute_count += br.attributes.size
        else
          @conflicting_resources << conflict
          @equal_attribute_count += conflict.equal_attributes_count
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
      @missing_edges = baseline_edges.reject { |edge| preview_edges.include?(edge) }

      @preview_compliant = @missing_resources.empty? && @conflicting_resources.empty? && @missing_edges.empty?
      @preview_equal = @preview_compliant && @version_equal && @added_resources.empty? && @added_edges.empty?

      unless verbose
        # Clear attributes in the added and missing resources array
        @added_resources.each { |r| r.clear_attributes }
        @missing_resources.each { |r| r.clear_attributes }
      end

      assign_ids(1)
    end

    def assign_ids(start)
      start = super(start)
      start = assign_ids_on_each(start, added_resources)
      start = assign_ids_on_each(start, missing_resources)
      start = assign_ids_on_each(start, conflicting_resources)
      start = assign_ids_on_each(start, added_edges)
      start = assign_ids_on_each(start, missing_edges)
      start
    end

    # @param br [Resource] Baseline resource
    # @param pr [Resource] Preview resource
    # @return [ResourceConflict]
    def create_resource_conflict(br, pr, ignore_tags)
      added_attributes = pr.attributes.reject { |key, a| br.attributes.include?(key) }
      missing_attributes = br.attributes.reject { |key, a| pr.attributes.include?(key) }
      conflicting_attributes = []
      br.attributes.each_pair do |key,ba|
        pa = pr.attributes[key]
        next if pa.nil? || ignore_tags && key == 'tags'
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

    # @param ba [Attribute]
    # @param pa [Attribute]
    # @return [AttributeConflict,nil]
    def create_attribute_conflict(ba, pa)
      bav = ba.value
      pav = pa.value
      return nil if bav == pav

      compliant = false
      if bav.is_a?(Set) && pav.is_a?(Set)
        compliant = ba.subset?(pa)
      elsif bav.is_a?(Array) && pav.is_a?(Array)
        compliant = bav.all? { |e| pav.include?(e) }
      end
      AttributeConflict.new(ba.name, bav, pav, compliant)
    end

    # @param hash [Hash] A Catalog hash
    # @return [Hash<String,Resource>] A Hash of Resource objects keyed by the Resource#key
    def create_resources(hash)
      result = {}
      assert_type(Array, hash['resources'], []).each do |rh|
        resource = create_resource(rh)
        result[resource.key] = resource
      end
      result
    end

    # @param resource [Hash]
    # @param verbose [Boolean]
    # @return [Resource]
    def create_resource(resource)
      Resource.new(create_location(resource), assert_type(String, resource['type']), assert_type(String, resource['title']), create_attributes(resource))
    end

    # @param hash [Hash] A Catalog hash
    # @return [Array<Edge>]
    def create_edges(hash)
      assert_type(Array, hash['edges'], []).map { |eh| resource = create_edge(assert_type(Hash, eh, {})) }
    end

    def create_edge(hash)
      Edge.new(hash['source'], hash['target'])
    end

    # @param elem [Hash]
    # @return [Location]
    def create_location(elem)
      file = assert_type(String, elem['file'])
      line = assert_type(Integer, elem['line'])
      file.nil? && line.nil? ? nil : Location.new(file, line)
    end

    # @param location [Location]
    # @param resource [Array<Hash>]
    # @return [Hash<String,Attribute>]
    def create_attributes(resource)
      attrs = {}
      attrs['tags'] = create_attribute('tags', assert_type(Array, resource['tags'], []))
      attrs['@@'] = create_attribute('@@', assert_boolean(resource['exported'], false))
      assert_type(Hash, resource['parameters'], {}).each_pair { |name, value| attrs[name] = create_attribute(name, value)}
      attrs
    end

    def create_attribute(name, value)
      value = Set.new(assert_type(Array, value, [])) if %w(before, after, subscribe, notify, tags).include?(name)
      Attribute.new(name, value)
    end
  end
end