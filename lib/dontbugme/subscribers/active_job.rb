# frozen_string_literal: true

module Dontbugme
  module Subscribers
    class ActiveJob
      EVENT = 'enqueue.active_job'

      def self.subscribe
        return unless defined?(::ActiveJob::Base)

        ::ActiveSupport::Notifications.subscribe(EVENT) do |*args|
          call(*args)
        end
      end

      def call(_name, start, finish, _id, payload)
        return unless Context.active?
        return unless Dontbugme.config.recording?

        duration_ms = ((finish - start) * 1000).round(2)
        job_class = payload[:job]&.class&.name || payload[:job_class] || payload['job_class']
        queue = payload[:queue] || payload['queue']
        args = payload[:args] || payload['args'] || []

        detail = "ENQUEUE #{job_class}"
        payload_data = {
          job: job_class,
          queue: queue,
          args: args.is_a?(Array) ? args.first(5) : args
        }
        payload_data[:scheduled_at] = payload[:scheduled_at] if payload[:scheduled_at]

        Recorder.add_span(
          category: :enqueue,
          operation: 'ENQUEUE',
          detail: detail,
          payload: payload_data,
          duration_ms: duration_ms,
          started_at: start
        )
      end
    end
  end
end
