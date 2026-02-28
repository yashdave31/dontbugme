# frozen_string_literal: true

require 'thor'

module Dontbugme
  class CLI < Thor
    desc 'list', 'List recent traces'
    option :limit, type: :numeric, default: 20, aliases: '-n'
    def list
      ensure_loaded
      traces = store.search(limit: options[:limit])
      display_list(traces)
    end

    desc 'show TRACE_ID', 'Show a single trace'
    option :only, type: :string, desc: 'Filter spans by category (sql, http, etc.)'
    option :slow, type: :numeric, desc: 'Only show spans slower than N ms'
    option :json, type: :boolean, default: false
    def show(trace_id)
      ensure_loaded
      trace = store.find_trace(trace_id)
      if trace.nil?
        puts "Trace not found: #{trace_id}"
        exit 1
      end

      if options[:json]
        puts Formatters::Json.format(trace)
      else
        puts Formatters::Timeline.format(trace, only: options[:only], slow: options[:slow])
      end
    end

    desc 'diff TRACE_A TRACE_B', 'Compare two traces'
    def diff(trace_id_a, trace_id_b)
      ensure_loaded
      trace_a = store.find_trace(trace_id_a)
      trace_b = store.find_trace(trace_id_b)
      if trace_a.nil?
        puts "Trace not found: #{trace_id_a}"
        exit 1
      end
      if trace_b.nil?
        puts "Trace not found: #{trace_id_b}"
        exit 1
      end
      puts Formatters::Diff.format(trace_a, trace_b)
    end

    desc 'trace TRACE_ID', 'Show trace and follow correlation chain'
    option :follow, type: :boolean, default: false, aliases: '-f'
    def trace(trace_id)
      ensure_loaded
      root = store.find_trace(trace_id)
      if root.nil?
        puts "Trace not found: #{trace_id}"
        exit 1
      end

      if options[:follow]
        cid = root.correlation_id || root.metadata[:correlation_id]
        if cid.nil? || cid.to_s.empty?
          puts "No correlation ID for trace #{trace_id}. Showing single trace."
          puts Formatters::Timeline.format(root)
          return
        end
        traces = store.search(correlation_id: cid, limit: 100)
        puts format_correlation_tree(traces, root)
      else
        puts Formatters::Timeline.format(root)
      end
    end

    desc 'search', 'Search traces'
    option :status, type: :string, desc: 'Filter by status (success, error)'
    option :kind, type: :string, desc: 'Filter by kind (sidekiq, request, custom)'
    option :identifier, type: :string, desc: 'Filter by identifier (partial match)'
    option :class, type: :string, desc: 'Filter by job/request class (e.g. SendInvoiceJob)'
    option :limit, type: :numeric, default: 20
    def search
      ensure_loaded
      filters = { limit: options[:limit] }
      filters[:status] = options[:status] if options[:status]
      filters[:kind] = options[:kind] if options[:kind]
      filters[:identifier] = options[:identifier] || options[:class]
      traces = store.search(filters)
      display_list(traces)
    end

    default_task :list

    private

    def ensure_loaded
      # Gem is loaded by bin/dontbugme; this is a no-op when used as a gem
      require 'dontbugme' unless defined?(Dontbugme)
    end

    def store
      Dontbugme.store
    end

    def display_list(traces)
      return puts('No traces found.') if traces.empty?

      rows = traces.map do |trace|
        [
          trace.id,
          truncate(trace.identifier, 24),
          status_icon(trace.status),
          duration_str(trace)
        ]
      end

      # Simple table
      col_widths = [12, 26, 6, 10]
      puts ''
      puts row_str(['Trace ID', 'Identifier', 'Status', 'Duration'], col_widths)
      puts row_str(['-' * 12, '-' * 24, '-' * 4, '-' * 8], col_widths)
      rows.each { |r| puts row_str(r, col_widths) }
      puts ''
    end

    def row_str(cols, widths)
      cols.each_with_index.map { |c, i| c.to_s.ljust(widths[i]) }.join('  ')
    end

    def truncate(str, max)
      return str if str.length <= max

      "#{str[0, max - 3]}..."
    end

    def status_icon(status)
      status.to_s == 'success' ? '✓' : '✗'
    end

    def duration_str(trace)
      ms = trace.duration_ms
      ms ? "#{ms.round}ms" : '-'
    end

    def format_correlation_tree(traces, root)
      lines = []
      lines << ''
      lines << "  Correlation: #{root.correlation_id || root.metadata[:correlation_id]}"
      lines << '  ' + ('─' * 60)
      lines << ''

      # Order: request first, then jobs by started_at
      sorted = traces.sort_by do |t|
        kind_order = { request: 0, sidekiq: 1, custom: 2 }
        [kind_order[t.kind] || 3, t.started_at_utc.to_s]
      end

      display_trace = lambda do |t|
        icon = t.status == :success ? '✓' : '✗'
        duration = t.duration_ms ? "#{t.duration_ms.round}ms" : '-'
        "#{t.identifier} (#{t.id}, #{duration}, #{t.status})"
      end

      sorted.each_with_index do |t, i|
        prefix = i.zero? ? '' : (i == sorted.size - 1 ? '└── ' : '├── ')
        lines << "  #{prefix}#{display_trace.call(t)}"
      end

      lines << ''
      lines.join("\n")
    end
  end
end
