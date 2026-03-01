# frozen_string_literal: true

module Dontbugme
  module Middleware
    class Rack
      def initialize(app)
        @app = app
      end

      def call(env)
        return @app.call(env) unless Dontbugme.config.recording?
        return @app.call(env) unless Dontbugme.config.should_record_request?(env)

        request = ::Rack::Request.new(env)
        path = request.path.to_s
        mount_path = Dontbugme.config.web_ui_mount_path.to_s.chomp('/')
        return @app.call(env) if mount_path.to_s != '' && (path == mount_path || path.start_with?("#{mount_path}/"))

        request_id = env['action_dispatch.request_id'] || request.get_header('HTTP_X_REQUEST_ID') || SecureRandom.uuid
        correlation_id = env['HTTP_X_CORRELATION_ID'] || Correlation.generate
        Correlation.current = correlation_id

        method = request.request_method
        identifier = "#{method} #{path}"

        metadata = {
          request_id: request_id,
          correlation_id: correlation_id,
          method: method,
          path: path
        }

        Recorder.record(kind: :request, identifier: identifier, metadata: metadata) do
          @app.call(env)
        end
      ensure
        Correlation.clear!
      end
    end
  end
end
