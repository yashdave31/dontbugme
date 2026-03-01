# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Dontbugme API' do
  describe '.span' do
    it 'records a custom span' do
      trace = Dontbugme.trace('test') do
        Dontbugme.span('my work') { 42 }
      end
      expect(trace.spans.custom.count).to eq(1)
      expect(trace.spans.custom.first.detail).to eq('my work')
    end
  end

  describe '.observe' do
    it 'records input and output for value transformations' do
      trace = Dontbugme.trace('test') do
        result = Dontbugme.observe('token increment', 'abc123') { 'abc124' }
        expect(result).to eq('abc124')
      end
      span = trace.spans.custom.find { |s| s.detail == 'token increment' }
      expect(span).not_to be_nil
      expect(span.payload[:input]).to eq('abc123')
      expect(span.payload[:output]).to eq('abc124')
    end

    it 'returns the block result' do
      result = Dontbugme.trace('test') do
        Dontbugme.observe('add one', 5) { 6 }
      end
      expect(result).to be_a(Dontbugme::Trace)
      span = result.spans.custom.first
      expect(span.payload[:output]).to eq('6')
    end
  end

  describe 'automatic variable tracking' do
    it 'captures local variable changes between lines when enabled' do
      Dontbugme.config.capture_variable_changes = true
      Dontbugme.config.source_filter = %w[app/ lib/ spec/]
      Dontbugme::VariableTracker.subscribe
      begin
        # Use eval with explicit path; need 3+ lines so we get a line event after the transformation
        code = <<~RUBY
          token = 'abc123'
          token = token + 'x'
          token
        RUBY
        trace = Dontbugme.trace('var change test') do
          eval(code, binding, 'app/services/token_service.rb', 1)
        end
        observe_spans = trace.spans.custom.select { |s| s.operation == 'observe' }
        span = observe_spans.find { |s| s.payload[:input] == 'abc123' && s.payload[:output] == 'abc123x' }
        expect(span).not_to be_nil, "Expected observe span with token abc123 -> abc123x, got: #{observe_spans.map { |s| s.payload }.inspect}"
      ensure
        Dontbugme::VariableTracker.unsubscribe
        Dontbugme.config.capture_variable_changes = false
        Dontbugme.config.source_filter = %w[app/ lib/]
      end
    end
  end

  describe '.snapshot' do
    it 'records a snapshot span' do
      trace = Dontbugme.trace('test') do
        Dontbugme.snapshot(user_id: 1, amount: 100)
      end
      expect(trace.spans.snapshot.count).to eq(1)
      expect(trace.spans.snapshot.first.payload[:user_id]).to eq(1)
    end
  end

  describe '.tag' do
    it 'merges metadata into the trace' do
      trace = Dontbugme.trace('test') do
        Dontbugme.tag(region: 'us-east', tier: 'premium')
      end
      expect(trace.metadata[:region]).to eq('us-east')
      expect(trace.metadata[:tier]).to eq('premium')
    end
  end
end
