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

  it 'returns response that Puma can process (status.to_i, etc.)' do
    # Puma calls response[0].to_i on the status - must not receive a Trace object
    response = app.call(Rack::MockRequest.env_for('/'))
    expect(response).to be_an(Array)
    expect(response.size).to eq(3)
    expect(response[0]).to eq(200)
    expect(response[0]).to respond_to(:to_i)
    expect(response[0].to_i).to eq(200)
    expect(response[1]).to be_a(Hash)
    expect(response[2]).to respond_to(:each)
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

  it 'does not record traces for requests to the web UI mount path' do
    Dontbugme.config.web_ui_mount_path = '/inspector'
    get '/inspector'
    expect(last_response.status).to eq(200)
    traces = Dontbugme.store.search(limit: 10)
    expect(traces.none? { |t| t.identifier.include?('/inspector') }).to be true
  end

  it 'does not record traces for requests under the web UI mount path' do
    Dontbugme.config.web_ui_mount_path = '/inspector'
    get '/inspector/traces/tr_abc123'
    expect(last_response.status).to eq(200)
    traces = Dontbugme.store.search(limit: 10)
    expect(traces.none? { |t| t.identifier.include?('/inspector') }).to be true
  end
end
