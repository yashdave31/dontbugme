# frozen_string_literal: true

module Dontbugme
  module Store
    # Sanitizes data for JSON encoding by replacing invalid UTF-8 sequences.
    # Trace data can contain binary from SQL binds, HTTP bodies, Redis, etc.
    module JsonSafe
      REPLACEMENT = "\uFFFD".freeze

      module_function

      def sanitize(obj)
        case obj
        when String
          sanitize_string(obj)
        when Hash
          obj.transform_values { |v| sanitize(v) }
        when Array
          obj.map { |v| sanitize(v) }
        when Symbol
          sanitize_string(obj.to_s)
        when Numeric, TrueClass, FalseClass, NilClass
          obj
        when Time
          obj.respond_to?(:iso8601) ? obj.iso8601(3) : obj.to_s
        else
          sanitize_string(obj.to_s)
        end
      end

      def sanitize_string(str)
        return str if str.nil?
        return str if str.encoding == Encoding::UTF_8 && str.valid_encoding?

        str.encode('UTF-8', invalid: :replace, undef: :replace, replace: REPLACEMENT)
      rescue StandardError
        REPLACEMENT
      end
    end
  end
end
