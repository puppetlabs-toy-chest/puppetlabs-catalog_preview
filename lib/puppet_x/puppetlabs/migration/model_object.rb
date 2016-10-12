module PuppetX::Puppetlabs::Migration
  TRANSIENT_PREFIX = '@_'.freeze

  # The super class of all elements in the Overview and CatalogDelta models
  #
  # @abstract
  # @api public
  module ModelObject
    # Creates a hash from the persistent instance variables of this object. The keys will be symbols
    # corresponding to the attribute names (without leading '@'). The process of creating
    # a hash is recursive in the sens that all ModelObject instances found by traversing
    # the values of the instance variables will be converted too.
    #
    # @return [Hash<Symbol,Object>] a Symbol keyed hash with all attributes in this object
    #
    # @api public
    def to_hash
      hash = {}
      instance_variables.each do |iv|
        iv_name = iv.to_s
        next if iv_name.start_with?(TRANSIENT_PREFIX)
        val = hashify(instance_variable_get(iv))
        hash[:"#{iv_name[1..-1]}"] = val unless val.nil?
      end
      hash
    end

    def initialize_from_hash(hash)
      hash.each_pair { |k, v| instance_variable_set( :"@#{k}", v)}
    end

    # Asserts that _value_ is of class _expected_type_ and raises an ArgumentError when that's not the case
    #
    # @param expected_type [Class]
    # @param value [Object]
    # @param default [Object]
    # @return [Object] the _value_ argument or _default_ argument when _value_ is nil
    #
    # @api private
    def assert_type(expected_type, value, default = nil)
      value = default if value.nil?
      raise ArgumentError, "Expected an instance of #{expected_type.name}. Got #{value.class.name}" unless value.nil? || value.is_a?(expected_type)
      value
    end
    private :assert_type

    # Asserts that _value_ is one of the classes in _expected_types_ and raises an ArgumentError when that's not the case
    #
    # @param expected_types [Array<Class>]
    # @param value [Object]
    # @param default [Object]
    # @return [Object] the _value_ argument or _default_ argument when _value_ is nil
    #
    # @api private
    def assert_one_of_type(expected_types, value, default = nil)
      value = default if value.nil?
      unless value.nil? || expected_types.any? {|t| value.is_a?(t) }
        raise ArgumentError, "Expected an instance of one of #{expected_types.map {|t| t.name}.join(', ')}. Got #{value.class.name}"
      end
      value
    end
    private :assert_type

    # Asserts that _value_ is a boolean and raises an ArgumentError when that's not the case
    #
    # @param value [Object]
    # @param default [Boolean]
    # @return [Boolean] the _value_ argument or _default_ argument when _value_ is nil
    #
    # @api private
    def assert_boolean(value, default)
      value = default if value.nil?
      raise ArgumentError, "Expected an instance of Boolean. Got #{value.class.name}" unless value == true || value == false
      value
    end
    private :assert_boolean

    # Converts ModelObject to Hash and traverses Array and Hash objects to
    # call this method recursively on each element. Object that are not
    # ModelObject, Array, or Hash are returned verbatim
    #
    # @param val [Object] The value to hashify
    # @return [Object] the val argument, possibly converted
    #
    # @api private
    def hashify(val)
      case val
      when ModelObject
        val.to_hash
      when Hash
        Hash[val.each_pair {|k, v| [k, hashify(v)]}]
      when Array
        val.map {|v| hashify(v) }
      else
        val
      end
    end
    private :hashify
  end
end
