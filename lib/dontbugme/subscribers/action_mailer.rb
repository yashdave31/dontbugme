# frozen_string_literal: true

module Dontbugme
  module Subscribers
    class ActionMailer < Base
      EVENT = 'deliver.action_mailer'

      def self.subscribe
        return unless defined?(::ActionMailer::Base)

        ::ActiveSupport::Notifications.subscribe(EVENT) do |*args|
          call(*args)
        end
      end

      def call(_name, start, finish, _id, payload)
        return unless Context.active?
        return unless Dontbugme.config.recording?

        duration_ms = ((finish - start) * 1000).round(2)
        mailer = payload[:mailer] || payload['mailer']
        action = payload[:action] || payload['action']
        message_id = payload[:message_id] || payload['message_id']

        detail = "#{mailer}##{action}"
        payload_data = {
          mailer: mailer,
          action: action,
          message_id: message_id
        }
        payload_data[:to] = payload[:to] if payload[:to]
        payload_data[:subject] = truncate(payload[:subject].to_s, 100) if payload[:subject]

        Recorder.add_span(
          category: :mailer,
          operation: 'deliver',
          detail: detail,
          payload: payload_data,
          duration_ms: duration_ms,
          started_at: start
        )
      end

      private

      def truncate(str, max)
        return str if str.length <= max

        "#{str[0, max]}..."
      end
    end
  end
end
