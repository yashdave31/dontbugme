# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dontbugme::SpanCollection do
  let(:spans) do
    [
      double(category: :sql, operation: 'SELECT'),
      double(category: :sql, operation: 'INSERT'),
      double(category: :http, operation: 'GET'),
      double(category: :redis, operation: 'SET')
    ]
  end

  let(:collection) { described_class.new(spans) }

  describe '#sql' do
    it 'returns spans with category sql' do
      expect(collection.sql.count).to eq(2)
    end
  end

  describe '#http' do
    it 'returns spans with category http' do
      expect(collection.http.count).to eq(1)
    end
  end

  describe '#category' do
    it 'returns spans for given category' do
      expect(collection.category(:redis).count).to eq(1)
    end
  end

  describe '#count' do
    it 'returns total span count' do
      expect(collection.count).to eq(4)
    end
  end
end
