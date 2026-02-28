# frozen_string_literal: true

module Dontbugme
  module Store
    class Base
      def save_trace(trace)
        raise NotImplementedError
      end

      def find_trace(trace_id)
        raise NotImplementedError
      end

      def search(filters = {})
        raise NotImplementedError
      end

      def cleanup(before:)
        raise NotImplementedError
      end
    end
  end
end
