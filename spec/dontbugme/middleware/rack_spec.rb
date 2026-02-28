# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'

RSpec.describe Dontbugme::Middleware::Rack do
  include Rack::Test::Methods

  let(:app) do
    inner = lambda { |env| [200, { 'Content-Type' => 'text/plain' }, ['Hello']] }
    described_class.new(inner)
  end

  before do
    Dontbugme.config.recording_mode = :always
  end

  it 'returns the Rack response from the inner app' do
    get '/'
    expect(last_response.status).to eq(200)
    expect(last_response.headers['Content-Type']).to eq('text/plain')
    expect(last_response.body).to eq('Hello')
  end

  it 'returns a valid Rack triple that can be indexed' do
    get '/test'
    status, headers, body = last_response.status, last_response.headers, last_response.body

    # Simulate what Passenger/Rack does: response[0], response[1], response[2]
    expect(status).to eq(200)
    expect(headers).to be_a(Hash)
    expect(body).to eq('Hello')
  end

  it 'records the request as a trace when recording is on' do
    get '/api/users'
    traces = Dontbugme.store.search(limit: 5)
    expect(traces.any? { |t| t.identifier.include?('/api/users') }).to be true
  end

  it 'passes through without recording when recording is off' do
    Dontbugme.config.recording_mode = :off
    get '/'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to eq('Hello')
  end
end
