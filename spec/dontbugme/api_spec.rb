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
