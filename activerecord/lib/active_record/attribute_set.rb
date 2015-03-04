require 'active_record/attribute_set/builder'

module ActiveRecord
  class AttributeSet # :nodoc:
    def initialize(attributes)
      @attributes = attributes
    end

    def [](name)
      attributes[name] || Attribute.null(name)
    end

    def values_before_type_cast
      attributes.transform_values(&:value_before_type_cast)
    end

    def to_hash
      initialized_attributes.transform_values(&:value)
    end
    alias_method :to_h, :to_hash

    def key?(name)
      attributes.key?(name) && self[name].initialized?
    end

    def keys
      attributes.initialized_keys
    end

    def fetch_value(name)
      self[name].value { |n| yield n if block_given? }
    end

    def fetch_raw_value(name)
      value_present = true
      value = attributes.raw_values.fetch(name) { value_present = false }
      value_present ? value : fetch_value(name)
    end

    def write_from_database(name, value)
      attr = self[name].with_value_from_database(value)
      attributes.raw_values[name] = attr.value
      attributes[name] = attr
    end

    def write_from_user(name, value)
      attr = self[name].with_value_from_user(value)
      attributes.raw_values[name] = attr.value
      attributes[name] = attr
    end

    def write_cast_value(name, value)
      attr = self[name].with_cast_value(value)
      attributes.raw_values[name] = attr.value
      attributes[name] = attr
    end

    def freeze
      @attributes.freeze
      super
    end

    def initialize_dup(_)
      @attributes = attributes.dup
      super
    end

    def initialize_clone(_)
      @attributes = attributes.clone
      super
    end

    def reset(key)
      if key?(key)
        write_from_database(key, nil)
      end
    end

    protected

    attr_reader :attributes

    private

    def initialized_attributes
      attributes.select { |_, attr| attr.initialized? }
    end
  end
end
