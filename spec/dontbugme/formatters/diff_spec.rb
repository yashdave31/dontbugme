# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dontbugme::Formatters::Diff do
  def make_span(category:, operation:, detail:, payload: {})
    Dontbugme::Span.new(
      category: category,
      operation: operation,
      detail: detail,
      payload: payload,
      started_at: 0,
      duration_ms: 1,
      source: nil
    )
  end

  def make_trace(identifier:, spans:, error: nil)
    trace = Dontbugme::Trace.new(kind: :sidekiq, identifier: identifier)
    spans.each { |s| trace.add_span(s) }
    trace.finish!(error: error)
    trace
  end

  it 'reports identical spans' do
    span = make_span(category: :sql, operation: 'SELECT', detail: 'SELECT 1')
    trace_a = make_trace(identifier: 'Job', spans: [span])
    trace_b = make_trace(identifier: 'Job', spans: [make_span(category: :sql, operation: 'SELECT', detail: 'SELECT 1')])

    output = described_class.format(trace_a, trace_b)
    expect(output).to include('IDENTICAL')
    expect(output).to include('SELECT')
  end

  it 'reports missing spans' do
    span1 = make_span(category: :sql, operation: 'SELECT', detail: 'SELECT 1')
    span2 = make_span(category: :sql, operation: 'UPDATE', detail: 'UPDATE x')
    trace_a = make_trace(identifier: 'Job', spans: [span1, span2])
    trace_b = make_trace(identifier: 'Job', spans: [span1])

    output = described_class.format(trace_a, trace_b)
    expect(output).to include('MISSING')
    expect(output).to include('UPDATE')
  end

  it 'reports new spans' do
    span1 = make_span(category: :sql, operation: 'SELECT', detail: 'SELECT 1')
    trace_a = make_trace(identifier: 'Job', spans: [span1])
    trace_b = make_trace(identifier: 'Job', spans: [span1, make_span(category: :sql, operation: 'INSERT', detail: 'INSERT x')])

    output = described_class.format(trace_a, trace_b)
    expect(output).to include('NEW')
    expect(output).to include('INSERT')
  end

  it 'reports exception when only in B' do
    span = make_span(category: :sql, operation: 'SELECT', detail: 'SELECT 1')
    trace_a = make_trace(identifier: 'Job', spans: [span])
    trace_b = make_trace(identifier: 'Job', spans: [span], error: StandardError.new('boom'))

    output = described_class.format(trace_a, trace_b)
    expect(output).to include('NEW')
    expect(output).to include('EXCEPTION')
    expect(output).to include('boom')
  end
end
