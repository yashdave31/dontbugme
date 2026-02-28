# frozen_string_literal: true

module Dontbugme
  class Span
    attr_reader :id, :category, :operation, :detail, :payload, :started_at, :duration_ms, :source

    def initialize(
      category:,
      operation:,
      detail:,
      payload: {},
      started_at:,
      duration_ms:,
      source: nil
    )
      @id = "sp_#{SecureRandom.hex(4)}"
      @category = category.to_sym
      @operation = operation.to_s
      max_size = defined?(Dontbugme) && Dontbugme.respond_to?(:config) ? Dontbugme.config&.max_span_detail_size : 8192
      @detail = truncate_string(detail.to_s, max_size)
      @payload = payload
      @started_at = started_at
      @duration_ms = duration_ms
      @source = source
    end

    def to_h
      {
        id: id,
        category: category,
        operation: operation,
        detail: detail,
        payload: payload,
        started_at: started_at,
        duration_ms: duration_ms,
        source: source
      }
    end

    def self.from_h(hash)
      new(
        category: hash[:category] || hash['category'],
        operation: hash[:operation] || hash['operation'],
        detail: hash[:detail] || hash['detail'],
        payload: (hash[:payload] || hash['payload'] || {}).transform_keys(&:to_sym),
        started_at: hash[:started_at] || hash['started_at'],
        duration_ms: hash[:duration_ms] || hash['duration_ms'],
        source: hash[:source] || hash['source']
      )
    end

    private

    def truncate_string(str, max_size)
      return str if str.nil? || max_size.nil?
      return str if str.bytesize <= max_size

      truncated = str.byteslice(0, max_size)
      original_size = str.bytesize
      "#{truncated}[truncated, #{format_bytes(original_size)} original]"
    end

    def format_bytes(bytes)
      return "#{bytes}B" if bytes < 1024
      return "#{(bytes / 1024.0).round(1)}KB" if bytes < 1024 * 1024

      "#{(bytes / (1024.0 * 1024)).round(1)}MB"
    end
  end
end
