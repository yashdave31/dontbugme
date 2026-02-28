# frozen_string_literal: true

module Dontbugme
  module Middleware
    class SidekiqClient
      def call(_worker_class, job, _queue, _redis_pool)
        if Correlation.current
          job['correlation_id'] = Correlation.current
        end
        yield
      end
    end
  end
end
