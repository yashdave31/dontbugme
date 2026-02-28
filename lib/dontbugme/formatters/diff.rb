# frozen_string_literal: true

require 'ostruct'

module Dontbugme
  module Formatters
    class Diff
      def self.format(trace_a, trace_b)
        new(trace_a, trace_b).format
      end

      def initialize(trace_a, trace_b)
        @trace_a = trace_a
        @trace_b = trace_b
        @alignment = align_spans
      end

      def format
        lines = []
        lines << ''
        lines << "  #{@trace_a.identifier} — Execution Diff"
        lines << '  ' + ('─' * 60)
        lines << ''
        lines << "  Trace A: #{@trace_a.id} (#{@trace_a.status}, #{duration_str(@trace_a)})"
        lines << "  Trace B: #{@trace_b.id} (#{@trace_b.status}, #{duration_str(@trace_b)})"
        lines << ''

        @alignment.each do |result|
          lines << format_result(result)
        end

        lines << ''
        lines.join("\n")
      end

      private

      def align_spans
        spans_a = spans_with_error(@trace_a)
        spans_b = spans_with_error(@trace_b)
        results = []
        i = j = 0

        while i < spans_a.size || j < spans_b.size
          span_a = spans_a[i]
          span_b = spans_b[j]

          if span_a.nil?
            results << { type: :new, span_a: nil, span_b: span_b }
            j += 1
          elsif span_b.nil?
            results << { type: :missing, span_a: span_a, span_b: nil }
            i += 1
          else
            key_a = span_key(span_a)
            key_b = span_key(span_b)

            if key_a == key_b
              if span_equal?(span_a, span_b)
                results << { type: :identical, span_a: span_a, span_b: span_b }
              else
                results << { type: :changed, span_a: span_a, span_b: span_b }
              end
              i += 1
              j += 1
            elsif key_a < key_b
              results << { type: :missing, span_a: span_a, span_b: nil }
              i += 1
            else
              results << { type: :new, span_a: nil, span_b: span_b }
              j += 1
            end
          end
        end

        results
      end

      def spans_with_error(trace)
        spans = trace.raw_spans.dup
        if trace.error
          error_span = OpenStruct.new(
            category: :custom,
            operation: 'EXCEPTION',
            detail: "#{trace.error[:class]}: #{trace.error[:message]}",
            payload: trace.error
          )
          spans << error_span
        end
        spans
      end

      def span_key(span)
        detail = normalize_detail(span.detail)
        "#{span.category}:#{span.operation}:#{detail}"
      end

      def normalize_detail(detail)
        return '' if detail.nil?
        # Normalize SQL: collapse whitespace, remove exact values for comparison
        detail = detail.to_s.strip.gsub(/\s+/, ' ')
        # Truncate for alignment (compare structure, not values)
        detail[0, 80]
      end

      def span_equal?(span_a, span_b)
        return false unless span_a.category == span_b.category
        return false unless span_a.operation == span_b.operation

        case span_a.category
        when :http
          (span_a.payload[:status] || span_a.payload['status']) == (span_b.payload[:status] || span_b.payload['status'])
        when :sql
          normalize_detail(span_a.detail) == normalize_detail(span_b.detail)
        else
          normalize_detail(span_a.detail) == normalize_detail(span_b.detail)
        end
      end

      def format_result(result)
        case result[:type]
        when :identical
          "  IDENTICAL  #{format_span_short(result[:span_a])}"
        when :changed
          lines = ["  CHANGED    #{format_span_short(result[:span_a])}"]
          lines << "               A: #{format_span_detail(result[:span_a])}"
          lines << "               B: #{format_span_detail(result[:span_b])} ←"
          lines.join("\n")
        when :missing
          "  MISSING    #{format_span_short(result[:span_a])}    ← never reached in B"
        when :new
          span_b = result[:span_b]
          if span_b.operation == 'EXCEPTION'
            err = span_b.payload
            detail = err ? "#{err[:class]}: #{truncate(err[:message].to_s, 40)}" : 'EXCEPTION'
            "  NEW        EXCEPTION #{detail}    ← only in B"
          else
            "  NEW        #{format_span_short(span_b)}    ← only in B"
          end
        else
          ''
        end
      end

      def format_span_short(span)
        return '' unless span

        detail = truncate(span.detail, 50)
        "#{span.category.to_s.upcase} #{span.operation} #{detail}"
      end

      def format_span_detail(span)
        case span.category
        when :http
          status = span.payload[:status] || span.payload['status']
          duration = span.duration_ms ? "#{span.duration_ms.round}ms" : ''
          "#{status} #{status_label(status)} (#{duration})".strip
        when :sql
          truncate(span.detail, 60)
        else
          truncate(span.detail, 60)
        end
      end

      def status_label(code)
        return '' unless code
        return 'OK' if code.to_i.between?(200, 299)
        return 'Timeout' if code.to_i == 408 || code.to_i == 504
        return 'Error' if code.to_i >= 400

        ''
      end

      def duration_str(trace)
        ms = trace.duration_ms
        ms ? "#{ms.round}ms" : 'N/A'
      end

      def truncate(str, max)
        return '' if str.nil? || str.empty?
        return str if str.length <= max

        "#{str[0, max - 3]}..."
      end
    end
  end
end
