# frozen_string_literal: true

module Dontbugme
  class Configuration
    attr_accessor :store,
                  :sqlite_path,
                  :postgresql_connection,
                  :enable_web_ui,
                  :web_ui_mount_path,
                  :recording_mode,
                  :record_on_error,
                  :record_jobs,
                  :record_requests,
                  :sample_rate,
                  :capture_sql_binds,
                  :capture_http_headers,
                  :capture_http_body,
                  :capture_redis_values,
                  :source_mode,
                  :source_filter,
                  :source_depth,
                  :source_stack_limit,
                  :max_spans_per_trace,
                  :span_overflow_strategy,
                  :max_sql_bind_size,
                  :max_http_body_size,
                  :max_redis_value_size,
                  :max_span_detail_size,
                  :max_trace_buffer_bytes,
                  :retention,
                  :max_traces,
                  :async_store

    def initialize
      apply_environment_defaults
    end

    def apply_environment_defaults
      env = defined?(Rails) ? Rails.env.to_s : 'development'

      case env
      when 'test'
        apply_test_defaults
      when 'production'
        apply_production_defaults
      else
        apply_development_defaults
      end
    end

    def apply_development_defaults
      self.store = :sqlite
      self.sqlite_path = 'tmp/inspector/inspector.db'
      self.postgresql_connection = nil
      self.enable_web_ui = true
      self.web_ui_mount_path = '/inspector'
      self.recording_mode = :always
      self.record_on_error = true
      self.record_jobs = :all
      self.record_requests = :all
      self.sample_rate = 1.0
      self.capture_sql_binds = true
      self.capture_http_headers = []
      self.capture_http_body = false
      self.capture_redis_values = false
      self.source_mode = :full
      self.source_filter = %w[app/ lib/]
      self.source_depth = 3
      self.source_stack_limit = 50
      self.max_spans_per_trace = 1_000
      self.span_overflow_strategy = :count
      self.max_sql_bind_size = 4_096
      self.max_http_body_size = 8_192
      self.max_redis_value_size = 512
      self.max_span_detail_size = 8_192
      self.max_trace_buffer_bytes = 10 * 1024 * 1024 # 10 MB
      self.retention = retention_seconds(72, :hours)
      self.max_traces = 10_000
      self.async_store = false
    end

    def apply_test_defaults
      apply_development_defaults
      self.store = :memory
      self.recording_mode = :off
      self.enable_web_ui = false
      self.record_on_error = false
      self.max_trace_buffer_bytes = 5 * 1024 * 1024 # 5 MB
    end

    def apply_production_defaults
      apply_development_defaults
      self.store = :postgresql
      self.enable_web_ui = false
      self.recording_mode = :selective
      self.record_on_error = true
      self.capture_sql_binds = false
      self.source_mode = :shallow
      self.source_depth = 1
      self.source_stack_limit = 30
      self.max_spans_per_trace = 500
      self.max_sql_bind_size = 512
      self.max_http_body_size = 1_024
      self.max_span_detail_size = 2_048
      self.max_trace_buffer_bytes = 5 * 1024 * 1024 # 5 MB
      self.retention = retention_seconds(24, :hours)
      self.async_store = true
    end

    def recording?
      return false if recording_mode == :off
      return true if recording_mode == :always

      # :selective — caller (Recorder) decides based on record_jobs, record_requests, etc.
      true
    end

    def should_record_job?(job_class)
      return false if record_jobs == :none
      return true if record_jobs == :all
      return record_jobs.include?(job_class.to_s) if record_jobs.is_a?(Array)

      false
    end

    def should_record_request?(env)
      return false if record_requests == :none
      return true if record_requests == :all
      return record_requests.call(env) if record_requests.respond_to?(:call)

      false
    end

    private

    def retention_seconds(value, unit)
      return value if value.is_a?(Integer)
      return value.to_i if defined?(ActiveSupport) && value.respond_to?(:to_i)

      case unit
      when :hours then value * 3600
      when :days then value * 86400
      else value
      end
    end
  end
end
