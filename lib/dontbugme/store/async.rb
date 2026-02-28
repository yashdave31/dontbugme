# frozen_string_literal: true

module Dontbugme
  module Store
    class Async < Base
      def initialize(backend)
        @backend = backend
        @queue = Queue.new
        @thread = start_worker
      end

      def save_trace(trace)
        @queue << [:save, trace]
      end

      def find_trace(trace_id)
        @backend.find_trace(trace_id)
      end

      def search(filters = {})
        @backend.search(filters)
      end

      def cleanup(before:)
        @queue << [:cleanup, before]
      end

      private

      def start_worker
        Thread.new do
          loop do
            action, arg = @queue.pop
            case action
            when :save
              @backend.save_trace(arg)
            when :cleanup
              @backend.cleanup(before: arg)
            end
          end
        end
      end
    end
  end
end
