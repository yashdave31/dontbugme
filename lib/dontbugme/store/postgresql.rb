# frozen_string_literal: true

require 'json'

module Dontbugme
  module Store
    class Postgresql < Base
      def initialize(connection: nil)
        @connection = connection || Dontbugme.config.postgresql_connection || default_connection
        raise ArgumentError, 'PostgreSQL store requires a database connection' unless @connection
        ensure_schema
      end

      def save_trace(trace)
        data = trace.to_h
        correlation_id = data[:correlation_id] || data[:metadata]&.dig(:correlation_id)
        params = [
          data[:id],
          data[:kind].to_s,
          JsonSafe.sanitize_string(data[:identifier].to_s),
          data[:status].to_s,
          data[:started_at],
          data[:duration_ms],
          correlation_id,
          JsonSafe.sanitize(data[:metadata]).to_json,
          JsonSafe.sanitize(data[:spans]).to_json,
          data[:error] ? JsonSafe.sanitize(data[:error]).to_json : nil
        ]
        exec_params(<<~SQL, params)
          INSERT INTO dontbugme_traces
          (id, kind, identifier, status, started_at, duration_ms, correlation_id, metadata_json, spans_json, error_json)
          VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
          ON CONFLICT (id) DO UPDATE SET
            kind = EXCLUDED.kind,
            identifier = EXCLUDED.identifier,
            status = EXCLUDED.status,
            started_at = EXCLUDED.started_at,
            duration_ms = EXCLUDED.duration_ms,
            correlation_id = EXCLUDED.correlation_id,
            metadata_json = EXCLUDED.metadata_json,
            spans_json = EXCLUDED.spans_json,
            error_json = EXCLUDED.error_json
        SQL
      end

      def find_trace(trace_id)
        result = query_result('SELECT * FROM dontbugme_traces WHERE id = $1', [trace_id])
        return nil if result.blank?

        row = result.is_a?(Array) ? result.first : result.to_a.first
        return nil unless row

        row_to_trace(row)
      end

      def search(filters = {})
        sql = 'SELECT * FROM dontbugme_traces WHERE 1=1'
        params = []
        i = 1

        if filters[:status]
          params << filters[:status].to_s
          sql += " AND status = $#{i}"
          i += 1
        end
        if filters[:kind]
          params << filters[:kind].to_s
          sql += " AND kind = $#{i}"
          i += 1
        end
        if filters[:identifier]
          params << "%#{filters[:identifier]}%"
          sql += " AND identifier LIKE $#{i}"
          i += 1
        end
        if filters[:correlation_id]
          params << filters[:correlation_id].to_s
          sql += " AND correlation_id = $#{i}"
          i += 1
        end

        params << (filters[:limit] || filters['limit'] || 100)
        sql += " ORDER BY started_at DESC LIMIT $#{i}"

        result = query_result(sql, params)
        rows = result.respond_to?(:to_a) ? result.to_a : Array(result)
        rows.map { |row| row_to_trace(normalize_row(row)) }
      end

      def cleanup(before:)
        cutoff = before.is_a?(Time) ? before.utc.iso8601 : before.to_s
        exec_params('DELETE FROM dontbugme_traces WHERE started_at < $1', [cutoff])
      end

      private

      def query_result(sql, params)
        if conn.respond_to?(:exec_query)
          conn.exec_query(sql, 'Dontbugme', params)
        else
          exec_params(sql, params)
        end
      end

      def normalize_row(row)
        return row if row.respond_to?(:[])

        row
      end

      def conn
        @connection
      end

      def default_connection
        return nil unless defined?(ActiveRecord::Base)

        ActiveRecord::Base.connection
      end

      def exec_params(sql, params)
        if conn.respond_to?(:raw_connection)
          conn.raw_connection.exec_params(sql, params)
        elsif conn.respond_to?(:exec_params)
          conn.exec_params(sql, params)
        else
          # Fallback: use execute with sanitization
          sanitized = ActiveRecord::Base.sanitize_sql_array([sql] + params)
          conn.execute(sanitized)
        end
      end

      def exec_query(sql, params = [])
        if conn.respond_to?(:exec_query)
          conn.exec_query(sql, 'Dontbugme', params)
        else
          result = exec_params(sql, params)
          result
        end
      end

      def ensure_schema
        return unless conn

        conn.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS dontbugme_traces (
            id VARCHAR(32) PRIMARY KEY,
            kind VARCHAR(32),
            identifier VARCHAR(512),
            status VARCHAR(32),
            started_at TIMESTAMP,
            duration_ms REAL,
            correlation_id VARCHAR(64),
            metadata_json JSONB,
            spans_json JSONB,
            error_json JSONB
          )
        SQL
        conn.execute('CREATE INDEX IF NOT EXISTS idx_dontbugme_started_at ON dontbugme_traces(started_at)')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_dontbugme_status ON dontbugme_traces(status)')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_dontbugme_correlation_id ON dontbugme_traces(correlation_id)')
      rescue StandardError => e
        raise e if e.message !~ /already exists/i
      end

      def row_to_trace(row)
        metadata_json = row['metadata_json'] || row[:metadata_json]
        spans_json = row['spans_json'] || row[:spans_json]
        error_json = row['error_json'] || row[:error_json]
        hash = {
          id: row['id'] || row[:id],
          kind: row['kind'] || row[:kind],
          identifier: row['identifier'] || row[:identifier],
          status: row['status'] || row[:status],
          started_at: (row['started_at'] || row[:started_at])&.to_s,
          duration_ms: (row['duration_ms'] || row[:duration_ms])&.to_f,
          correlation_id: row['correlation_id'] || row[:correlation_id],
          metadata: metadata_json ? (metadata_json.is_a?(String) ? JSON.parse(metadata_json, symbolize_names: true) : metadata_json) : {},
          spans: spans_json ? (spans_json.is_a?(String) ? JSON.parse(spans_json, symbolize_names: true) : spans_json) : [],
          error: error_json ? (error_json.is_a?(String) ? JSON.parse(error_json, symbolize_names: true) : error_json) : nil
        }
        Trace.from_h(hash)
      end
    end
  end
end
