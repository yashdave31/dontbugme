# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dontbugme::Store::JsonSafe do
  describe '.sanitize' do
    it 'replaces invalid UTF-8 in strings' do
      invalid = "hello\x80world".dup.force_encoding('UTF-8')
      expect(invalid.valid_encoding?).to be false
      result = described_class.sanitize(invalid)
      expect(result.valid_encoding?).to be true
      expect(result).to include("\uFFFD")
    end

    it 'sanitizes nested hashes and arrays' do
      data = { a: { b: "bad\x80".dup.force_encoding('UTF-8') }, c: ["x\x80".dup.force_encoding('UTF-8')] }
      result = described_class.sanitize(data)
      expect(result[:a][:b].valid_encoding?).to be true
      expect(result[:c][0].valid_encoding?).to be true
    end

    it 'produces JSON-encodable output' do
      data = { sql: "SELECT * FROM users WHERE name = '\x80'".dup.force_encoding('UTF-8') }
      result = described_class.sanitize(data)
      expect { result.to_json }.not_to raise_error
    end
  end
end
