# frozen_string_literal: true

module Dontbugme
  module Formatters
    class Json
      def self.format(trace)
        trace.to_h.to_json
      end
    end
  end
end
