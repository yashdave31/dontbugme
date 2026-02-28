# frozen_string_literal: true

require 'fileutils'
require 'json'

module Dontbugme
  module Store
    class Sqlite < Base
      def initialize(path: nil)
        @path = path || Dontbugme.config.sqlite_path
        ensure_directory
        ensure_schema
      end

      def save_trace(trace)
        data = trace.to_h
        correlation_id = data[:correlation_id] || data[:metadata]&.dig(:correlation_id)
        db.execute(
          'INSERT OR REPLACE INTO traces (id, kind, identifier, status, started_at, duration_ms, correlation_id, metadata_json, spans_json, error_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          data[:id],
          data[:kind].to_s,
          data[:identifier],
          data[:status].to_s,
          data[:started_at],
          data[:duration_ms],
          correlation_id,
          data[:metadata].to_json,
          data[:spans].to_json,
          data[:error]&.to_json
        )
      end

      def find_trace(trace_id)
        row = db.execute('SELECT id, kind, identifier, status, started_at, duration_ms, correlation_id, metadata_json, spans_json, error_json FROM traces WHERE id = ?', trace_id).first
        return nil unless row

        row_to_trace(row)
      end

      def search(filters = {})
        sql = 'SELECT id, kind, identifier, status, started_at, duration_ms, correlation_id, metadata_json, spans_json, error_json FROM traces WHERE 1=1'
        params = []

        if filters[:status]
          sql += ' AND status = ?'
          params << filters[:status].to_s
        end
        if filters[:kind]
          sql += ' AND kind = ?'
          params << filters[:kind].to_s
        end
        if filters[:identifier]
          sql += ' AND identifier LIKE ?'
          params << "%#{filters[:identifier]}%"
        end
        if filters[:correlation_id]
          sql += ' AND correlation_id = ?'
          params << filters[:correlation_id].to_s
        end

        sql += ' ORDER BY started_at DESC LIMIT ?'
        params << (filters[:limit] || filters['limit'] || 100)

        rows = db.execute(sql, *params)
        rows.map { |row| row_to_trace(row) }
      end

      def cleanup(before:)
        cutoff = before.is_a?(Time) ? before.iso8601 : before.to_s
        db.execute('DELETE FROM traces WHERE started_at < ?', cutoff)
      end

      private

      def db
        @db ||= begin
          require 'sqlite3'
          db = SQLite3::Database.new(@path)
          db.execute('PRAGMA journal_mode=WAL')
          db.execute('PRAGMA busy_timeout=5000')
          db
        end
      end

      def ensure_directory
        dir = File.dirname(@path)
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      end

      def ensure_schema
        db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS traces (
            id TEXT PRIMARY KEY,
            kind TEXT,
            identifier TEXT,
            status TEXT,
            started_at TEXT,
            duration_ms REAL,
            correlation_id TEXT,
            metadata_json TEXT,
            spans_json TEXT,
            error_json TEXT
          )
        SQL
        migrate_add_correlation_id
        db.execute('CREATE INDEX IF NOT EXISTS idx_traces_started_at ON traces(started_at)')
        db.execute('CREATE INDEX IF NOT EXISTS idx_traces_status ON traces(status)')
        db.execute('CREATE INDEX IF NOT EXISTS idx_traces_correlation_id ON traces(correlation_id)')
      end

      def migrate_add_correlation_id
        return if db.execute("PRAGMA table_info(traces)").any? { |col| col[1] == 'correlation_id' }

        db.execute('ALTER TABLE traces ADD COLUMN correlation_id TEXT')
      end

      def row_to_trace(row)
        # row: [id, kind, identifier, status, started_at, duration_ms, correlation_id, metadata_json, spans_json, error_json]
        # Handle both old schema (9 cols) and new (10 cols)
        if row.size >= 10
          hash = {
            id: row[0],
            kind: row[1],
            identifier: row[2],
            status: row[3],
            started_at: row[4],
            duration_ms: row[5],
            metadata: row[7] ? JSON.parse(row[7], symbolize_names: true) : {},
            spans: row[8] ? JSON.parse(row[8], symbolize_names: true) : [],
            error: row[9] ? JSON.parse(row[9], symbolize_names: true) : nil
          }
          hash[:correlation_id] = row[6] if row[6]
          hash[:metadata][:correlation_id] ||= row[6] if row[6]
        else
          hash = {
            id: row[0],
            kind: row[1],
            identifier: row[2],
            status: row[3],
            started_at: row[4],
            duration_ms: row[5],
            metadata: row[6] ? JSON.parse(row[6], symbolize_names: true) : {},
            spans: row[7] ? JSON.parse(row[7], symbolize_names: true) : [],
            error: row[8] ? JSON.parse(row[8], symbolize_names: true) : nil
          }
        end
        Trace.from_h(hash)
      end
    end
  end
end
