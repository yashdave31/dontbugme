# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dontbugme::Recorder do
  describe '.record' do
    it 'returns the block result by default (for Rack middleware)' do
      Dontbugme.config.recording_mode = :always
      result = described_class.record(kind: :custom, identifier: 'test') { [200, {}, ['ok']] }
      expect(result).to eq([200, {}, ['ok']])
      expect(result[0]).to eq(200)
      expect(result[1]).to be_a(Hash)
      expect(result[2]).to respond_to(:each)
    end

    it 'returns the trace when return_trace: true (for manual Dontbugme.trace)' do
      Dontbugme.config.recording_mode = :always
      trace = described_class.record(kind: :custom, identifier: 'test', return_trace: true) { 42 }
      expect(trace).to be_a(Dontbugme::Trace)
      expect(trace.identifier).to eq('test')
      expect(trace.status).to eq(:success)
    end

    it 'captures errors and re-raises' do
      Dontbugme.config.recording_mode = :always
      Dontbugme.config.record_on_error = true
      expect {
        described_class.record(kind: :custom, identifier: 'test') { raise 'boom' }
      }.to raise_error(StandardError, 'boom')

      traces = Dontbugme.store.search
      expect(traces.any? { |t| t.status == :error }).to be true
    end
  end
end
