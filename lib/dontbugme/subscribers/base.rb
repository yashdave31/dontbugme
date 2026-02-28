# frozen_string_literal: true

module Dontbugme
  module Subscribers
    class Base
      def self.subscribe
        raise NotImplementedError
      end

      def self.call(*args)
        new.call(*args)
      end

      def call(_name, _start, _finish, _id, _payload)
        raise NotImplementedError
      end
    end
  end
end
