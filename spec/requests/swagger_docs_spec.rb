require 'rails_helper'

RSpec.describe 'GET /api-docs/v1/swagger.json' do
  def served_servers
    JSON.parse(response.body)['servers']
  end

  it 'lists the proxied request origin as the only server' do
    host! 'pilot.example.com'
    with_env('SENTRY_ENVIRONMENT' => 'prod') do
      get '/api-docs/v1/swagger.json', headers: { 'X-Forwarded-Proto' => 'https' }
    end

    expect(response).to have_http_status(:ok)
    expect(served_servers).to eq([ { 'url' => 'https://pilot.example.com', 'description' => 'PILOT prod' } ])
  end

  it 'follows X-Forwarded-Host when the proxy reaches the app under an internal name' do
    host! 'app:3000'
    with_env('SENTRY_ENVIRONMENT' => 'dev') do
      get '/api-docs/v1/swagger.json',
          headers: { 'X-Forwarded-Host' => 'pilot.example.com', 'X-Forwarded-Proto' => 'https' }
    end

    expect(served_servers).to eq([ { 'url' => 'https://pilot.example.com', 'description' => 'PILOT dev' } ])
  end

  it 'lists localhost:3000 for a local development request' do
    host! 'localhost:3000'
    with_env('SENTRY_ENVIRONMENT' => nil) do
      get '/api-docs/v1/swagger.json'
    end

    expect(served_servers).to eq([ { 'url' => 'http://localhost:3000', 'description' => 'PILOT test' } ])
  end

  it 'still serves the documented paths' do
    get '/api-docs/v1/swagger.json'

    expect(JSON.parse(response.body)['paths']).to include('/api/v1/projects')
  end
end
