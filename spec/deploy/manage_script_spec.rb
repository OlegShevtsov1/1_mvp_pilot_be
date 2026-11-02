require 'rails_helper'

RSpec.describe 'deploy/manage.sh' do
  let(:prod_env) { { 'PROD_VPN_IP' => '192.0.2.70', 'KAMAL_REGISTRY_SERVER' => 'registry.example.test' } }

  def kamal_calls(root)
    sandbox_log(root, 'bundle.log').lines(chomp: true)
  end

  {
    'status' => [ 'exec kamal details -c config/deploy.yml', 'exec kamal app version -c config/deploy.yml' ],
    'logs' => [ 'exec kamal app logs --lines 200 -c config/deploy.yml' ],
    'restart' => [ 'exec kamal app boot -c config/deploy.yml' ]
  }.each do |action, calls|
    it "runs #{action} against the prod config only" do
      run_script('manage.sh', action, env: prod_env) do |output, status, root|
        expect(status).to be_success, output
        expect(kamal_calls(root)).to eq(calls)
      end
    end
  end

  it 'refuses to remove without a passed backup gate' do
    run_script('manage.sh', 'remove', env: prod_env) do |output, status, root|
      expect(status.exitstatus).to eq(1)
      expect(output).to include('remove needs BACKUP_GATE=passed')
      expect(kamal_calls(root)).to be_empty
    end
  end

  it 'removes once the backup gate passed' do
    run_script('manage.sh', 'remove', env: prod_env.merge('BACKUP_GATE' => 'passed')) do |_output, status, root|
      expect(status).to be_success
      expect(kamal_calls(root)).to eq([ 'exec kamal remove -y -c config/deploy.yml' ])
    end
  end

  it 'refuses an unknown action' do
    run_script('manage.sh', 'deploy', env: prod_env) do |_output, status, root|
      expect(status.exitstatus).to eq(2)
      expect(kamal_calls(root)).to be_empty
    end
  end

  it 'refuses to run without PROD_VPN_IP' do
    run_script('manage.sh', 'status') do |output, status, root|
      expect(status.exitstatus).to eq(2)
      expect(output).to include('PROD_VPN_IP is not set')
      expect(kamal_calls(root)).to be_empty
    end
  end

  context 'with the prod-srv destination' do
    let(:srv_env) { { 'PROD_SRV_VPN_IP' => '192.0.2.80', 'KAMAL_REGISTRY_SERVER' => 'registry.example.test' } }

    {
      'status' => [ 'exec kamal details -c config/deploy.prod-srv.yml', 'exec kamal app version -c config/deploy.prod-srv.yml' ],
      'logs' => [ 'exec kamal app logs --lines 200 -c config/deploy.prod-srv.yml' ]
    }.each do |action, calls|
      it "runs #{action} against the srv config only" do
        run_script('manage.sh', action, 'prod-srv', env: srv_env) do |output, status, root|
          expect(status).to be_success, output
          expect(kamal_calls(root)).to eq(calls)
        end
      end
    end

    it 'restarts the running version by name: the latest tag on the srv host is moved by dev deploys' do
      run_script('manage.sh', 'restart', 'prod-srv', env: srv_env, current_version: "prod-sha-#{'b' * 40}\n") do |output, status, root|
        expect(status).to be_success, output
        expect(kamal_calls(root)).to eq([ 'exec kamal app version -q -c config/deploy.prod-srv.yml',
                                          "exec kamal app boot --version prod-sha-#{'b' * 40} -c config/deploy.prod-srv.yml" ])
      end
    end

    [ { 'version.fail' => '' }, { 'version.txt' => '' } ].each do |files|
      it "refuses to restart without a running version (#{files.keys.first})" do
        run_script('manage.sh', 'restart', 'prod-srv', env: srv_env, files: files) do |output, status, root|
          expect(status.exitstatus).to eq(1)
          expect(output).to include('could not determine the running version', 'nothing was restarted')
          expect(kamal_calls(root)).not_to include(a_string_including('app boot'))
        end
      end
    end

    it 'refuses remove even after a passed backup gate: it would also remove the shared kamal-proxy' do
      run_script('manage.sh', 'remove', 'prod-srv', env: srv_env.merge('BACKUP_GATE' => 'passed')) do |output, status, root|
        expect(status.exitstatus).to eq(1)
        expect(output).to include('remove is refused on prod-srv', 'nothing was removed')
        expect(kamal_calls(root)).to be_empty
      end
    end

    it 'refuses to run without PROD_SRV_VPN_IP' do
      run_script('manage.sh', 'status', 'prod-srv', env: srv_env.merge('PROD_SRV_VPN_IP' => nil)) do |output, status, root|
        expect(status.exitstatus).to eq(2)
        expect(output).to include('PROD_SRV_VPN_IP is not set')
        expect(kamal_calls(root)).to be_empty
      end
    end
  end

  it 'never manages dev' do
    run_script('manage.sh', 'status', 'dev', env: prod_env) do |output, status, root|
      expect(status.exitstatus).to eq(2)
      expect(output).to include("unknown destination 'dev' (supported: prod, prod-srv)")
      expect(kamal_calls(root)).to be_empty
    end
  end
end
