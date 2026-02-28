# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dontbugme::Trace do
  describe '#add_span' do
    it 'adds spans to the trace' do
      trace = described_class.new(kind: :custom, identifier: 'test')
      span = Dontbugme::Span.new(
        category: :sql,
        operation: 'SELECT',
        detail: 'SELECT 1',
        payload: {},
        started_at: 0,
        duration_ms: 1.5,
        source: nil
      )
      trace.add_span(span)
      expect(trace.spans.count).to eq(1)
      expect(trace.spans.first.operation).to eq('SELECT')
    end
  end

  describe '#finish!' do
    it 'sets status and duration' do
      trace = described_class.new(kind: :custom, identifier: 'test')
      trace.finish!
      expect(trace.status).to eq(:success)
      expect(trace.duration_ms).to be >= 0
    end

    it 'captures error when provided' do
      trace = described_class.new(kind: :custom, identifier: 'test')
      error = StandardError.new('test error')
      trace.finish!(error: error)
      expect(trace.status).to eq(:error)
      expect(trace.error[:class]).to eq('StandardError')
      expect(trace.error[:message]).to eq('test error')
    end
  end

  describe '.from_h' do
    it 'deserializes a trace from hash' do
      hash = {
        id: 'tr_abc',
        kind: 'custom',
        identifier: 'test',
        status: 'success',
        started_at: '2025-01-01T00:00:00.000Z',
        duration_ms: 10,
        spans: [],
        metadata: {},
        error: nil,
        truncated_spans_count: 0
      }
      trace = described_class.from_h(hash)
      expect(trace.id).to eq('tr_abc')
      expect(trace.identifier).to eq('test')
      expect(trace.duration_ms).to eq(10)
    end
  end
end
