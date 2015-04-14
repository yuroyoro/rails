require 'active_support/core_ext/module/method_transplanting'

module ActiveRecord
  module AttributeMethods
    module Read
      ReaderMethodCache = Class.new(AttributeMethodCache) {
        private
        # We want to generate the methods via module_eval rather than
        # define_method, because define_method is slower on dispatch.
        # Evaluating many similar methods may use more memory as the instruction
        # sequences are duplicated and cached (in MRI).  define_method may
        # be slower on dispatch, but if you're careful about the closure
        # created, then define_method will consume much less memory.
        #
        # But sometimes the database might return columns with
        # characters that are not allowed in normal method names (like
        # 'my_column(omg)'. So to work around this we first define with
        # the __temp__ identifier, and then use alias method to rename
        # it to what we want.
        #
        # We are also defining a constant to hold the frozen string of
        # the attribute name. Using a constant means that we do not have
        # to allocate an object on each call to the attribute method.
        # Making it frozen means that it doesn't get duped when used to
        # key the @attributes in read_attribute.
        def method_body(method_name, const_name)
          <<-EOMETHOD
          def #{method_name}
            name = ::ActiveRecord::AttributeMethods::AttrNames::ATTR_#{const_name}
            _read_attribute(name) { |n| missing_attribute(n, caller) }
          end
          EOMETHOD
        end
      }.new

      TextReaderMethodCache = Class.new(AttributeMethodCache) {
        def method_body(method_name, const_name)
          <<-EOMETHOD
          def #{method_name}
            name = ::ActiveRecord::AttributeMethods::AttrNames::ATTR_#{const_name}
            @attributes.fetch_original_value(name)
          end
          EOMETHOD
        end
      }.new

      IntegerReaderMethodCache = Class.new(AttributeMethodCache) {
        def method_body(method_name, const_name)
          <<-EOMETHOD
          def #{method_name}
            name = ::ActiveRecord::AttributeMethods::AttrNames::ATTR_#{const_name}
            v = @attributes.fetch_original_value(name)
            ActiveRecord::AttributeMethods::Read::TypeConverter.value_to_integer(v)
          end
          EOMETHOD
        end
      }.new

      FloatReaderMethodCache = Class.new(AttributeMethodCache) {
        def method_body(method_name, const_name)
          <<-EOMETHOD
          def #{method_name}
            name = ::ActiveRecord::AttributeMethods::AttrNames::ATTR_#{const_name}
            v = @attributes.fetch_original_value(name)
            v.to_f
          end
          EOMETHOD
        end
      }.new

      DecimalReaderMethodCache = Class.new(AttributeMethodCache) {
        def method_body(method_name, const_name)
          <<-EOMETHOD
          def #{method_name}
            name = ::ActiveRecord::AttributeMethods::AttrNames::ATTR_#{const_name}
            v = @attributes.fetch_original_value(name)
            ActiveRecord::AttributeMethods::Read::TypeConverter.value_to_decimal(v)
          end
          EOMETHOD
        end
      }.new
      extend ActiveSupport::Concern

      DatetimeReaderMethodCache = Class.new(AttributeMethodCache) {
        def method_body(method_name, const_name)
          <<-EOMETHOD
          def #{method_name}
            name = ::ActiveRecord::AttributeMethods::AttrNames::ATTR_#{const_name}
            v = @attributes.fetch_original_value(name)
            ActiveRecord::AttributeMethods::Read::TypeConverter.string_to_time(v)
          end
          EOMETHOD
        end
      }.new

      TimeReaderMethodCache = Class.new(AttributeMethodCache) {
        def method_body(method_name, const_name)
          <<-EOMETHOD
          def #{method_name}
            name = ::ActiveRecord::AttributeMethods::AttrNames::ATTR_#{const_name}
            v = @attributes.fetch_original_value(name)
            ActiveRecord::AttributeMethods::Read::TypeConverter.dummy_time_string(v)
          end
          EOMETHOD
        end
      }.new

      DateReaderMethodCache = Class.new(AttributeMethodCache) {
        def method_body(method_name, const_name)
          <<-EOMETHOD
          def #{method_name}
            name = ::ActiveRecord::AttributeMethods::AttrNames::ATTR_#{const_name}
            v = @attributes.fetch_original_value(name)
            ActiveRecord::AttributeMethods::Read::TypeConverter.string_to_date(v)
          end
          EOMETHOD
        end
      }.new

      BinaryReaderMethodCache = Class.new(AttributeMethodCache) {
        def method_body(method_name, const_name)
          <<-EOMETHOD
          def #{method_name}
            name = ::ActiveRecord::AttributeMethods::AttrNames::ATTR_#{const_name}
            v = @attributes.fetch_original_value(name)
            ActiveRecord::AttributeMethods::Read::TypeConverter.binary_to_string(v)
          end
          EOMETHOD
        end
      }.new

      BooleanReaderMethodCache = Class.new(AttributeMethodCache) {
        def method_body(method_name, const_name)
          <<-EOMETHOD
          def #{method_name}
            name = ::ActiveRecord::AttributeMethods::AttrNames::ATTR_#{const_name}
            v = @attributes.fetch_original_value(name)
            ActiveRecord::AttributeMethods::Read::TypeConverter.value_to_boolean(v)
          end
          EOMETHOD
        end
      }.new


      extend ActiveSupport::Concern

      module ClassMethods
        [:cache_attributes, :cached_attributes, :cache_attribute?].each do |method_name|
          define_method method_name do |*|
            cached_attributes_deprecation_warning(method_name)
            true
          end
        end

        protected

        def cached_attributes_deprecation_warning(method_name)
          ActiveSupport::Deprecation.warn "Calling `#{method_name}` is no longer necessary. All attributes are cached."
        end

        if Module.methods_transplantable?
          def define_method_attribute(name)
            cache  = rails3_attribute_method_cache(name)
            method = cache[name]
            generated_attribute_methods.module_eval { define_method name, method }
          end

          def rails3_attribute_method_cache(name)
            return ReaderMethodCache if self.serialized_attributes.key? name
            column = self.columns_hash[name]
            case column.type
            when :string, :text        then TextReaderMethodCache
            when :integer              then IntegerReaderMethodCache
            when :float                then FloatReaderMethodCache
            when :decimal              then DecimalReaderMethodCache
            when :datetime, :timestamp then DatetimeReaderMethodCache
            when :time                 then TimeReaderMethodCache
            when :date                 then DateReaderMethodCache
            when :binary               then BinaryReaderMethodCache
            when :boolean              then BooleanReaderMethodCache
            else ReaderMethodCache
            end
          end
        else
          def define_method_attribute(name)
            safe_name = name.unpack('h*').first
            temp_method = "__temp__#{safe_name}"

            ActiveRecord::AttributeMethods::AttrNames.set_name_cache safe_name, name

            generated_attribute_methods.module_eval <<-STR, __FILE__, __LINE__ + 1
              def #{temp_method}
                name = ::ActiveRecord::AttributeMethods::AttrNames::ATTR_#{safe_name}
                _read_attribute(name) { |n| missing_attribute(n, caller) }
              end
            STR

            generated_attribute_methods.module_eval do
              alias_method name, temp_method
              undef_method temp_method
            end
          end
        end
      end

      class TypeConverter
        module Format
          ISO_DATE = /\A(\d{4})-(\d\d)-(\d\d)\z/
          ISO_DATETIME = /\A(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)(\.\d+)?\z/
        end

        class << self
          # Used to convert from Strings to BLOBs
          def string_to_binary(value)
            value
          end

          # Used to convert from BLOBs to Strings
          def binary_to_string(value)
            value
          end

          def string_to_date(string)
            return string unless string.is_a?(String)
            return nil if string.empty?

            fast_string_to_date(string) || fallback_string_to_date(string)
          end

          def string_to_time(string)
            return string unless string.is_a?(String)
            return nil if string.empty?

            fast_string_to_time(string) || fallback_string_to_time(string)
          end

          def string_to_dummy_time(string)
            return string unless string.is_a?(String)
            return nil if string.empty?

            dummy_time_string = "2000-01-01 #{string}"

            fast_string_to_time(dummy_time_string) || begin
              time_hash = Date._parse(dummy_time_string)
              return nil if time_hash[:hour].nil?
              new_time(*time_hash.values_at(:year, :mon, :mday, :hour, :min, :sec, :sec_fraction))
            end
          end
          # convert something to a boolean
          def value_to_boolean(value)
            if value.is_a?(String) && value.blank?
              nil
            else
              ConnectionAdapters::Column::TRUE_VALUES.include?(value)
            end
          end

          # Used to convert values to integer.
          # handle the case when an integer column is used to store boolean values
          def value_to_integer(value)
            case value
            when TrueClass, FalseClass
              value ? 1 : 0
            else
              value.to_i rescue nil
            end
          end

          # convert something to a BigDecimal
          def value_to_decimal(value)
            # Using .class is faster than .is_a? and
            # subclasses of BigDecimal will be handled
            # in the else clause
            if value.class == BigDecimal
              value
            elsif value.respond_to?(:to_d)
              value.to_d
            else
              value.to_s.to_d
            end
          end

          # '0.123456' -> 123456
          # '1.123456' -> 123456
          def microseconds(time)
            time[:sec_fraction] ? (time[:sec_fraction] * 1_000_000).to_i : 0
          end

          def new_date(year, mon, mday)
            if year && year != 0
              Date.new(year, mon, mday) rescue nil
            end
          end

          def new_time(year, mon, mday, hour, min, sec, microsec, offset = nil)
            # Treat 0000-00-00 00:00:00 as nil.
            return if year.nil? || (year == 0 && mon == 0 && mday == 0)

            if offset
              time = ::Time.utc(year, mon, mday, hour, min, sec, microsec) rescue nil
              return unless time

              time -= offset
              Base.default_timezone == :utc ? time : time.getlocal
            else
              ::Time.public_send(Base.default_timezone, year, mon, mday, hour, min, sec, microsec) rescue nil
            end
          end

          def fast_string_to_date(string)
            if string =~ Format::ISO_DATE
              new_date $1.to_i, $2.to_i, $3.to_i
            end
          end

          if RUBY_VERSION >= '1.9'
            # Doesn't handle time zones.
            def fast_string_to_time(string)
              if string =~ Format::ISO_DATETIME
                microsec = ($7.to_r * 1_000_000).to_i
                new_time $1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i, $6.to_i, microsec
              end
            end
          else
            def fast_string_to_time(string)
              if string =~ Format::ISO_DATETIME
                microsec = ($7.to_f * 1_000_000).round.to_i
                new_time $1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i, $6.to_i, microsec
              end
            end
          end

          def fallback_string_to_date(string)
            new_date(*::Date._parse(string, false).values_at(:year, :mon, :mday))
          end

          def fallback_string_to_time(string)
            time_hash = Date._parse(string)
            time_hash[:sec_fraction] = microseconds(time_hash)

            new_time(*time_hash.values_at(:year, :mon, :mday, :hour, :min, :sec, :sec_fraction))
          end
        end
      end

      ID = 'id'.freeze

      # Returns the value of the attribute identified by <tt>attr_name</tt> after
      # it has been typecast (for example, "2004-12-12" in a date column is cast
      # to a date object, like Date.new(2004, 12, 12)).
      def read_attribute(attr_name, &block)
        name = attr_name.to_s
        name = self.class.primary_key if name == ID
        _read_attribute(name, &block)
      end

      # This method exists to avoid the expensive primary_key check internally, without
      # breaking compatibility with the read_attribute API
      def _read_attribute(attr_name) # :nodoc:
        @attributes.fetch_value(attr_name.to_s) { |n| yield n if block_given? }
      end

      private

      def attribute(attribute_name)
        _read_attribute(attribute_name)
      end
    end
  end
end
