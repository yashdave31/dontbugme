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
      Recorder.record(kind: :custom, identifier: identifier, metadata: metadata, &block)
    end

    def span(name, payload: {}, &block)
      return yield unless Context.active?

      start_mono = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
      start_wall = Time.now
      result = yield
      duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond) - start_mono).round(2)

      Recorder.add_span(
        category: :custom,
        operation: 'span',
        detail: name.to_s,
        payload: payload,
        duration_ms: duration_ms,
        started_at: start_wall
      )
      result
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
