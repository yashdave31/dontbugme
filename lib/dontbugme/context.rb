# frozen_string_literal: true

module Dontbugme
  class Context
    KEY = :dontbugme_trace

    class << self
      def current
        Thread.current[KEY]
      end

      def current=(trace)
        Thread.current[KEY] = trace
      end

      def active?
        !current.nil?
      end

      def clear!
        Thread.current[KEY] = nil
      end
    end
  end
end
