# frozen_string_literal: true

module Dontbugme
  class Recorder
    class << self
      def record(kind:, identifier:, metadata: {}, return_trace: false, &block)
        return yield unless Dontbugme.config.recording?
        return yield unless should_sample?

        metadata = metadata.dup
        metadata[:correlation_id] ||= Correlation.current || Correlation.generate
        Correlation.current = metadata[:correlation_id]

        trace = Trace.new(kind: kind, identifier: identifier, metadata: metadata)
        Context.current = trace

        result = yield
        trace.finish!
        persist(trace)
        return_trace ? trace : result
      rescue StandardError => e
        trace&.finish!(error: e)
        persist(trace) if trace && Dontbugme.config.record_on_error
        raise
      ensure
        Context.clear!
        Correlation.clear! unless kind == :request
      end

      def add_span(category:, operation:, detail:, payload: {}, duration_ms: 0, started_at: nil)
        trace = Context.current
        return unless trace

        # started_at can be a Time (from ActiveSupport::Notifications) or we compute from monotonic
        started_offset = if started_at
          ((started_at - trace.started_at_time) * 1000).round(2)
        else
          (Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond) - trace.started_at_monotonic - duration_ms).round(2)
        end
        source = SourceLocation.capture

        span = Span.new(
          category: category,
          operation: operation,
          detail: detail,
          payload: payload,
          started_at: started_offset,
          duration_ms: duration_ms,
          source: source
        )

        trace.add_span(span)
      end

      private

      def should_sample?
        rate = Dontbugme.config.sample_rate.to_f
        return true if rate >= 1.0

        Random.rand < rate
      end

      def persist(trace)
        store = Dontbugme.store
        store&.save_trace(trace)
      end
    end
  end
end
