require 'rails_helper'

# The values that must fail are built at runtime: the real-repository example scans this file too,
# and a literal here would be exactly the leak the check exists to stop.
RSpec.describe 'scripts/check-public-repo.sh' do
  context 'in a fixture repository' do
    around { |example| in_git_repo { example.run } }

    def check_public_repo
      run_in_repo3('scripts/check-public-repo.sh')
    end

    def version_line
      "    rails (#{%w[7 2 3 2].join('.')})\n"
    end

    def public_ipv4
      %w[198 18 0 9].join('.')
    end

    def bot_api_host
      "https://#{%w[api telegram org].join('.')}/bot"
    end

    def chat_id
      '-100' + '1234567890'
    end

    it 'passes a clean tree and says so' do
      commit('Clean', 'README.md' => "Plain text, nothing internal.\n")

      stdout, stderr, status = check_public_repo
      expect(status).to be_success, stderr
      expect(stdout).to include('public-repo check: clean')
    end

    it 'ignores untracked files' do
      commit('Clean', 'README.md' => "Plain text, nothing internal.\n")
      File.write(File.join(@repo, 'scratch.txt'), "host: #{%w[192 168 1 20].join('.')}\n")

      stdout, stderr, status = check_public_repo
      expect(status).to be_success, stdout + stderr
      expect(stdout).to include('public-repo check: clean')
    end

    it 'fails on each rule of the shared rule set and prints only file:line, never the match' do
      rules = [
        [ 'private LAN IP (192-168 range)', %w[192 168 1 20].join('.') ],
        [ 'internal VPN IP (10-18 range)', %w[10 18 0 5].join('.') ],
        [ 'IPv4 literal (EIP or internal)', public_ipv4 ],
        [ 'internal hostname (vr8 prefix)', 'vr8' + '-db' ],
        [ 'internal hostname srvN.local', 'srv1' + '.local' ],
        [ 'internal hostname (bonfir[e])', 'bonfi' + 're' ],
        [ 'AWS account ID (12 digits)', '1234' * 3 ],
        [ 'Route53 hosted zone ID', 'Z' + 'ABCDEFGHIJ0123' ],
        [ 'Trello link', "https://#{%w[trello com].join('.')}/c/x" ],
        [ 'Notion link or page ID', "https://#{%w[notion so].join('.')}/x" ],
        [ 'Notion link or page ID', 'ab12' * 8 ],
        [ 'Telegram link or chat ID', "https://#{%w[t me].join('.')}/x" ],
        [ 'Telegram link or chat ID', chat_id ],
        [ 'Telegram Bot API host', bot_api_host ],
        [ 'local home path', '/' + %w[home dev].join('/') + '/x' ]
      ]
      rules.each.with_index { |(_, value), n| commit("Hit #{n}", "notes/#{n}.txt" => "line one\nhost: #{value}\n") }

      stdout, stderr, status = check_public_repo
      expect(status.exitstatus).to eq(1), stdout + stderr
      rules.each.with_index do |(label, value), n|
        expect(stdout).to include("notes/#{n}.txt:2")
        expect(stdout).to include("::error::public-repo check failed: #{label}")
        expect(stdout + stderr).not_to include(value)
      end
    end

    it 'allows loopback, bind-all and RFC 5737 documentation addresses' do
      commit('Sandbox', 'spec/support/sandbox.rb' =>
        "{ 'DEV_HOST' => '192.0.2.10', 'BIND' => '0.0.0.0', db: '127.0.0.1', a: '198.51.100.7', b: '203.0.113.77' }\n")

      stdout, stderr, status = check_public_repo
      expect(status).to be_success, stdout + stderr
    end

    it 'still fails a line that mixes an allowed and a real address' do
      commit('Mixed', 'config/hosts.txt' => "127.0.0.1 #{public_ipv4}\n")

      stdout, stderr, status = check_public_repo
      expect(status.exitstatus).to eq(1), stdout + stderr
      expect(stdout).to include('::error::public-repo check failed: IPv4 literal (EIP or internal)')
      expect(stdout).to include('config/hosts.txt:1')
    end

    it 'allows four-part version numbers only in Gemfile, Gemfile.lock and config/brakeman.ignore' do
      commit('Versions', 'Gemfile' => version_line, 'Gemfile.lock' => version_line,
                         'config/brakeman.ignore' => version_line)

      stdout, stderr, status = check_public_repo
      expect(status).to be_success, stdout + stderr

      commit('Elsewhere', 'config/versions.yml' => version_line)

      stdout, stderr, status = check_public_repo
      expect(status.exitstatus).to eq(1), stdout + stderr
      expect(stdout).to include('config/versions.yml:1')
    end

    it 'allows the Telegram Bot API host only in workflows and the notifier spec, never a chat ID or link' do
      commit('Notifier', '.github/workflows/alert.yml' => "url: #{bot_api_host}\n",
                         'spec/deploy/infra_helpers_checkout_spec.rb' => "url = '#{bot_api_host}'\n")

      stdout, stderr, status = check_public_repo
      expect(status).to be_success, stdout + stderr

      commit('App notifier', 'app/notify.rb' => "URL = '#{bot_api_host}'\n")

      stdout, stderr, status = check_public_repo
      expect(status.exitstatus).to eq(1), stdout + stderr
      expect(stdout).to include('::error::public-repo check failed: Telegram Bot API host')
      expect(stdout).to include('app/notify.rb:1')

      commit('Chat ID', 'app/notify.rb' => "# nothing\n", '.github/workflows/alert.yml' => "chat: #{chat_id}\n")

      stdout, stderr, status = check_public_repo
      expect(status.exitstatus).to eq(1), stdout + stderr
      expect(stdout).to include('::error::public-repo check failed: Telegram link or chat ID')
      expect(stdout).to include('.github/workflows/alert.yml:1')
    end
  end

  context 'in this repository' do
    it 'passes on this repository' do
      output, status = Open3.capture2e('bash', 'scripts/check-public-repo.sh', chdir: Rails.root.to_s)
      expect(status).to be_success, output
      expect(output).to include('public-repo check: clean')
    end

    it 'runs as a blocking step of Rails CI' do
      workflow = YAML.load_file(Rails.root.join('.github/workflows/rails-lint.yml'))
      step = workflow.dig('jobs', 'lint', 'steps').find { |s| s['run'] == 'bash scripts/check-public-repo.sh' }
      expect(step).not_to be_nil
      expect(step).not_to have_key('continue-on-error')
    end
  end
end
