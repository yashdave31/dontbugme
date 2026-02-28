# frozen_string_literal: true

module Dontbugme
  module Store
    class Memory < Base
      def initialize
        @traces = {}
        @mutex = Mutex.new
      end

      def save_trace(trace)
        @mutex.synchronize do
          @traces[trace.id] = trace.to_h
        end
      end

      def find_trace(trace_id)
        data = @mutex.synchronize { @traces[trace_id] }
        return nil unless data

        Trace.from_h(data)
      end

      def search(filters = {})
        traces = @mutex.synchronize { @traces.values.dup }
        traces = apply_filters(traces, filters)
        traces.map { |h| Trace.from_h(h) }
      end

      def cleanup(before:)
        cutoff = before.is_a?(Time) ? before : Time.parse(before.to_s)
        @mutex.synchronize do
          @traces.delete_if { |_, t| parse_time(t[:started_at]) < cutoff }
        end
      end

      private

      def apply_filters(traces, filters)
        traces = traces.select { |t| t[:status].to_s == filters[:status].to_s } if filters[:status]
        traces = traces.select { |t| t[:status].to_s == filters['status'].to_s } if filters['status']
        traces = traces.select { |t| t[:kind].to_s == filters[:kind].to_s } if filters[:kind]
        if filters[:identifier]
          pattern = /#{Regexp.escape(filters[:identifier].to_s)}/i
          traces = traces.select { |t| t[:identifier].to_s.match?(pattern) }
        end
        if filters[:correlation_id]
          cid = filters[:correlation_id].to_s
          traces = traces.select { |t| (t[:correlation_id] || t.dig(:metadata, :correlation_id)).to_s == cid }
        end
        limit = filters[:limit] || filters['limit'] || 100
        traces.sort_by { |t| t[:started_at] || '' }.reverse.first(limit)
      end

      def parse_time(val)
        return Time.at(0) unless val
        val.is_a?(Time) ? val : Time.parse(val.to_s)
      end
    end
  end
end
