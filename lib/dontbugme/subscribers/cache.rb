# frozen_string_literal: true

module Dontbugme
  module Subscribers
    class Cache
      EVENTS = %w[
        cache_read.active_support
        cache_write.active_support
        cache_delete.active_support
        cache_exist?.active_support
      ].freeze

      def self.subscribe
        return unless defined?(ActiveSupport::Cache::Store)

        EVENTS.each do |event|
          ::ActiveSupport::Notifications.subscribe(event) do |*args|
            new.call(*args)
          end
        end
      end

      def call(name, start, finish, _id, payload)
        return unless Context.active?
        return unless Dontbugme.config.recording?

        duration_ms = ((finish - start) * 1000).round(2)
        operation = payload[:operation] || payload['operation'] || extract_operation(name)
        key = payload[:key] || payload['key']
        hit = payload[:hit] if payload.key?(:hit) || payload.key?('hit')

        detail = "cache #{operation} #{key}"
        payload_data = { key: key }
        payload_data[:hit] = hit unless hit.nil?
        payload_data[:super_operation] = payload[:super_operation] if payload[:super_operation]

        Recorder.add_span(
          category: :cache,
          operation: operation.to_s.upcase,
          detail: detail,
          payload: payload_data,
          duration_ms: duration_ms,
          started_at: start
        )
      end

      private

      def extract_operation(event_name)
        event_name.to_s.split('.').first
      end
    end
  end
end
