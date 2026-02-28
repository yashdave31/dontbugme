# frozen_string_literal: true

require 'dontbugme'

RSpec.configure do |config|
  config.before do
    Dontbugme.config.store = :memory
    Dontbugme.store = Dontbugme::Store::Memory.new
  end
end
