# frozen_string_literal: true

module Dontbugme
  module Middleware
    class Sidekiq
      def call(_worker, job, _queue)
        return yield unless Dontbugme.config.recording?

        job_class = job['class'] || job[:class] || 'Unknown'
        return yield unless Dontbugme.config.should_record_job?(job_class)
        jid = job['jid'] || job[:jid] || SecureRandom.hex(8)
        correlation_id = job['correlation_id'] || job[:correlation_id] || Correlation.current
        Correlation.current = correlation_id

        identifier = "#{job_class} (jid=#{jid})"

        metadata = {
          jid: jid,
          queue: job['queue'] || job[:queue],
          args: job['args'] || job[:args],
          correlation_id: correlation_id
        }

        Recorder.record(kind: :sidekiq, identifier: identifier, metadata: metadata) do
          yield
        end
      ensure
        Correlation.clear!
      end
    end
  end
end
