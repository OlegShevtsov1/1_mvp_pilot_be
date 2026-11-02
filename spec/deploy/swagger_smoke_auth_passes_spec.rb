require 'rails_helper'

# The dev deploy's smoke must prove that a bearer access token opens me, projects and tasks (QG-2), and its legacy
# pass must never count as a legacy use (AC-12): the server skips the count only for requests that carry
# X-Smoke-Token, so every legacy request of the smoke has to carry it.
RSpec.describe 'bin/swagger_smoke bearer pass and marked legacy pass' do
  let(:curl_shim) do
    <<~'SH'
      #!/usr/bin/env bash
      echo "$*" >> "$SANDBOX/curl.log"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          -o) out="$2"; shift ;;
          --data) data="$2"; shift ;;
        esac
        shift
      done
      who=b; [[ "${data:-}" == *smoke-a-* ]] && who=a
      echo "{\"status\":\"ok\",\"access_token\":\"oauth-access\",\"refresh_token\":\"oauth-refresh\",\"data\":{\"id\":7,\"authentication_token\":\"legacy-$who\",\"access_token\":\"access-$who\"}}" > "$out"
      printf 200
    SH
  end

  def smoke(env = {})
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, 'shim'))
      File.write(File.join(root, 'shim', 'curl'), curl_shim)
      FileUtils.chmod(0o755, File.join(root, 'shim', 'curl'))
      full_env = { 'PATH' => "#{File.join(root, 'shim')}:#{ENV.fetch('PATH')}", 'SANDBOX' => root,
                   'SMOKE_READ_ONLY' => nil, 'SMOKE_CONNECT_TO' => nil, 'SMOKE_FORWARDED_PROTO' => nil,
                   'SMOKE_TOKEN' => 'smoke-test-token', 'OAUTH_CLIENT_ID' => 'web-client',
                   'LEGACY_AUTH_ENABLED' => nil }.merge(env)
      output, = Open3.capture2e(full_env, Rails.root.join('bin/swagger_smoke').to_s, 'https://example.test')
      [ output, File.read(File.join(root, 'curl.log')).lines(chomp: true) ]
    end
  end

  def requests(calls, header)
    calls.select { |call| call.include?(header) }
         .map { |call| call.match(%r{-X (\w+) https://example\.test(\S+)}).captures.join(' ') }
  end

  it 'runs me, project and task create, read, update and delete, and sign-out with the sign-up bearer token' do
    _, calls = smoke

    expect(requests(calls, 'Authorization: Bearer access-a')).to include(
      'GET /api/v1/me', 'POST /api/v1/projects', 'GET /api/v1/projects/7', 'PUT /api/v1/projects/7',
      'DELETE /api/v1/projects/7', 'POST /api/v1/projects/7/tasks', 'GET /api/v1/projects/7/tasks/7',
      'PUT /api/v1/projects/7/tasks/7', 'DELETE /api/v1/projects/7/tasks/7', 'POST /api/v1/sign_out'
    )
  end

  it "asks for another user's project with that user's bearer token" do
    _, calls = smoke

    expect(requests(calls, 'Authorization: Bearer access-b')).to include('GET /api/v1/projects/7')
  end

  it 'marks every legacy request as a pipeline call' do
    _, calls = smoke
    legacy = calls.select { |call| call.include?('X-User-Token') }

    expect(requests(calls, 'X-User-Token: legacy-a')).to include('GET /api/v1/me', 'POST /api/v1/projects')
    expect(legacy).to all(include('X-Smoke-Token: smoke-test-token'))
    expect(requests(legacy, 'X-User-Token')).not_to include('POST /api/v1/sign_out')
  end

  it 'drops the legacy pass when LEGACY_AUTH_ENABLED is off' do
    output, calls = smoke('LEGACY_AUTH_ENABLED' => 'false')

    expect(calls).to all(satisfy { |call| !call.include?('X-User-Token') })
    expect(output).to include('SKIP  legacy pass')
  end

  it 'skips the legacy pass without SMOKE_TOKEN, so nothing is counted' do
    _, calls = smoke('SMOKE_TOKEN' => nil)

    expect(calls).to all(satisfy { |call| !call.include?('X-User-Token') })
  end

  it 'falls back to the marked legacy headers without a web client' do
    output, calls = smoke('OAUTH_CLIENT_ID' => nil)
    me_calls = calls.select { |call| call.include?('-X GET https://example.test/api/v1/me ') && call.include?('X-User-') }

    expect(calls).to all(satisfy { |call| !call.include?('Authorization: Bearer') })
    expect(me_calls).not_to be_empty
    expect(me_calls).to all(include('X-Smoke-Token: smoke-test-token'))
    expect(output).to include('SKIP  bearer pass')
  end
end
