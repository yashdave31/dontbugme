# frozen_string_literal: true

module Dontbugme
  module Formatters
    class Timeline
      def self.format(trace, only: nil, slow: nil)
        new(trace, only: only, slow: slow).format
      end

      def initialize(trace, only: nil, slow: nil)
        @trace = trace
        @only = only&.to_sym
        @slow = slow
      end

      def format
        lines = []
        lines << ''
        lines << "  #{@trace.identifier}"
        lines << "  Status: #{@trace.status} | Duration: #{duration_str} | Recorded: #{time_ago}"
        lines << ''
        lines << '  TIMELINE'
        lines << '  ' + ('─' * 60)
        lines << ''
        lines << format_start_span
        lines << ''

        spans_to_show.each do |span|
          lines << format_span(span)
        end

        lines << ''
        lines << format_finish_span

        if @trace.truncated_spans_count.to_i.positive?
          lines << ''
          lines << "  ... #{@trace.truncated_spans_count} additional spans truncated"
        end

        lines << ''
        lines.join("\n")
      end

      private

      def format_start_span
        label = case @trace.kind
                when :sidekiq then 'Job started'
                when :request then 'Request started'
                else 'Started'
                end
        "  0.0ms   ▸ #{label}"
      end

      def format_finish_span
        label = case @trace.kind
                when :sidekiq then 'Job finished'
                when :request then 'Request finished'
                else 'Finished'
                end
        duration = @trace.duration_ms ? "#{@trace.duration_ms.round(1)}ms" : '0ms'
        "  #{duration}   ▸ #{label}"
      end

      def spans_to_show
        spans = @trace.raw_spans
        spans = spans.select { |s| s.category == @only } if @only
        spans = spans.select { |s| s.duration_ms.to_f >= @slow } if @slow
        spans
      end

      def format_span(span)
        offset = span.started_at.to_f.round(1)
        duration = span.duration_ms ? "(#{span.duration_ms.round(1)}ms)" : ''
        detail = format_span_detail(span)
        line = "  #{offset}ms   ▸ #{span.category.to_s.upcase} #{span.operation} #{detail} #{duration}".strip
        lines = [line]
        lines << "            → #{span.source}" if span.source && !span.source.empty?
        lines.join("\n")
      end

      def format_span_detail(span)
        case span.category
        when :http
          status = span.payload[:status] || span.payload['status']
          status_str = status ? " → #{status}" : ''
          truncate_detail(span.detail + status_str, 55)
        else
          truncate_detail(span.detail, 50)
        end
      end

      def truncate_detail(str, max_len)
        return '' if str.nil? || str.empty?

        str = str.strip
        return str if str.length <= max_len

        "#{str[0, max_len - 3]}..."
      end

      def duration_str
        ms = @trace.duration_ms
        ms ? "#{ms.round}ms" : 'N/A'
      end

      def time_ago
        return 'N/A' unless @trace.started_at_utc

        sec = Time.now - @trace.started_at_utc
        if sec < 60 then "#{sec.round} sec ago"
        elsif sec < 3600 then "#{(sec / 60).round} min ago"
        elsif sec < 86400 then "#{(sec / 3600).round} hours ago"
        else "#{(sec / 86400).round} days ago"
        end
      end
    end
  end
end
