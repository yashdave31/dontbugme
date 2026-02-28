# frozen_string_literal: true

module Dontbugme
  module TracesHelper
    def span_category_badge_class(category)
      case category.to_sym
      when :sql then 'badge-sql'
      when :http then 'badge-http'
      when :redis then 'badge-redis'
      when :cache then 'badge-cache'
      when :mailer then 'badge-mailer'
      when :enqueue then 'badge-enqueue'
      when :custom then 'badge-custom'
      when :snapshot then 'badge-snapshot'
      else 'badge-default'
      end
    end

    OUTPUT_KEYS = %w[output result response_body].freeze

    def span_output(span)
      return nil if span.payload.blank?

      payload = span.payload.is_a?(Hash) ? span.payload : {}
      key = OUTPUT_KEYS.find { |k| payload[k.to_sym] || payload[k] }
      key ? (payload[key.to_sym] || payload[key]) : nil
    end

    def format_span_payload(span)
      return [] if span.payload.blank?

      payload = span.payload.is_a?(Hash) ? span.payload : {}
      payload.map do |key, value|
        next if value.nil?
        next if OUTPUT_KEYS.include?(key.to_s)

        display_value = case value
        when Array then value.map { |v| v.is_a?(String) ? v : v.inspect }.join(', ')
        when Hash then value.inspect
        else value.to_s
        end
        display_value = "#{display_value[0, 500]}..." if display_value.length > 500
        [key.to_s.tr('_', ' ').capitalize, display_value]
      end.compact
    end

    def format_span_detail_for_display(span)
      span.detail
    end

    def truncate_detail(str, max_len = 80)
      return '' if str.blank?
      str = str.to_s.strip
      return str if str.length <= max_len
      "#{str[0, max_len - 3]}..."
    end
  end
end
