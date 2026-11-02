require 'rails_helper'

# Every failed password grant counts as a failed sign-in for the deploy's source (AC-10), so the smoke provokes the
# documented /oauth/token 400 with a refresh token no one was issued instead of a wrong password (PILOT-331). The
# legacy sign-in counts every 401 the same way, so the smoke sends no wrong password to /api/v1/sign_in either
# (PILOT-333).
RSpec.describe 'bin/swagger_smoke failed sign-ins' do
  let(:curl_shim) do
    <<~'SH'
      #!/usr/bin/env bash
      while [[ $# -gt 0 ]]; do
        case "$1" in
          -o) out="$2"; shift ;;
          --data) echo "$2" >> "$SANDBOX/data.log"; shift ;;
        esac
        shift
      done
      echo '{"status":"ok","access_token":"oauth-access","refresh_token":"oauth-refresh","data":{"id":7,"authentication_token":"legacy","access_token":"access"}}' > "$out"
      printf 200
    SH
  end

  def request_bodies
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, 'shim'))
      File.write(File.join(root, 'shim', 'curl'), curl_shim)
      FileUtils.chmod(0o755, File.join(root, 'shim', 'curl'))
      env = { 'PATH' => "#{File.join(root, 'shim')}:#{ENV.fetch('PATH')}", 'SANDBOX' => root,
              'SMOKE_READ_ONLY' => nil, 'SMOKE_CONNECT_TO' => nil, 'SMOKE_FORWARDED_PROTO' => nil,
              'SMOKE_TOKEN' => 'smoke-test-token', 'OAUTH_CLIENT_ID' => 'web-client', 'LEGACY_AUTH_ENABLED' => nil }
      Open3.capture2e(env, Rails.root.join('bin/swagger_smoke').to_s, 'https://example.test')
      File.read(File.join(root, 'data.log')).lines.filter_map do |line|
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end
    end
  end

  def token_requests
    request_bodies.select { |body| body.key?('grant_type') }
  end

  it 'never sends a wrong password to either sign-in door' do
    password_bodies = request_bodies.select { |body| body.key?('password') }

    expect(password_bodies).to include(include('email' => a_string_starting_with('smoke-a-')))
    expect(password_bodies).to all(include('password' => 'password123'))
  end

  it 'never sends a password grant with a wrong password for the web client' do
    password_grants = token_requests.select { |body| body['grant_type'] == 'password' && body['client_id'] == 'web-client' }

    expect(password_grants).to all(include('password' => 'password123'))
  end

  it 'asks for a token with a refresh token it was never issued' do
    refresh_grants = token_requests.select { |body| body['grant_type'] == 'refresh_token' }

    expect(refresh_grants.size).to eq(1)
    expect(refresh_grants.first).to include('client_id' => 'web-client')
    expect(refresh_grants.first['refresh_token']).to be_present
    expect(refresh_grants.first['refresh_token']).not_to eq('oauth-refresh')
  end
end
