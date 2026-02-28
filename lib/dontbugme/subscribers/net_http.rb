# frozen_string_literal: true

module Dontbugme
  module Subscribers
    class NetHttp
      def self.subscribe
        return unless defined?(Net::HTTP)

        Net::HTTP.prepend(Instrumentation)
      end

      module Instrumentation
        def request(req, body = nil, &block)
          return super unless Dontbugme::Context.active?
          return super unless Dontbugme.config.recording?

          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
          start_wall = Time.now
          response = super
          duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond) - start_time).round(2)

          record_span(req, response, start_wall, duration_ms)
          response
        rescue StandardError => e
          duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond) - start_time).round(2)
          record_span(req, nil, start_wall, duration_ms, error: e)
          raise
        end

        private

        def record_span(req, response, start_wall, duration_ms, error: nil)
          config = Dontbugme.config
          uri = build_uri(req)
          method = req.method
          detail = "#{method} #{uri}"
          payload = {
            method: method,
            url: uri,
            status: response&.code&.to_i
          }
          payload[:error] = error.message if error

          if config.capture_http_body && response&.body
            payload[:response_body] = truncate(response.body, config.max_http_body_size)
          end

          if config.capture_http_headers&.any?
            payload[:request_headers] = capture_headers(req, config.capture_http_headers)
          end

          Dontbugme::Recorder.add_span(
            category: :http,
            operation: method,
            detail: detail,
            payload: payload,
            duration_ms: duration_ms,
            started_at: start_wall
          )
        end

        def build_uri(req)
          path = req.path.to_s.empty? ? '/' : req.path
          "#{use_ssl? ? 'https' : 'http'}://#{address}:#{port}#{path}"
        end

        def capture_headers(req, header_names)
          result = {}
          max = Dontbugme.config.max_http_body_size
          header_map = {
            'content_type' => 'Content-Type',
            'authorization_type' => 'Authorization',
            'authorization' => 'Authorization'
          }
          header_names.each do |name|
            key = header_map[name.to_s.downcase] || name.to_s.split('_').map(&:capitalize).join('-')
            val = req[key]
            result[name.to_s] = truncate(val.to_s, max) if val
          end
          result
        end

        def truncate(str, max)
          return str if str.bytesize <= max

          "#{str.byteslice(0, max)}[truncated]"
        end
      end
    end
  end
end
