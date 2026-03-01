# frozen_string_literal: true

require 'securerandom'

module Dontbugme
  class Error < StandardError; end

  class << self
    attr_writer :config, :store

    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
    end

    def store
      @store ||= build_store
    end

    def trace(identifier, metadata: {}, &block)
      Recorder.record(kind: :custom, identifier: identifier, metadata: metadata, return_trace: true, &block)
    end

    def span(name, payload: {}, capture_output: true, &block)
      return yield unless Context.active?

      start_mono = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
      start_wall = Time.now
      result = yield
      duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond) - start_mono).round(2)

      span_payload = payload.dup
      if capture_output && config.capture_span_output
        span_payload[:output] = format_output_value(result)
      end

      Recorder.add_span(
        category: :custom,
        operation: 'span',
        detail: name.to_s,
        payload: span_payload,
        duration_ms: duration_ms,
        started_at: start_wall
      )
      result
    end

    # Captures input and output of in-house calculations for value transformation inspection.
    # Example: token = Dontbugme.observe('token increment', token) { token + 1 }
    def observe(name, input = nil, &block)
      return yield unless Context.active?

      payload = {}
      payload[:input] = format_output_value(input) unless input.nil?
      span(name, payload: payload, capture_output: true, &block)
    end

    def snapshot(data)
      return unless Context.active?

      payload = data.is_a?(Hash) ? data : { value: data }
      Recorder.add_span(
        category: :snapshot,
        operation: 'snapshot',
        detail: 'snapshot',
        payload: payload,
        duration_ms: 0,
        started_at: Time.now
      )
    end

    def tag(**metadata)
      return unless Context.active?

      Context.current&.merge_tags!(**metadata)
    end

    private

    def format_output_value(val)
      return nil if val.nil?

      max = config.max_span_detail_size
      str = if val.is_a?(Array)
              format_array(val)
            elsif val.is_a?(Hash)
              format_hash(val)
            elsif defined?(ActiveRecord::Base) && val.is_a?(ActiveRecord::Base)
              val.inspect
            elsif defined?(ActiveRecord::Relation) && val.is_a?(ActiveRecord::Relation)
              "#{val.to_sql} (relation)"
            else
              val.to_s
            end
      str.bytesize > max ? "#{str.byteslice(0, max)}...[truncated]" : str
    rescue StandardError
      val.class.name
    end

    def format_array(ary)
      return '[]' if ary.empty?

      preview = ary.first(5).map { |v| format_single_value(v) }.join(', ')
      ary.size > 5 ? "[#{preview}, ... (#{ary.size} total)]" : "[#{preview}]"
    end

    def format_hash(hash)
      return '{}' if hash.empty?

      preview = hash.first(5).map { |k, v| "#{k}: #{format_single_value(v)}" }.join(', ')
      hash.size > 5 ? "{#{preview}, ...}" : "{#{preview}}"
    end

    def format_single_value(v)
      if defined?(ActiveRecord::Base) && v.is_a?(ActiveRecord::Base)
        v.respond_to?(:id) ? "#<#{v.class.name} id=#{v.id}>" : "#<#{v.class.name}>"
      elsif v.is_a?(Hash)
        '{...}'
      elsif v.is_a?(Array)
        '[...]'
      else
        v.to_s
      end
    end

    def build_store
      store = case config.store
              when :sqlite
                Store::Sqlite.new(path: config.sqlite_path)
              when :memory
                Store::Memory.new
              when :postgresql
                conn = config.postgresql_connection || (defined?(ActiveRecord::Base) && ActiveRecord::Base.connection)
                conn ? Store::Postgresql.new(connection: conn) : Store::Sqlite.new(path: config.sqlite_path)
              else
                Store::Sqlite.new(path: config.sqlite_path)
              end
      config.async_store ? Store::Async.new(store) : store
    end
  end
end

require 'dontbugme/version'
require 'dontbugme/configuration'
require 'dontbugme/span'
require 'dontbugme/variable_tracker'
require 'dontbugme/span_collection'
require 'dontbugme/trace'
require 'dontbugme/context'
require 'dontbugme/source_location'
require 'dontbugme/recorder'
require 'dontbugme/subscribers/base'
require 'dontbugme/subscribers/active_record'
require 'dontbugme/subscribers/net_http'
require 'dontbugme/subscribers/redis'
require 'dontbugme/subscribers/cache'
require 'dontbugme/subscribers/action_mailer'
require 'dontbugme/subscribers/active_job'
require 'dontbugme/store/base'
require 'dontbugme/store/memory'
require 'dontbugme/store/sqlite'
require 'dontbugme/store/postgresql'
require 'dontbugme/store/async'
require 'dontbugme/cleanup_job'
require 'dontbugme/correlation'
require 'dontbugme/middleware/sidekiq'
require 'dontbugme/middleware/sidekiq_client'
require 'dontbugme/middleware/rack'
require 'dontbugme/formatters/timeline'
require 'dontbugme/formatters/json'
require 'dontbugme/formatters/diff'
require 'dontbugme/cli'

# Load Railtie when Rails is present (must be after all other requires)
if defined?(Rails)
  require 'dontbugme/railtie'
end
