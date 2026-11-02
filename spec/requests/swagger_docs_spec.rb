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

  it 'documents the auth operations with the answers of the todolist contract' do
    contract = YAML.safe_load_file(Rails.root.join('docs/features/todolist/contracts/openapi.yaml'))['paths']
    get '/api-docs/v1/swagger.json'
    document = JSON.parse(response.body)

    operations = [ %w[/oauth/token post], %w[/oauth/revoke post], %w[/api/v1/users post], %w[/api/v1/sign_in post],
                   %w[/api/v1/sign_out post], %w[/api/v1/me get] ]
    statuses = ->(paths) { operations.to_h { |path, verb| [ "#{verb} #{path}", paths.dig(path, verb, 'responses')&.keys&.sort ] } }

    expect(statuses.call(document['paths'])).to eq(statuses.call(contract))
    expect(document.dig('components', 'securitySchemes').values).to include({ 'type' => 'http', 'scheme' => 'bearer' })
    expect(document.dig('paths', '/api/v1/sign_in', 'post', 'deprecated')).to be(true)
  end

  it 'carries placeholder tokens, never live ones, in its examples' do
    get '/api-docs/v1/swagger.json'

    expect(token_values(JSON.parse(response.body))).to all(match(/\A<[a-z-]+>\z/))
  end

  def token_values(node)
    case node
    when Hash
      node.flat_map do |key, value|
        if %w[authentication_token access_token refresh_token].include?(key) && value.is_a?(String)
          [ value ]
        else
          token_values(value)
        end
      end
    when Array then node.flat_map { |value| token_values(value) }
    else []
    end
  end
end
