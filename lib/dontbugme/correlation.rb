# frozen_string_literal: true

module Dontbugme
  module Correlation
    KEY = :dontbugme_correlation_id

    class << self
      def current
        Thread.current[KEY]
      end

      def current=(id)
        Thread.current[KEY] = id
      end

      def generate
        "corr_#{SecureRandom.hex(8)}"
      end

      def clear!
        Thread.current[KEY] = nil
      end
    end
  end
end
