# frozen_string_literal: true

module Dontbugme
  module Subscribers
    class ActiveRecord < Base
      EVENT = 'sql.active_record'

      def self.subscribe
        return unless defined?(::ActiveRecord::Base)

        ::ActiveSupport::Notifications.subscribe(EVENT) do |*args|
          call(*args)
        end
      end

      def call(_name, start, finish, _id, payload)
        return unless Context.active?

        config = Dontbugme.config
        return unless config.recording?

        duration_ms = ((finish - start) * 1000).round(2)
        sql = payload[:sql] || payload['sql'] || ''
        binds = config.capture_sql_binds ? process_binds(payload) : []

        operation = extract_operation(sql)
        payload_data = {
          name: payload[:name] || payload['name'],
          connection_id: payload[:connection_id] || payload['connection_id']
        }
        payload_data[:binds] = binds if binds.any?

        Recorder.add_span(
          category: :sql,
          operation: operation,
          detail: sql,
          payload: payload_data,
          duration_ms: duration_ms,
          started_at: start
        )
      end

      private

      def extract_operation(sql)
        return 'UNKNOWN' if sql.nil? || sql.empty?

        sql = sql.strip.upcase
        if sql.start_with?('SELECT') then 'SELECT'
        elsif sql.start_with?('INSERT') then 'INSERT'
        elsif sql.start_with?('UPDATE') then 'UPDATE'
        elsif sql.start_with?('DELETE') then 'DELETE'
        elsif sql.start_with?('BEGIN') then 'BEGIN'
        elsif sql.start_with?('COMMIT') then 'COMMIT'
        elsif sql.start_with?('ROLLBACK') then 'ROLLBACK'
        elsif sql.start_with?('SAVEPOINT') then 'SAVEPOINT'
        elsif sql.start_with?('RELEASE') then 'RELEASE'
        else 'OTHER'
        end
      end

      def process_binds(payload)
        binds = payload[:binds] || payload['binds'] || []
        type_casted = payload[:type_casted_binds] || payload['type_casted_binds'] || binds
        max_size = Dontbugme.config.max_sql_bind_size

        Array(type_casted).map do |val|
          truncate_value(val, max_size)
        end
      end

      def truncate_value(val, max_size)
        str = val.to_s
        return str if str.bytesize <= max_size

        truncated = str.byteslice(0, max_size)
        "#{truncated}[truncated, #{str.bytesize}B]"
      end
    end
  end
end
