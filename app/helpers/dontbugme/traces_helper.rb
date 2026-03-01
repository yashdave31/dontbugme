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
    DEDICATED_INPUT_KEYS = %w[input].freeze

    def span_input(span)
      return nil if span.payload.blank?

      payload = span.payload.is_a?(Hash) ? span.payload : {}
      key = DEDICATED_INPUT_KEYS.find { |k| payload[k.to_sym] || payload[k] }
      key ? (payload[key.to_sym] || payload[key]) : nil
    end

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
        next if DEDICATED_INPUT_KEYS.include?(key.to_s)

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

    def trace_started_at_formatted(trace)
      return nil unless trace.respond_to?(:started_at_utc) && trace.started_at_utc

      trace.started_at_utc.respond_to?(:strftime) ? trace.started_at_utc.strftime('%Y-%m-%d %H:%M:%S.%3N UTC') : trace.started_at_utc.to_s
    end

    def trace_started_at_short(trace)
      return nil unless trace.respond_to?(:started_at_utc) && trace.started_at_utc

      trace.started_at_utc.respond_to?(:strftime) ? trace.started_at_utc.strftime('%Y-%m-%d %H:%M:%S') : trace.started_at_utc.to_s
    end

    def trace_finished_at_formatted(trace)
      return nil unless trace.respond_to?(:duration_ms) && trace.duration_ms

      finished = trace.started_at_utc + (trace.duration_ms / 1000.0)
      finished.respond_to?(:strftime) ? finished.strftime('%Y-%m-%d %H:%M:%S.%3N UTC') : finished.to_s
    end

    def span_timestamp_formatted(trace, span)
      return nil unless trace.respond_to?(:started_at_utc) && trace.started_at_utc
      return nil unless span.respond_to?(:started_at) && span.started_at

      offset_sec = (span.started_at.to_f / 1000.0)
      at = trace.started_at_utc + offset_sec
      at.respond_to?(:strftime) ? at.strftime('%H:%M:%S.%3N') : at.to_s
    end
  end
end
