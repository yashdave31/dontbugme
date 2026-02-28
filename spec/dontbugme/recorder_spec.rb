# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dontbugme::Recorder do
  describe '.record' do
    it 'returns the trace' do
      trace = described_class.record(kind: :custom, identifier: 'test') { 42 }
      expect(trace).to be_a(Dontbugme::Trace)
      expect(trace.identifier).to eq('test')
      expect(trace.status).to eq(:success)
    end

    it 'captures errors and re-raises' do
      Dontbugme.config.record_on_error = true
      expect {
        described_class.record(kind: :custom, identifier: 'test') { raise 'boom' }
      }.to raise_error(StandardError, 'boom')

      traces = Dontbugme.store.search
      expect(traces.any? { |t| t.status == :error }).to be true
    end
  end
end
