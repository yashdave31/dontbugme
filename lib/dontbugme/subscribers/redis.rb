# frozen_string_literal: true

module Dontbugme
  module Subscribers
    class Redis
      def self.subscribe
        return unless defined?(::Redis)
        return unless defined?(::Redis::Client)

        ::Redis::Client.prepend(Instrumentation)
      end

      module Instrumentation
        def call(command, &block)
          return super unless Dontbugme::Context.active?
          return super unless Dontbugme.config.recording?

          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
          start_wall = Time.now
          result = super
          duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond) - start_time).round(2)

          record_span(command, start_wall, duration_ms)
          result
        rescue StandardError => e
          duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond) - start_time).round(2)
          record_span(command, start_wall, duration_ms, error: e)
          raise
        end

        private

        def record_span(command, start_wall, duration_ms, error: nil)
          cmd = Array(command).map(&:to_s)
          operation = cmd.first&.upcase || 'UNKNOWN'
          detail = cmd.join(' ')
          config = Dontbugme.config

          payload = { command: operation }
          if config.capture_redis_values && cmd.size > 1
            payload[:args] = cmd[1..].map { |a| truncate(a, config.max_redis_value_size) }
          end
          payload[:error] = error.message if error

          Dontbugme::Recorder.add_span(
            category: :redis,
            operation: operation,
            detail: detail,
            payload: payload,
            duration_ms: duration_ms,
            started_at: start_wall
          )
        end

        def truncate(str, max)
          return str if str.to_s.bytesize <= max

          "#{str.to_s.byteslice(0, max)}[truncated]"
        end
      end
    end
  end
end
