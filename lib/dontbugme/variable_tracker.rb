# frozen_string_literal: true

module Dontbugme
  # Automatically captures local variable changes between lines using TracePoint.
  # Emits observe-style spans when variables change, so you can inspect value
  # transformations without manual Dontbugme.observe calls.
  class VariableTracker
    THREAD_KEY = :dontbugme_variable_tracker_state
    THREAD_PATH_KEY = :dontbugme_variable_tracker_path
    IN_TRACKER_KEY = :dontbugme_variable_tracker_in_callback
    SKIP_VARS = %w[_ result trace e ex].freeze
    TRACKABLE_CLASSES = [String, Integer, Float, Symbol, TrueClass, FalseClass, NilClass].freeze

    class << self
      def subscribe
        return if @subscribed

        @trace_point = TracePoint.new(:line) { |tp| handle_line(tp) }
        @trace_point.enable
        @subscribed = true
      end

      def unsubscribe
        return unless @subscribed

        @trace_point&.disable
        @trace_point = nil
        @subscribed = false
      end

      def handle_line(tp)
        return if Thread.current[IN_TRACKER_KEY]
        return unless Dontbugme.config.recording?
        return unless Dontbugme.config.capture_variable_changes
        return unless Context.active?

        path = tp.path.to_s
        return if path.include?('dontbugme') || path.include?('/gems/') || path.include?('bundler')
        return unless Dontbugme.config.source_filter.any? { |f| path.include?(f) }

        binding = tp.binding
        return unless binding

        Thread.current[IN_TRACKER_KEY] = true
        begin
          current = extract_locals(binding)
          prev = Thread.current[THREAD_KEY]
          prev_path = Thread.current[THREAD_PATH_KEY]
          # Only diff when we're in the same file (avoid cross-scope false positives)
          if prev && prev_path == path
            diff_and_emit(prev, current, tp)
          end
          Thread.current[THREAD_KEY] = current
          Thread.current[THREAD_PATH_KEY] = path
        ensure
          Thread.current[IN_TRACKER_KEY] = false
        end
      end

      def clear_state!
        Thread.current[THREAD_KEY] = nil
        Thread.current[THREAD_PATH_KEY] = nil
      end

      private

      def extract_locals(binding)
        return {} unless binding.respond_to?(:local_variables)

        binding.local_variables.each_with_object({}) do |name, h|
          next if SKIP_VARS.include?(name.to_s)
          next if name.to_s.start_with?('_')

          begin
            h[name] = binding.local_variable_get(name)
          rescue StandardError
            # Some vars (e.g. from C extensions) may not be readable
          end
        end
      end

      def diff_and_emit(prev, current, tp)
        changed = current.select do |name, new_val|
          prev_val = prev[name]
          !values_equal?(prev_val, new_val)
        end
        return if changed.empty?

        changed.each do |name, new_val|
          prev_val = prev[name]
          emit_observe(name, prev_val, new_val, tp)
        end
      end

      def values_equal?(a, b)
        return true if a.equal?(b)
        return a == b if a.nil? || b.nil?

        a == b
      rescue StandardError
        false
      end

      def emit_observe(name, input, output, tp)
        return unless (input.nil? || trackable_value?(input)) && (output.nil? || trackable_value?(output))

        detail = "#{name} changed"
        payload = {
          input: format_value(input),
          output: format_value(output)
        }
        Recorder.add_span(
          category: :custom,
          operation: 'observe',
          detail: detail,
          payload: payload,
          duration_ms: 0,
          started_at: Time.now
        )
      end

      def format_value(val)
        return nil if val.nil?

        Dontbugme.send(:format_output_value, val)
      rescue StandardError
        val.class.name
      end

      def trackable_value?(val)
        return true if val.nil?
        return true if TRACKABLE_CLASSES.any? { |c| val.is_a?(c) }
        return true if val.is_a?(Array) && val.size <= 10 && val.all? { |v| trackable_value?(v) }
        return true if val.is_a?(Hash) && val.size <= 10 && val.values.all? { |v| trackable_value?(v) }

        false
      end
    end
  end
end
