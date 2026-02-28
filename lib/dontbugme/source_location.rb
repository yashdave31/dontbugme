# frozen_string_literal: true

module Dontbugme
  class SourceLocation
    class << self
      def capture
        return nil unless Dontbugme.config.recording?
        return nil if Dontbugme.config.source_mode == :off

        config = Dontbugme.config
        limit = config.source_stack_limit
        depth = config.source_mode == :shallow ? 1 : config.source_depth
        filters = config.source_filter

        locations = caller_locations(1, limit)
        return nil if locations.nil? || locations.empty?

        exclude_patterns = %w[dontbugme /gems/ bundler]
        app_frames = locations.select do |loc|
          path = loc.absolute_path || loc.path.to_s
          next false if exclude_patterns.any? { |p| path.include?(p) }
          filters.any? { |f| path.include?(f) }
        end

        return nil if app_frames.empty?

        frames_to_keep = app_frames.first(depth)
        frames_to_keep.map { |loc| format_location(loc) }.join(' <- ')
      end

      private

      def format_location(loc)
        path = loc.absolute_path || loc.path.to_s
        # Use relative path from cwd if possible for shorter output
        base = path
        if defined?(Rails) && Rails.root
          base = Pathname.new(path).relative_path_from(Rails.root).to_s rescue path
        end
        "#{base}:#{loc.lineno} in `#{loc.label}`"
      end
    end
  end
end
