# frozen_string_literal: true

module Dontbugme
  module Store
    class Async < Base
      def initialize(backend)
        @backend = backend
        @queue = Queue.new
        @pid = Process.pid
        @thread = start_worker
      end

      def save_trace(trace)
        restart_worker_if_forked
        @queue << [:save, trace]
      end

      def find_trace(trace_id)
        @backend.find_trace(trace_id)
      end

      def search(filters = {})
        @backend.search(filters)
      end

      def cleanup(before:)
        restart_worker_if_forked
        @queue << [:cleanup, before]
      end

      private

      def restart_worker_if_forked
        return if Process.pid == @pid

        @pid = Process.pid
        @thread = start_worker
      end

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
          rescue StandardError => e
            warn "[Dontbugme] Async store error: #{e.class} #{e.message}"
          end
        end
      end
    end
  end
end
