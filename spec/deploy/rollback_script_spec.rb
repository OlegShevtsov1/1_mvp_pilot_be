require 'rails_helper'

RSpec.describe 'deploy/rollback.sh' do
  let(:service) { "#{project_env.fetch('PROJECT_NAME')}-dev" }
  let(:current) { "sha-#{'c' * 40}" }
  let(:previous) { "sha-#{'b' * 40}" }
  let(:oldest) { "sha-#{'a' * 40}" }

  def kamal_calls(root)
    sandbox_log(root, 'bundle.log').lines(chomp: true)
  end

  it 'rolls back to an explicit version and waits until /health reports it' do
    run_script('rollback.sh', 'dev', previous, release: 'b' * 40) do |output, status, root|
      expect(status).to be_success
      expect(kamal_calls(root).last).to eq("exec kamal rollback #{previous} -c config/deploy.dev.yml")
      expect(output).to include(%(Healthy: {"status":"ok","release":"#{'b' * 40}"}))
    end
  end

  it 'fails when /health never reports the rolled-back release' do
    run_script('rollback.sh', 'dev', previous, release: 'c' * 40) do |output, status|
      expect(status.exitstatus).to eq(1)
      expect(output).to include("did not report release #{'b' * 40}")
    end
  end

  it 'picks the newest version before the current one, ignoring replaced-container suffixes' do
    containers = <<~TXT
      #{service}-web-#{current}
      #{service}-web-#{current}_replaced_1a2b3c4d
      #{service}-cron-#{previous}_replaced_9a8b7c6d
      #{service}-web-#{previous}_replaced_5e6f7a8b
      #{service}-web-#{oldest}
    TXT
    run_script('rollback.sh', 'dev', release: 'b' * 40, containers: containers, current_version: "#{current}\n") do |_output, status, root|
      expect(status).to be_success
      expect(kamal_calls(root).last).to eq("exec kamal rollback #{previous} -c config/deploy.dev.yml")
    end
  end

  it 'rolls back only the web role to a version from before the cron role' do
    containers = <<~TXT
      #{service}-cron-#{current}
      #{service}-web-#{current}
      #{service}-web-#{previous}_replaced_5e6f7a8b
    TXT
    run_script('rollback.sh', 'dev', release: 'b' * 40, containers: containers, current_version: "#{current}\n") do |output, status, root|
      expect(status).to be_success, output
      expect(kamal_calls(root).last).to eq("exec kamal rollback #{previous} --roles web -c config/deploy.dev.yml")
    end
  end

  it 'rolls back every role to a version that has a cron container' do
    containers = <<~TXT
      #{service}-cron-#{current}
      #{service}-web-#{current}
      #{service}-cron-#{previous}_replaced_9a8b7c6d
      #{service}-web-#{previous}_replaced_5e6f7a8b
    TXT
    run_script('rollback.sh', 'dev', previous, release: 'b' * 40, containers: containers) do |output, status, root|
      expect(status).to be_success, output
      expect(kamal_calls(root).last).to eq("exec kamal rollback #{previous} -c config/deploy.dev.yml")
    end
  end

  it 'refuses when there is no earlier version on the host' do
    run_script('rollback.sh', 'dev', containers: "#{service}-web-#{current}\n", current_version: current) do |output, status, root|
      expect(status.exitstatus).to eq(1)
      expect(output).to include('could not determine a previous version')
      expect(kamal_calls(root)).not_to include(/rollback/)
    end
  end

  it 'refuses to pick a version when it cannot tell which one is running' do
    containers = "#{service}-web-#{current}\n#{service}-web-#{previous}_replaced_5e6f7a8b\n"
    [ { 'version.fail' => '' }, { 'version.txt' => '' } ].each do |files|
      run_script('rollback.sh', 'dev', containers: containers, files: files) do |output, status, root|
        expect(status.exitstatus).to eq(1)
        expect(output).to include('could not determine the running version')
        expect(kamal_calls(root)).not_to include(/rollback/)
      end
    end
  end

  it 'refuses an unknown destination' do
    run_script('rollback.sh', 'staging') do |_output, status|
      expect(status.exitstatus).to eq(2)
    end
  end

  context 'with the prod destination' do
    let(:name) { project_env.fetch('PROJECT_NAME') }
    let(:repo) { "registry.example.test/#{name}" }
    let(:prod_env) { { 'PROD_VPN_IP' => '192.0.2.70', 'KAMAL_REGISTRY_SERVER' => 'registry.example.test', 'CONFIRM' => 'ROLLBACK-prod' } }
    let(:digests) { "prod-#{previous} sha256:pb\nprod-#{current} sha256:pc\nprod-current sha256:pc\n" }

    def crane_calls(root)
      sandbox_log(root, 'crane.log').lines(chomp: true)
    end

    it 'refuses without the typed confirm ROLLBACK-prod, before any Kamal or crane call' do
      [ nil, 'prod', 'rollback-prod' ].each do |confirm|
        run_script('rollback.sh', 'prod', previous, env: prod_env.merge('CONFIRM' => confirm), release: 'b' * 40,
                                                    files: { 'digests' => digests }) do |output, status, root|
          expect(status.exitstatus).to eq(1), confirm.inspect
          expect(output).to include('ROLLBACK-prod')
          expect(kamal_calls(root)).to be_empty
          expect(crane_calls(root)).to be_empty
        end
      end
    end

    it 'rolls back to the prod image of an explicit version and swaps the ECR tags' do
      run_script('rollback.sh', 'prod', previous, env: prod_env, release: 'b' * 40, files: { 'digests' => digests }) do |output, status, root|
        expect(status).to be_success, output
        expect(kamal_calls(root).last).to eq("exec kamal rollback prod-#{previous} -c config/deploy.yml")
        expect(crane_calls(root).grep(/\Atag /)).to eq([
          "tag #{repo}@sha256:pc prod-previous",
          "tag #{repo}@sha256:pb prod-current"
        ])
      end
    end

    it 'picks the newest prod version before the current one' do
      containers = <<~TXT
        #{name}-web-prod-#{current}
        #{name}-web-prod-#{current}_replaced_1a2b3c4d
        #{name}-cron-prod-#{previous}_replaced_9a8b7c6d
        #{name}-web-prod-#{previous}_replaced_5e6f7a8b
      TXT
      run_script('rollback.sh', 'prod', env: prod_env, release: 'b' * 40, containers: containers,
                                        current_version: "prod-#{current}\n", files: { 'digests' => digests }) do |_output, status, root|
        expect(status).to be_success
        expect(kamal_calls(root).last).to eq("exec kamal rollback prod-#{previous} -c config/deploy.yml")
      end
    end

    it 'moves no tag when it cannot tell which prod version is running' do
      containers = "#{name}-web-prod-#{current}\n#{name}-web-prod-#{previous}_replaced_5e6f7a8b\n"
      run_script('rollback.sh', 'prod', env: prod_env, containers: containers,
                                        files: { 'digests' => digests, 'version.fail' => '' }) do |output, status, root|
        expect(status.exitstatus).to eq(1)
        expect(output).to include('could not determine the running version')
        expect(kamal_calls(root)).not_to include(/rollback/)
        expect(crane_calls(root).grep(/\Atag /)).to be_empty
      end
    end

    it 'moves no tag when the rolled-back release never becomes healthy' do
      run_script('rollback.sh', 'prod', previous, env: prod_env, release: 'c' * 40, files: { 'digests' => digests }) do |_output, status, root|
        expect(status.exitstatus).to eq(1)
        expect(crane_calls(root).grep(/\Atag /)).to be_empty
      end
    end

    it 'checks health inside the container and swaps only prod-aws-* while the srv host is the live prod' do
      files = { 'digests' => "#{digests}prod-aws-current sha256:pc\n", 'exec.txt' => %({"status":"ok","release":"#{previous.delete_prefix('sha-')}"}) }
      run_script('rollback.sh', 'prod', previous, env: prod_env.merge('PROD_ACTIVE_TARGET' => 'srv'), release: 'c' * 40,
                                                  files: files) do |output, status, root|
        expect(status).to be_success, output
        expect(kamal_calls(root)).to include(/\Aexec kamal app exec --reuse --roles=web -q curl .*localhost:3000\/health -c config\/deploy\.yml\z/)
        expect(sandbox_log(root, 'curl.log')).to be_empty
        expect(crane_calls(root).grep(/\Atag /)).to eq([
          "tag #{repo}@sha256:pc prod-aws-previous",
          "tag #{repo}@sha256:pb prod-aws-current"
        ])
      end
    end
  end

  context 'with the prod-srv destination' do
    let(:name) { project_env.fetch('PROJECT_NAME') }
    let(:repo) { "registry.example.test/#{name}" }
    let(:srv_env) { { 'PROD_SRV_VPN_IP' => '192.0.2.80', 'KAMAL_REGISTRY_SERVER' => 'registry.example.test', 'CONFIRM' => 'ROLLBACK-prod' } }
    let(:digests) { "prod-#{previous} sha256:pb\nprod-#{current} sha256:pc\nprod-srv-current sha256:pc\nprod-current sha256:aws\n" }

    def crane_calls(root)
      sandbox_log(root, 'crane.log').lines(chomp: true)
    end

    it 'refuses without the typed confirm ROLLBACK-prod, before any Kamal or crane call' do
      run_script('rollback.sh', 'prod-srv', previous, env: srv_env.merge('CONFIRM' => 'prod'), files: { 'digests' => digests }) do |output, status, root|
        expect(status.exitstatus).to eq(1)
        expect(output).to include('ROLLBACK-prod')
        expect(kamal_calls(root)).to be_empty
        expect(crane_calls(root)).to be_empty
      end
    end

    it 'also swaps prod-current and prod-previous while the srv host is the live prod' do
      digests = "prod-#{previous} sha256:pb\nprod-#{current} sha256:pc\nprod-srv-current sha256:pc\nprod-current sha256:pc\n"
      run_script('rollback.sh', 'prod-srv', previous, env: srv_env.merge('PROD_ACTIVE_TARGET' => 'srv'), release: 'b' * 40,
                                                      files: { 'digests' => digests }) do |output, status, root|
        expect(status).to be_success, output
        expect(crane_calls(root).grep(/\Atag /)).to eq([
          "tag #{repo}@sha256:pc prod-srv-previous",
          "tag #{repo}@sha256:pb prod-srv-current",
          "tag #{repo}@sha256:pc prod-previous",
          "tag #{repo}@sha256:pb prod-current"
        ])
      end
    end

    it 'rolls back with the srv config and swaps only the prod-srv tags' do
      run_script('rollback.sh', 'prod-srv', previous, env: srv_env, release: 'b' * 40, files: { 'digests' => digests }) do |output, status, root|
        expect(status).to be_success, output
        expect(kamal_calls(root).last).to eq("exec kamal rollback prod-#{previous} -c config/deploy.prod-srv.yml")
        expect(crane_calls(root).grep(/\Atag /)).to eq([
          "tag #{repo}@sha256:pc prod-srv-previous",
          "tag #{repo}@sha256:pb prod-srv-current"
        ])
      end
    end
  end
end
