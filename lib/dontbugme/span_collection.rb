# frozen_string_literal: true

module Dontbugme
  class SpanCollection
    include Enumerable

    def initialize(spans)
      @spans = spans.to_a.freeze
    end

    def each(&block)
      @spans.each(&block)
    end

    def count
      @spans.count
    end

    def category(cat)
      @spans.select { |s| s.category == cat.to_sym }
    end

    def method_missing(method_name, *args, &block)
      cat = method_name.to_s.downcase.to_sym
      return category(cat) if known_category?(cat)

      super
    end

    def respond_to_missing?(method_name, include_private = false)
      known_category?(method_name.to_s.downcase.to_sym) || super
    end

    private

    def known_category?(cat)
      %i[sql http redis cache mailer enqueue custom snapshot].include?(cat)
    end
  end
end
