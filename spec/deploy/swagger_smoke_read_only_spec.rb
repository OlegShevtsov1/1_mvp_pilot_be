require 'rails_helper'

# Prod runs bin/swagger_smoke with SMOKE_READ_ONLY=1 after every deploy: it must not create
# anything there, because the API cannot delete the users the full smoke signs up.
RSpec.describe 'bin/swagger_smoke with SMOKE_READ_ONLY=1' do
  CURL_SHIM = <<~'SH'.freeze
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
    echo '{"status":"ok"}' > "$out"
    case "${method} ${url#https://example.test}" in
      'GET /health'|'GET /api-docs/'*) printf 200 ;;
      'GET /api/v1/me'|'GET /api/v1/projects') printf 401 ;;
      *) printf 500 ;;
    esac
  SH

  def run_smoke(env)
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, 'shim'))
      File.write(File.join(root, 'shim', 'curl'), CURL_SHIM)
      FileUtils.chmod(0o755, File.join(root, 'shim', 'curl'))
      full_env = { 'PATH' => "#{File.join(root, 'shim')}:#{ENV.fetch('PATH')}", 'SANDBOX' => root,
                   'SMOKE_CONNECT_TO' => nil, 'SMOKE_FORWARDED_PROTO' => nil }.merge(env)
      output, status = Open3.capture2e(full_env, Rails.root.join('bin/swagger_smoke').to_s, 'https://example.test')
      yield(output, status, File.read(File.join(root, 'curl.log')).lines(chomp: true))
    end
  end

  it 'passes on a healthy deployment using GET requests only' do
    run_smoke('SMOKE_READ_ONLY' => '1') do |output, status, calls|
      expect(status).to be_success, output
      expect(output.strip).to end_with('all passed')
      expect(calls.size).to eq(5)
      expect(calls).to all(include('-X GET'))
    end
  end

  it 'still runs the writing checks without it' do
    run_smoke('SMOKE_READ_ONLY' => nil) do |_output, status, calls|
      expect(status).not_to be_success
      expect(calls).to include(a_string_including('-X POST https://example.test/api/v1/users'))
    end
  end
end
