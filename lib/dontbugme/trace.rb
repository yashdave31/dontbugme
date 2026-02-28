# frozen_string_literal: true

require 'time'

module Dontbugme
  class Trace
    attr_reader :id, :kind, :identifier, :metadata, :correlation_id
    attr_accessor :status, :error, :truncated_spans_count

    def initialize(kind:, identifier:, metadata: {})
      @id = "tr_#{SecureRandom.hex(6)}"
      @kind = kind.to_sym
      @identifier = identifier.to_s
      @metadata = metadata
      @correlation_id = metadata[:correlation_id] || metadata['correlation_id']
      @spans = []
      @started_at_utc = Time.now.utc
      @started_at_monotonic = now_monotonic_ms
      @finished_at = nil
      @status = :success
      @error = nil
      @truncated_spans_count = 0
    end

    def merge_tags!(**tags)
      @metadata.merge!(tags.transform_keys(&:to_sym))
    end

    def add_span(span)
      config = Dontbugme.config
      max_spans = config.max_spans_per_trace

      if @spans.size >= max_spans
        @truncated_spans_count += 1
        return
      end

      @spans << span
    end

    def spans
      @span_collection ||= SpanCollection.new(@spans)
    end

    def raw_spans
      @spans.dup
    end

    def finish!(error: nil)
      @finished_at = now_monotonic_ms
      @status = error ? :error : :success
      @error = error ? format_error(error) : nil
    end

    def started_at_utc
      @started_at_utc
    end

    # Monotonic start time, used for computing span offsets during recording
    def started_at_monotonic
      @started_at_monotonic
    end

    # Wall-clock start time for computing span offsets from ActiveSupport::Notifications
    def started_at_time
      @started_at_utc
    end

    def duration_ms
      return @duration_ms_stored if defined?(@duration_ms_stored) && @duration_ms_stored
      return nil unless @finished_at

      (@finished_at - @started_at_monotonic).round(2)
    end

    def to_h
      finished_at_time = @finished_at ? (@started_at_utc + (duration_ms || 0) / 1000.0) : nil
      {
        id: id,
        kind: kind,
        identifier: identifier,
        started_at: format_time(started_at_utc),
        finished_at: finished_at_time ? format_time(finished_at_time) : nil,
        duration_ms: duration_ms,
        status: status,
        error: error,
        metadata: metadata,
        correlation_id: correlation_id,
        spans: raw_spans.map(&:to_h),
        truncated_spans_count: truncated_spans_count
      }
    end

    def self.from_h(hash)
      trace = allocate
      trace.instance_variable_set(:@id, hash[:id] || hash['id'])
      trace.instance_variable_set(:@kind, (hash[:kind] || hash['kind']).to_sym)
      trace.instance_variable_set(:@identifier, hash[:identifier] || hash['identifier'])
      trace.instance_variable_set(:@metadata, (hash[:metadata] || hash['metadata'] || {}).transform_keys(&:to_sym))
      trace.instance_variable_set(:@correlation_id, hash[:correlation_id] || hash['correlation_id'])
      trace.instance_variable_set(:@status, (hash[:status] || hash['status'] || :success).to_sym)
      trace.instance_variable_set(:@error, hash[:error] || hash['error'])
      trace.instance_variable_set(:@truncated_spans_count, hash[:truncated_spans_count] || hash['truncated_spans_count'] || 0)

      spans_data = hash[:spans] || hash['spans'] || []
      trace.instance_variable_set(:@spans, spans_data.map { |s| Span.from_h(s) })

      started = hash[:started_at] || hash['started_at']
      trace.instance_variable_set(:@started_at_utc, started ? Time.parse(started.to_s) : nil)
      trace.instance_variable_set(:@started_at_monotonic, 0)
      trace.instance_variable_set(:@finished_at, nil)
      trace.instance_variable_set(:@duration_ms_stored, hash[:duration_ms] || hash['duration_ms'])
      trace
    end

    # Convenience for trace.spans by category
    def spans_by_category(cat)
      spans.select { |s| s.category == cat.to_sym }
    end

    def to_timeline(only: nil, slow: nil)
      Formatters::Timeline.format(self, only: only, slow: slow)
    end

    private

    def now_monotonic_ms
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
    end

    def format_time(t)
      t.respond_to?(:iso8601) ? t.iso8601(3) : t.utc.strftime('%Y-%m-%dT%H:%M:%S.%LZ')
    end

    def format_error(err)
      {
        class: err.class.name,
        message: err.message,
        backtrace: err.backtrace&.first(20)
      }
    end
  end
end
