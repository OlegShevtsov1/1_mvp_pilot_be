require 'rails_helper'

# Every dev deploy's smoke signs up three times from the same address; more than one deploy an hour would trip
# the sign-up limit unless the smoke presents SMOKE_TOKEN, which exempts it.
RSpec.describe 'bin/swagger_smoke sign-ups and the sign-up limit' do
  let(:curl_shim) do
    <<~'SH'
      #!/usr/bin/env bash
      echo "$*" >> "$SANDBOX/curl.log"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          -o) out="$2"; shift ;;
          -X) method="$2"; shift ;;
          http*) url="$1" ;;
        esac
        shift
      done
      echo '{"data":{"authentication_token":"t"}}' > "$out"
      case "${method} ${url#https://example.test}" in
        'POST /api/v1/users') printf 201 ;;
        *) printf 500 ;;
      esac
    SH
  end

  def sign_up_calls(env)
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, 'shim'))
      File.write(File.join(root, 'shim', 'curl'), curl_shim)
      FileUtils.chmod(0o755, File.join(root, 'shim', 'curl'))
      full_env = { 'PATH' => "#{File.join(root, 'shim')}:#{ENV.fetch('PATH')}", 'SANDBOX' => root,
                   'SMOKE_READ_ONLY' => nil, 'SMOKE_CONNECT_TO' => nil, 'SMOKE_FORWARDED_PROTO' => nil }.merge(env)
      Open3.capture2e(full_env, Rails.root.join('bin/swagger_smoke').to_s, 'https://example.test')
      File.read(File.join(root, 'curl.log')).lines(chomp: true)
          .select { |call| call.include?('-X POST https://example.test/api/v1/users') }
    end
  end

  it 'presents SMOKE_TOKEN on every sign-up when it is set' do
    calls = sign_up_calls('SMOKE_TOKEN' => 'smoke-test-token')

    expect(calls.size).to eq(3)
    expect(calls).to all(include('X-Smoke-Token: smoke-test-token'))
  end

  it 'sends no smoke header without SMOKE_TOKEN' do
    calls = sign_up_calls('SMOKE_TOKEN' => nil)

    expect(calls.size).to eq(3)
    expect(calls).to all(satisfy { |call| !call.include?('X-Smoke-Token') })
  end
end
