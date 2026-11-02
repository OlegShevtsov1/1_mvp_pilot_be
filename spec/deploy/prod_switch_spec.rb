require 'rails_helper'

RSpec.describe 'deploy/prod_switch.sh' do
  let(:name) { project_env.fetch('PROJECT_NAME') }
  let(:zone) { project_env.fetch('PROJECT_ZONE') }
  let(:version) { "sha-#{DeploySandbox::SHA}" }
  let(:release) { "prod-#{version}" }
  let(:repo) { "registry.example.test/#{name}" }
  let(:stop_app) { "docker ps -q --filter label=service=#{name} | xargs -r docker stop" }
  let(:aws) { '192.0.2.70' }
  let(:srv) { '192.0.2.80' }
  let(:hosts_env) do
    { 'PROD_VPN_IP' => aws, 'PROD_SRV_VPN_IP' => srv, 'KAMAL_REGISTRY_SERVER' => 'registry.example.test', 'PROD_ACTIVE_TARGET' => 'aws' }
  end

  def switch(*args, env: {}, **options, &block)
    run_script('prod_switch.sh', *args, env: hosts_env.merge(env), **options, &block)
  end

  def log_lines(root, name)
    sandbox_log(root, name).lines(chomp: true)
  end

  def kamal_calls(root)
    log_lines(root, 'bundle.log')
  end

  def ssh_commands(root)
    log_lines(root, 'ssh.log').map { |line| line.sub(/\A-o BatchMode=yes -o StrictHostKeyChecking=accept-new /, '') }
  end

  # The dispatch inputs of Project Terraform Prod as `gh workflow view --yaml` prints them.
  def infra_workflow(options, inline: false)
    list = inline ? "        options: [#{options.join(', ')}]\n" : "        options:\n#{options.map { |o| "          - #{o}\n" }.join}"
    "name: Project Terraform Prod\non:\n  workflow_dispatch:\n    inputs:\n      project:\n        type: string\n" \
      "      action:\n        type: choice\n        options:\n          - plan\n          - apply\n" \
      "      prod_target:\n        description: 'aws or srv'\n        default: 'aws'\n        type: choice\n#{list}" \
      "      other:\n        type: choice\n        options:\n          - unrelated\njobs:\n  terraform:\n    runs-on: ubuntu-latest\n"
  end

  def host_logs(root)
    %w[bundle.log ssh.log nc.log crane.log gh.log curl.log smoke.log].to_h { |log| [ log, sandbox_log(root, log) ] }
  end

  describe 'guard' do
    def guard(to, active)
      switch('guard', env: { 'TO' => to, 'ACTIVE_TARGET' => active }) { |output, status| return [ output, status ] }
    end

    it 'names both sides and their destinations for each direction' do
      output, status = guard('srv', 'aws')
      expect(status).to be_success, output
      expect(output).to eq("to=srv\nfrom=aws\nto_destination=prod-srv\nfrom_destination=prod\n")
      output, = guard('aws', 'srv')
      expect(output).to eq("to=aws\nfrom=srv\nto_destination=prod\nfrom_destination=prod-srv\n")
    end

    it 'refuses a switch to the host that is already live' do
      %w[aws srv].each do |target|
        output, status = guard(target, target)
        expect(status.exitstatus).to eq(1)
        expect(output).to include("::error::prod already runs on #{target}")
        expect(output).not_to include('to=')
      end
    end

    it 'refuses an unknown target or live host' do
      [ [ 'gcp', 'aws' ], [ '', 'aws' ], [ 'srv', '' ], [ 'srv', 'mid-change' ] ].each do |to, active|
        output, status = guard(to, active)
        expect(status.exitstatus).to eq(1), [ to, active ].inspect
        expect(output).not_to include('to=')
      end
    end
  end

  describe 'deploy/prod_active_target.sh' do
    def active(hosts)
      run_script('prod_active_target.sh', files: { 'hosts.txt' => hosts }) { |output, status| return [ output, status ] }
    end

    it 'reads aws or srv from where the zone points, compared with the srv TLS terminator' do
      expect(active(public_dns('aws'))).to match([ "active_target=aws\n", be_success ])
      expect(active(public_dns('srv'))).to match([ "active_target=srv\n", be_success ])
    end

    it 'refuses while DNS is unresolvable or mid-change' do
      {
        'unresolvable' => "dev.#{zone} 192.0.2.20\n",
        'zone and app.zone disagree' => "#{zone} 192.0.2.20\napp.#{zone} 192.0.2.10\ndev.#{zone} 192.0.2.20\n",
        'partly on the terminator' => "#{zone} 192.0.2.10\n#{zone} 192.0.2.20\napp.#{zone} 192.0.2.10\napp.#{zone} 192.0.2.20\ndev.#{zone} 192.0.2.20\n"
      }.each do |label, hosts|
        output, status = active(hosts)
        expect(status.exitstatus).to eq(1), label
        expect(output).to include('::error::the live prod host is unknown'), label
        expect(output).not_to include('active_target='), label
      end
    end
  end

  describe 'plan (the step selection of prepare)' do
    let(:ready) do
      { 'TO' => 'srv', 'RELEASE' => release, 'REACHABLE' => 'yes', 'FE_RUNNING' => 'yes', 'SOURCE_VERSION' => release,
        'TARGET_CONTAINERS' => 'yes', 'TARGET_VERSION' => release }
    end

    def plan(observations)
      switch('plan', env: ready.merge(observations)) { |output, status| return [ output, status ] }
    end

    it 'only resumes a target that already runs the release (the old side of an earlier switch)' do
      expect(plan({})).to match([ "steps=live\n", be_success ])
    end

    it 'resumes, then deploys a target that runs another version or none' do
      expect(plan('TARGET_VERSION' => "prod-sha-#{'b' * 40}")).to match([ "steps=live deploy\n", be_success ])
      expect(plan('TARGET_VERSION' => '')).to match([ "steps=live deploy\n", be_success ])
    end

    it 'only deploys a target without containers of the service' do
      expect(plan('TARGET_CONTAINERS' => 'no', 'TARGET_VERSION' => '')).to match([ "steps=deploy\n", be_success ])
    end

    it 'selects standby for an unreachable AWS instance and refuses it after the standby' do
      expect(plan('TO' => 'aws', 'REACHABLE' => 'no')).to match([ "steps=standby\n", be_success ])
      output, status = plan('TO' => 'aws', 'REACHABLE' => 'no', 'AFTER_STANDBY' => '1')
      expect(status.exitstatus).to eq(1)
      expect(output).to include('the AWS instance did not come up after the standby', 'nothing touched prod')
      expect(output).not_to include('steps=')
    end

    it 'refuses an unreachable srv host' do
      output, status = plan('REACHABLE' => 'no')
      expect(status.exitstatus).to eq(1)
      expect(output).to include('the srv host is not reachable')
      expect(output).not_to include('steps=')
    end

    it 'refuses an unreachable srv host after a standby too' do
      output, status = plan('REACHABLE' => 'no', 'AFTER_STANDBY' => '1')
      expect(status.exitstatus).to eq(1)
      expect(output).to include('the srv host is not reachable')
    end

    it 'refuses when the live prod does not run the release' do
      output, status = plan('SOURCE_VERSION' => "prod-sha-#{'b' * 40}")
      expect(status.exitstatus).to eq(1)
      expect(output).to include("the live prod runs prod-sha-#{'b' * 40}, not #{release}")
    end

    it 'refuses until fe runs on the target, naming fe\'s Kamal Deploy' do
      output, status = plan('FE_RUNNING' => 'no')
      expect(status.exitstatus).to eq(1)
      expect(output).to include("fe's Kamal Deploy target=srv")
      expect(output).not_to include('steps=')
    end
  end

  describe 'compare-counts' do
    def compare(source, target)
      switch('compare-counts', 'source.counts', 'target.counts',
             files: { 'source.counts' => source, 'target.counts' => target }) { |output, status| return [ output, status ] }
    end

    it 'passes when every table has the same count, whatever the order' do
      output, status = compare("users|3\ntasks|10\n", "tasks|10\nusers|3\n")
      expect(status).to be_success, output
      expect(output).to include('2 tables, every row count matches')
    end

    it 'fails naming each table whose count differs' do
      output, status = compare("users|3\ntasks|10\n", "users|2\ntasks|10\n")
      expect(status.exitstatus).to eq(1)
      expect(output).to include('table users: 3 rows on the live prod, 2 on the target')
      expect(output).not_to include('tasks')
    end

    it 'fails when a table exists on one side only' do
      output, status = compare("users|3\ntasks|10\n", "users|3\n")
      expect(status.exitstatus).to eq(1)
      expect(output).to include('table tasks: 10 rows on the live prod, missing on the target')
    end

    it 'fails on an empty list' do
      expect(compare('', '').last.exitstatus).to eq(1)
      expect(compare("users|3\n", '').last.exitstatus).to eq(1)
    end
  end

  describe 'with DRY_RUN=1' do
    def dry(*args, env: {}, **options, &block)
      switch(*args, env: { 'DRY_RUN' => '1', 'INFRA_PROD_REPO' => 'owner/1_mvp_infra' }.merge(env), files: dev_image_files, **options, &block)
    end

    def dry_lines(output)
      output.lines(chomp: true).grep(/\A\[dry-run\] /)
    end

    it 'prints the freeze of the live prod and runs nothing' do
      dry('freeze', 'prod') do |output, status, root|
        expect(status).to be_success, output
        expect(dry_lines(output)).to eq([
          "[dry-run] bundle exec kamal app maintenance --roles=web --message #{'Prod is moving to another host and is back in a few minutes.'} -c config/deploy.yml",
          "[dry-run] on the AWS host: #{stop_app}"
        ])
        expect(host_logs(root).values).to all(be_empty)
      end
    end

    it 'prints the dump, the restore into the recreated target database, the counts and the boot, and runs nothing' do
      dry('move-data', 'prod', 'prod-srv', version) do |output, status, root|
        expect(status).to be_success, output
        expect(dry_lines(output)).to eq([
          "[dry-run] on the AWS host: docker exec #{name}-db pg_dump -U postgres -d #{name}_prod -Fc",
          "[dry-run] on the srv host: #{stop_app}",
          "[dry-run] on the srv host: docker exec #{name}-db dropdb -U postgres --if-exists --force #{name}_prod",
          "[dry-run] on the srv host: docker exec #{name}-db createdb -U postgres #{name}_prod",
          "[dry-run] on the srv host: docker exec -i #{name}-db pg_restore -U postgres -d #{name}_prod --no-owner --exit-on-error",
          "[dry-run] on the AWS host: docker exec -i #{name}-db psql -U postgres -d #{name}_prod -At -v ON_ERROR_STOP=1",
          "[dry-run] on the srv host: docker exec -i #{name}-db psql -U postgres -d #{name}_prod -At -v ON_ERROR_STOP=1",
          "[dry-run] bundle exec kamal app boot --version #{release} -c config/deploy.prod-srv.yml",
          "[dry-run] wait until /health on the srv host reports release #{DeploySandbox::SHA}"
        ])
        expect(host_logs(root).values).to all(be_empty)
      end
    end

    it 'prints how the target is brought to the release, assuming it needs a deploy, and runs nothing' do
      dry('prepare', 'prod-srv', 'v0.1.0') do |output, status, root|
        expect(status).to be_success, output
        expect(dry_lines(output).last).to eq('[dry-run] bundle exec kamal app live -c config/deploy.prod-srv.yml')
        expect(output).to include('==> the srv host: live deploy')
        expect(output).not_to include('deploy/deploy.sh')
        expect(host_logs(root).values).to all(be_empty)
      end
    end

    it 'prints the standby for the AWS instance, then a deploy after it, and runs nothing' do
      dry('prepare', 'prod', 'v0.1.0', env: { 'PROD_ACTIVE_TARGET' => 'srv' }) do |output, status, root|
        expect(status).to be_success, output
        expect(output).to include('==> the AWS host: standby')
        expect(host_logs(root).values).to all(be_empty)
      end
      dry('prepare', 'prod', 'v0.1.0', env: { 'PROD_ACTIVE_TARGET' => 'srv', 'AFTER_STANDBY' => '1' }) do |output, status|
        expect(status).to be_success, output
        expect(output).to include('==> the AWS host: live deploy')
      end
    end

    it 'with REQUIRE_READY assumes the target job brought the target to the release' do
      dry('prepare', 'prod', 'v0.1.0', env: { 'PROD_ACTIVE_TARGET' => 'srv', 'REQUIRE_READY' => '1' }) do |output, status|
        expect(status).to be_success, output
        expect(output).to include('==> the AWS host: live')
      end
    end

    it 'prints the infra dispatch of the AWS standby and the manual text, and dispatches nothing' do
      dry('standby', files: { 'output' => '' }, env: { 'GITHUB_OUTPUT' => 'output' }) do |output, status, root|
        expect(status).to be_success, output
        expect(dry_lines(output).first).to eq(
          "[dry-run] gh workflow run project-terraform-prod.yml -R owner/1_mvp_infra --ref env/prod -f project=#{name} " \
          "-f action=apply -f confirm=APPLY-PROD-#{name} -f prod_target=aws-standby"
        )
        expect(output).to include('AWS instance running (re-created if absent); records stay on srv')
        expect(File.read(File.join(root, 'output'))).to eq("dispatched=no\n")
        expect(host_logs(root).values).to all(be_empty)
      end
    end

    it 'prints the Kamal Deploy dispatch with prod_switch_run and dispatches nothing' do
      dry('deploy-target', 'aws', 'v0.1.0', env: { 'GITHUB_REPOSITORY' => 'owner/be', 'GITHUB_RUN_ID' => '77' }) do |output, status, root|
        expect(status).to be_success, output
        expect(dry_lines(output).first).to eq(
          '[dry-run] gh workflow run kamal-deploy.yml -R owner/be --ref main -f environment=prod -f target=aws ' \
          '-f version=v0.1.0 -f confirm=prod -f prod_switch_run=77'
        )
        expect(host_logs(root).values).to all(be_empty)
      end
    end

    it 'prints the wait for the AWS instance and the abort check, and runs nothing' do
      dry('wait-host', 'prod', '20') do |output, status, root|
        expect(status).to be_success, output
        expect(dry_lines(output)).to eq([ '[dry-run] wait up to 20 min for SSH on the AWS host' ])
        expect(host_logs(root).values).to all(be_empty)
      end
      dry('abort-check', 'prod', env: { 'GITHUB_REPOSITORY' => 'owner/be', 'GITHUB_RUN_ID' => '77' }) do |output, status, root|
        expect(status).to be_success, output
        expect(dry_lines(output).size).to eq(1)
        expect(host_logs(root).values).to all(be_empty)
      end
    end

    it 'prints the start on the release and the end of maintenance for an abort, and runs nothing' do
      dry('abort', 'prod-srv', version, env: { 'PROD_ACTIVE_TARGET' => 'srv' }) do |output, status, root|
        expect(status).to be_success, output
        expect(dry_lines(output).first(2)).to eq([
          "[dry-run] bundle exec kamal app start --version #{release} -c config/deploy.prod-srv.yml",
          '[dry-run] bundle exec kamal app live -c config/deploy.prod-srv.yml'
        ])
        expect(host_logs(root).values).to all(be_empty)
      end
    end

    it 'prints the infra dispatch and the record changes, and dispatches nothing' do
      dry('dns', 'srv') do |output, status, root|
        expect(status).to be_success, output
        expect(dry_lines(output).first).to eq(
          "[dry-run] gh workflow run project-terraform-prod.yml -R owner/1_mvp_infra --ref env/prod -f project=#{name} " \
          "-f action=apply -f confirm=APPLY-PROD-#{name} -f prod_target=srv"
        )
        expect(output).to include("#{zone} A -> the addresses of dev.#{zone}", "app.#{zone} A -> the addresses of dev.#{zone}")
        expect(host_logs(root).values).to all(be_empty)
      end
    end

    it 'prints the public checks and the tag move, and runs nothing' do
      dry('finalize-public', 'prod-srv', version) do |output, status, root|
        expect(status).to be_success, output
        expect(dry_lines(output).last).to eq("[dry-run] prod-previous <- prod-current, prod-current <- #{release}")
        expect(host_logs(root).values).to all(be_empty)
      end
    end

    it 'prints the stop of the old host and runs nothing' do
      dry('stop-old', 'prod') do |output, status, root|
        expect(status).to be_success, output
        expect(dry_lines(output)).to eq([ "[dry-run] on the AWS host: #{stop_app}" ])
        expect(host_logs(root).values).to all(be_empty)
      end
    end
  end

  describe 'prepare' do
    let(:fe) { { "fe-#{srv}.txt" => "abc123\n" } }

    def prepare(to_dest = 'prod-srv', env: {}, files: {}, **options, &block)
      switch('prepare', to_dest, 'v0.1.0', env: env, files: dev_image_files.merge(fe).merge(files), **options, &block)
    end

    let(:other_version) { { 'version-deploy.yml.txt' => "#{release}\n", 'version-deploy.prod-srv.yml.txt' => "prod-sha-#{'b' * 40}\n" } }

    it 'resumes the paused target and reports deploy, running no deploy script' do
      prepare(files: other_version, containers: "#{name}-web-prod-sha-#{'b' * 40}\n") do |output, status, root|
        expect(status).to be_success, output
        expect(output).to include('==> the srv host: live deploy')
        expect(kamal_calls(root)).to include('exec kamal app live -c config/deploy.prod-srv.yml')
        expect(kamal_calls(root)).not_to include(/kamal (deploy|setup)/)
        expect(log_lines(root, 'crane.log').grep(/\Atag /)).to be_empty
        expect(ssh_commands(root)).to eq([
          "#{name}-prod@#{srv} docker ps --filter name=^#{name}-fe-web- --filter status=running -q stdin=0"
        ])
      end
    end

    it 'writes steps to GITHUB_OUTPUT' do
      prepare(env: { 'GITHUB_OUTPUT' => 'output' }, files: other_version.merge('output' => ''),
              containers: "#{name}-web-prod-sha-#{'b' * 40}\n") do |output, status, root|
        expect(status).to be_success, output
        expect(File.read(File.join(root, 'output'))).to eq("steps=live deploy\n")
      end
    end

    it 'with REQUIRE_READY it refuses a target that does not run the release' do
      prepare(env: { 'REQUIRE_READY' => '1' }, files: other_version, containers: "#{name}-web-prod-sha-#{'b' * 40}\n") do |output, status, root|
        expect(status.exitstatus).to eq(1)
        expect(output).to include("the target does not run #{release}", 'nothing touched prod')
        expect(kamal_calls(root)).not_to include(/app live/)
      end
    end

    it 'leaves a target that already runs the release alone apart from resuming it' do
      files = { 'version.txt' => "#{release}\n" }
      prepare(files: files, containers: "#{name}-web-#{release}\n") do |output, status, root|
        expect(status).to be_success, output
        expect(kamal_calls(root)).to include('exec kamal app live -c config/deploy.prod-srv.yml')
        expect(kamal_calls(root)).not_to include(/kamal (deploy|setup)/)
      end
    end

    it 'reports standby without touching anything when the AWS instance is unreachable' do
      prepare('prod', env: { 'PROD_ACTIVE_TARGET' => 'srv', 'GITHUB_OUTPUT' => 'output' },
                      files: { "nc-#{aws}.fail" => '', 'output' => '' }) do |output, status, root|
        expect(status).to be_success, output
        expect(File.read(File.join(root, 'output'))).to eq("steps=standby\n")
        expect(kamal_calls(root)).to be_empty
        expect(sandbox_log(root, 'ssh.log')).to be_empty
        expect(log_lines(root, 'nc.log')).to eq([ "-z -w 5 #{aws} 22" ] * 3)
      end
    end

    it 'with REQUIRE_READY refuses an AWS instance that still needs the standby' do
      prepare('prod', env: { 'PROD_ACTIVE_TARGET' => 'srv', 'REQUIRE_READY' => '1' }, files: { "nc-#{aws}.fail" => '' }) do |output, status|
        expect(status.exitstatus).to eq(1)
        expect(output).to include('the target does not run', 'nothing touched prod')
      end
    end

    it 'refuses before touching anything when fe does not run on the target' do
      prepare(files: { "fe-#{srv}.txt" => '', 'version.txt' => "#{release}\n" }) do |output, status, root|
        expect(status.exitstatus).to eq(1)
        expect(output).to include("fe's Kamal Deploy target=srv")
        expect(kamal_calls(root)).not_to include(/app live|kamal (deploy|setup)/)
      end
    end

    it 'refuses a switch to the host that is already live' do
      prepare('prod') do |output, status, root|
        expect(status.exitstatus).to eq(1)
        expect(output).to include('the source and the target are both prod')
        expect(host_logs(root).values).to all(be_empty)
      end
    end
  end

  describe 'freeze and abort' do
    it 'puts the live prod into maintenance, then stops its app containers and keeps the service in kamal-proxy' do
      switch('freeze', 'prod') do |output, status, root|
        expect(status).to be_success, output
        expect(kamal_calls(root)).to eq([
          'exec kamal app maintenance --roles=web --message Prod is moving to another host and is back in a few minutes. -c config/deploy.yml'
        ])
        expect(ssh_commands(root)).to eq([ "ubuntu@#{aws} #{stop_app} stdin=0" ])
      end
    end

    it 'starts the live prod on the release by name, ends maintenance and waits for its health' do
      switch('abort', 'prod', version) do |output, status, root|
        expect(status).to be_success, output
        expect(kamal_calls(root)).to eq([
          "exec kamal app start --version #{release} -c config/deploy.yml",
          'exec kamal app live -c config/deploy.yml'
        ])
        expect(log_lines(root, 'curl.log').uniq).to eq([ "-fsS --max-time 5 https://#{zone}/health" ])
        expect(output).to include('DNS was not touched')
      end
    end
  end

  describe 'move-data' do
    let(:counts) { "tasks|10\nusers|3\n" }
    let(:count_sql) do
      "SELECT format('SELECT %L || ''|'' || count(*) FROM public.%I', tablename, tablename) " \
        "FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename \\gexec\n"
    end
    let(:data_files) { { 'dump.bin' => "PGDMP-binary-archive\n", "counts-#{aws}.txt" => counts, "counts-#{srv}.txt" => counts } }

    def move(files: {}, &block)
      switch('move-data', 'prod', 'prod-srv', version, files: data_files.merge(files), &block)
    end

    it 'restores the final dump into the recreated target database, checks the counts, then boots the target' do
      move do |output, status, root|
        expect(status).to be_success, output
        expect(ssh_commands(root)).to eq([
          "ubuntu@#{aws} docker exec #{name}-db pg_dump -U postgres -d #{name}_prod -Fc stdin=0",
          "#{name}-prod@#{srv} #{stop_app} stdin=0",
          "#{name}-prod@#{srv} docker exec #{name}-db dropdb -U postgres --if-exists --force #{name}_prod stdin=0",
          "#{name}-prod@#{srv} docker exec #{name}-db createdb -U postgres #{name}_prod stdin=0",
          "#{name}-prod@#{srv} docker exec -i #{name}-db pg_restore -U postgres -d #{name}_prod --no-owner --exit-on-error stdin=21",
          "ubuntu@#{aws} docker exec -i #{name}-db psql -U postgres -d #{name}_prod -At -v ON_ERROR_STOP=1 stdin=#{count_sql.bytesize}",
          "#{name}-prod@#{srv} docker exec -i #{name}-db psql -U postgres -d #{name}_prod -At -v ON_ERROR_STOP=1 stdin=#{count_sql.bytesize}"
        ])
        expect(kamal_calls(root)).to eq([ "exec kamal app boot --version #{release} -c config/deploy.prod-srv.yml" ])
        expect(output).to include('2 tables, every row count matches', 'The data is on the srv host')
      end
    end

    it 'stops before DNS without booting the target when a count differs' do
      move(files: { "counts-#{srv}.txt" => "tasks|10\nusers|2\n" }) do |output, status, root|
        expect(status.exitstatus).to eq(1)
        expect(output).to include('table users: 3 rows on the live prod, 2 on the target', 'DNS was not touched')
        expect(output).not_to include('The data is on')
        expect(kamal_calls(root)).not_to include(/app boot/)
      end
    end

    it 'touches nothing on the target when the dump is not a pg_dump archive' do
      move(files: { 'dump.bin' => "error: connection refused\n" }) do |output, status, root|
        expect(status.exitstatus).to eq(1)
        expect(output).to include('is not a pg_dump archive')
        expect(ssh_commands(root).size).to eq(1)
        expect(kamal_calls(root)).to be_empty
      end
    end

    it 'keeps no copy of the dump' do
      move do |_output, status, root|
        expect(status).to be_success
        expect(Dir.glob(File.join(root, '**', 'prod-switch.*'))).to be_empty
      end
    end
  end

  describe 'dns' do
    let(:dns_env) { { 'INFRA_PROD_REPO' => 'owner/1_mvp_infra', 'DNS_WAIT_MINUTES' => '1', 'DNS_POLL_SECONDS' => '30' } }
    let(:moved) { { 'hosts-next.txt' => public_dns('srv') } }
    let(:dispatch) do
      "workflow run project-terraform-prod.yml -R owner/1_mvp_infra --ref env/prod -f project=#{name} -f action=apply " \
        "-f confirm=APPLY-PROD-#{name} -f prod_target=srv"
    end
    let(:infra_run) do
      { 'gh-runs.json' => '[{"databaseId":42,"createdAt":"2999-01-01T00:00:00Z"}]', 'gh-view.json' => '{"jobs":[{"conclusion":"success"}]}' }
    end

    def dns(env: {}, files: {}, &block)
      switch('dns', 'srv', env: dns_env.merge(env), files: files, &block)
    end

    it 'without a dispatch token prints the command and the record changes, then waits for public DNS' do
      dns(files: moved) do |output, status, root|
        expect(status).to be_success, output
        expect(output).to include('INFRA_PROD_DISPATCH_TOKEN is not set', "gh #{dispatch}",
                                  "#{zone} A -> the addresses of dev.#{zone}", 'never in the Route53 console',
                                  "points at srv")
        expect(sandbox_log(root, 'gh.log')).to be_empty
      end
    end

    it 'dispatches the infra apply with prod_target, watches it and waits for public DNS' do
      dns(env: { 'GH_TOKEN' => 'token' }, files: moved.merge(infra_run)) do |output, status, root|
        expect(status).to be_success, output
        gh = log_lines(root, 'gh.log')
        expect(gh.first(2)).to eq([ 'workflow view project-terraform-prod.yml -R owner/1_mvp_infra --ref env/prod --yaml', dispatch ])
        expect(gh).to include('run watch 42 -R owner/1_mvp_infra --exit-status')
        expect(output).not_to include('up to the operator')
      end
    end

    it 'falls back to the operator when the dispatch fails' do
      dns(env: { 'GH_TOKEN' => 'token' }, files: moved.merge('gh-dispatch.code' => '1')) do |output, status|
        expect(status).to be_success, output
        expect(output).to include('the infra dispatch failed', 'up to the operator', "gh #{dispatch}")
      end
    end

    it 'falls back to the operator when every job of the infra run was skipped' do
      skipped = infra_run.merge('gh-view.json' => '{"jobs":[{"conclusion":"skipped"}]}')
      dns(env: { 'GH_TOKEN' => 'token' }, files: moved.merge(skipped)) do |output, status|
        expect(status).to be_success, output
        expect(output).to include('was skipped', 'up to the operator')
      end
    end

    it 'falls back to the operator without dispatching when prod_target does not offer the target' do
      files = moved.merge(infra_run).merge('gh-workflow.yml' => infra_workflow(%w[aws]))
      dns(env: { 'GH_TOKEN' => 'token' }, files: files) do |output, status, root|
        expect(status).to be_success, output
        expect(output).to include('offers no prod_target=srv', 'up to the operator', "gh #{dispatch}")
        expect(log_lines(root, 'gh.log').grep(/workflow run/)).to be_empty
      end
    end

    it 'dispatches when prod_target offers the target' do
      files = moved.merge(infra_run).merge('gh-workflow.yml' => infra_workflow(%w[aws srv aws-standby]))
      dns(env: { 'GH_TOKEN' => 'token' }, files: files) do |output, status, root|
        expect(status).to be_success, output
        expect(log_lines(root, 'gh.log')).to include(dispatch)
        expect(output).not_to include('up to the operator')
      end
    end

    it 'fails when public DNS never shows the target' do
      dns do |output, status|
        expect(status.exitstatus).to eq(1)
        expect(output).to include('public DNS did not show srv within 1 min', 'after DNS')
      end
    end
  end

  describe 'finalize-public' do
    let(:config_js) { %(window.APP_CONFIG = { API_URL: "https://#{zone}", GOOGLE_CLIENT_ID: "", ENV_NAME: "prod", APP_VERSION: "v0.1.0" };\n) }
    let(:digests) { "#{release} sha256:new\nprod-current sha256:old\nprod-srv-current sha256:new\n" }

    def finalize(files: {}, **options, &block)
      fixtures = { 'hosts.txt' => public_dns('srv'), 'config.js' => config_js, 'digests' => digests }.merge(files)
      switch('finalize-public', 'prod-srv', version, env: { 'PROD_ACTIVE_TARGET' => 'srv' }, files: fixtures, **options, &block)
    end

    it 'checks /health, the smoke and config.js pinned to the new addresses, then moves prod-current' do
      finalize do |output, status, root|
        expect(status).to be_success, output
        curl = log_lines(root, 'curl.log')
        expect(curl).to include("-fsS --max-time 5 --resolve #{zone}:443:192.0.2.20 https://#{zone}/health",
                                "-fsS --max-time 10 --resolve app.#{zone}:443:192.0.2.20 https://app.#{zone}/config.js")
        expect(sandbox_log(root, 'smoke.log').strip).to eq(
          "https://#{zone} SMOKE_CONNECT_TO=#{zone}:443:192.0.2.20:443 SMOKE_FORWARDED_PROTO= SMOKE_READ_ONLY=1"
        )
        expect(log_lines(root, 'crane.log').grep(/\Atag /)).to eq([
          "tag #{repo}@sha256:old prod-previous",
          "tag #{repo}@sha256:new prod-current"
        ])
      end
    end

    it 'leaves the tags alone when prod-current already is the release' do
      finalize(files: { 'digests' => "#{release} sha256:new\nprod-current sha256:new\nprod-srv-current sha256:new\n" }) do |output, status, root|
        expect(status).to be_success, output
        expect(log_lines(root, 'crane.log').grep(/\Atag /)).to be_empty
      end
    end

    it 'fails without moving a tag when config.js does not point at the zone' do
      finalize(files: { 'config.js' => config_js.sub("https://#{zone}", 'https://dev.example.test') }) do |output, status, root|
        expect(status.exitstatus).to eq(1)
        expect(output).to include('config.js does not set API_URL')
        expect(log_lines(root, 'crane.log').grep(/\Atag /)).to be_empty
      end
    end

    it 'fails without checking anything when public DNS does not show the target' do
      finalize(files: { 'hosts.txt' => public_dns('aws') }) do |output, status, root|
        expect(status.exitstatus).to eq(1)
        expect(output).to include('public DNS does not show srv')
        expect(sandbox_log(root, 'curl.log')).to be_empty
      end
    end

    it 'fails without moving a tag while /health on the new address reports another release' do
      finalize(release: 'b' * 40) do |output, status, root|
        expect(status.exitstatus).to eq(1)
        expect(output).to include("did not report release #{DeploySandbox::SHA}")
        expect(sandbox_log(root, 'smoke.log')).to be_empty
        expect(log_lines(root, 'crane.log').grep(/\Atag /)).to be_empty
      end
    end
  end

  describe 'stop-old' do
    it 'stops, never removes, the old host\'s app containers and leaves its service paused in kamal-proxy' do
      switch('stop-old', 'prod', env: { 'PROD_ACTIVE_TARGET' => 'srv' }) do |output, status, root|
        expect(status).to be_success, output
        expect(kamal_calls(root)).to be_empty
        expect(ssh_commands(root)).to eq([ "ubuntu@#{aws} #{stop_app} stdin=0" ])
      end
    end

    it 'succeeds without SSH when infra already stopped the AWS instance' do
      switch('stop-old', 'prod', env: { 'PROD_ACTIVE_TARGET' => 'srv' }, files: { "nc-#{aws}.fail" => '' }) do |output, status, root|
        expect(status).to be_success, output
        expect(output).to include('the AWS instance is stopped by infra (prod_target=srv)')
        expect(sandbox_log(root, 'ssh.log')).to be_empty
      end
    end

    it 'fails for an unreachable srv host' do
      switch('stop-old', 'prod-srv', files: { "nc-#{srv}.fail" => '' }) do |output, status, root|
        expect(status.exitstatus).to eq(1)
        expect(output).to include('the srv host is not reachable')
        expect(sandbox_log(root, 'ssh.log')).to be_empty
      end
    end
  end

  describe 'infra-options' do
    def options(yaml)
      switch('infra-options', stdin: yaml) { |output, status| return [ output, status ] }
    end

    it 'prints the options of the prod_target input, from a block or an inline list' do
      expect(options(infra_workflow(%w[aws srv]))).to match([ "aws\nsrv\n", be_success ])
      expect(options(infra_workflow(%w[aws srv aws-standby], inline: true))).to match([ "aws\nsrv\naws-standby\n", be_success ])
    end

    it 'prints nothing for a workflow without a prod_target input' do
      expect(options("on:\n  workflow_dispatch:\n    inputs:\n      action:\n        options:\n          - plan\n")).to match([ '', be_success ])
    end
  end

  describe 'standby' do
    let(:standby_env) { { 'INFRA_PROD_REPO' => 'owner/1_mvp_infra', 'GITHUB_OUTPUT' => 'output' } }
    let(:dispatch) do
      "workflow run project-terraform-prod.yml -R owner/1_mvp_infra --ref env/prod -f project=#{name} -f action=apply " \
        "-f confirm=APPLY-PROD-#{name} -f prod_target=aws-standby"
    end
    let(:infra_run) do
      { 'gh-runs.json' => '[{"databaseId":42,"createdAt":"2999-01-01T00:00:00Z"}]', 'gh-view.json' => '{"jobs":[{"conclusion":"success"}]}',
        'output' => '' }
    end

    def standby(env: {}, files: {}, &block)
      switch('standby', env: standby_env.merge(env), files: infra_run.merge(files), &block)
    end

    def dispatched(root)
      File.read(File.join(root, 'output'))
    end

    it 'dispatches the infra apply with prod_target=aws-standby when infra offers it, and watches it' do
      standby(env: { 'GH_TOKEN' => 'token' }, files: { 'gh-workflow.yml' => infra_workflow(%w[aws srv aws-standby]) }) do |output, status, root|
        expect(status).to be_success, output
        expect(log_lines(root, 'gh.log')).to include(dispatch, 'run watch 42 -R owner/1_mvp_infra --exit-status')
        expect(dispatched(root)).to eq("dispatched=yes\n")
        expect(output).not_to include('up to the operator')
      end
    end

    it 'dispatches when the infra workflow cannot be read' do
      standby(env: { 'GH_TOKEN' => 'token' }) do |output, status, root|
        expect(status).to be_success, output
        expect(log_lines(root, 'gh.log')).to include(dispatch)
        expect(dispatched(root)).to eq("dispatched=yes\n")
      end
    end

    it 'falls back to the operator without a dispatch when infra does not offer aws-standby' do
      standby(env: { 'GH_TOKEN' => 'token' }, files: { 'gh-workflow.yml' => infra_workflow(%w[aws srv]) }) do |output, status, root|
        expect(status).to be_success, output
        expect(output).to include('offers no prod_target=aws-standby', 'up to the operator', "gh #{dispatch}",
                                  'AWS instance running (re-created if absent); records stay on srv')
        expect(log_lines(root, 'gh.log').grep(/workflow run/)).to be_empty
        expect(dispatched(root)).to eq("dispatched=no\n")
      end
    end

    it 'falls back to the operator when the dispatch fails or the token is missing' do
      standby(env: { 'GH_TOKEN' => 'token' }, files: { 'gh-dispatch.code' => '1' }) do |output, status, root|
        expect(status).to be_success, output
        expect(output).to include('the infra dispatch failed', 'up to the operator')
        expect(dispatched(root)).to eq("dispatched=no\n")
      end
      standby do |output, status, root|
        expect(status).to be_success, output
        expect(output).to include('INFRA_PROD_DISPATCH_TOKEN is not set', 'up to the operator')
        expect(sandbox_log(root, 'gh.log')).to be_empty
        expect(dispatched(root)).to eq("dispatched=no\n")
      end
    end
  end

  describe 'wait-host' do
    it 'succeeds once SSH on the host answers' do
      switch('wait-host', 'prod', '1', env: { 'STANDBY_POLL_SECONDS' => '30' }) do |output, status, root|
        expect(status).to be_success, output
        expect(log_lines(root, 'nc.log')).to eq([ "-z -w 5 #{aws} 22" ])
      end
    end

    it 'fails, nothing touched, when SSH never answers' do
      switch('wait-host', 'prod', '1', env: { 'STANDBY_POLL_SECONDS' => '30' }, files: { "nc-#{aws}.fail" => '' }) do |output, status, root|
        expect(status.exitstatus).to eq(1)
        expect(output).to include('did not answer within 1 min', 'nothing touched prod', 'run Prod Switch again')
        expect(log_lines(root, 'nc.log').size).to eq(2)
      end
    end
  end

  describe 'deploy-target' do
    let(:run_env) { { 'GITHUB_REPOSITORY' => 'owner/be', 'GITHUB_RUN_ID' => '77' } }
    let(:runs) do
      { 'gh-runs.json' => '[{"databaseId":5,"displayTitle":"Kamal Deploy aws v0.1.0"},' \
                          '{"databaseId":9,"displayTitle":"Kamal Deploy aws v0.1.0 for Prod Switch 77"}]' }
    end
    let(:dispatch) do
      'workflow run kamal-deploy.yml -R owner/be --ref main -f environment=prod -f target=aws -f version=v0.1.0 ' \
        "-f source_sha=#{'c' * 40} -f confirm=prod -f prod_switch_run=77"
    end

    it 'dispatches Kamal Deploy with every input, finds its run by title and watches it' do
      switch('deploy-target', 'aws', 'v0.1.0', 'c' * 40, env: run_env, files: runs) do |output, status, root|
        expect(status).to be_success, output
        gh = log_lines(root, 'gh.log')
        expect(gh.first).to eq(dispatch)
        expect(gh).to include('run watch 9 -R owner/be --exit-status')
      end
    end

    it 'fails, nothing touched, when the Kamal Deploy run fails' do
      switch('deploy-target', 'aws', 'v0.1.0', env: run_env, files: runs.merge('gh-watch.code' => '1')) do |output, status|
        expect(status.exitstatus).to eq(1)
        expect(output).to include('the target deploy (Kamal Deploy run 9) failed', 'nothing touched prod')
      end
    end
  end

  describe 'switch-run-check' do
    let(:run) do
      { 'path' => '.github/workflows/prod-switch.yml', 'event' => 'workflow_dispatch', 'status' => 'in_progress',
        'head_branch' => 'main', 'display_title' => 'Prod Switch to srv' }
    end

    def check(id = '77', changes: {}, target: 'srv', active: 'aws', files: {}, &block)
      switch('switch-run-check', id, env: { 'GITHUB_REPOSITORY' => 'owner/be', 'TARGET' => target, 'ACTIVE_TARGET' => active },
                                     files: { 'gh-run.json' => run.merge(changes).to_json }.merge(files), &block)
    end

    it 'passes for an in-progress Prod Switch on main to the deploy target, which is not the live host' do
      check do |output, status, root|
        expect(status).to be_success, output
        expect(log_lines(root, 'gh.log')).to eq([ 'api repos/owner/be/actions/runs/77' ])
      end
    end

    it "accepts the title prod-switch.yml's run-name gives a real switch, and refuses a dry run's" do
      run_name = YAML.load_file(Rails.root.join('.github/workflows/prod-switch.yml')).fetch('run-name')
      { 'srv' => 'aws', 'aws' => 'srv' }.each do |to, live|
        [ false, true ].each do |dry_run|
          title = GithubExpression.interpolate(run_name, 'inputs' => { 'to' => to, 'dry_run' => dry_run })
          check(target: to, active: live, changes: { 'display_title' => title }) do |output, status|
            expect(status.success?).to eq(!dry_run), "#{title}: #{output}"
          end
        end
      end
    end

    it 'refuses another workflow, event, state, branch or title, or a target that is the live host' do
      {
        { 'path' => '.github/workflows/kamal-deploy.yml' } => 'not a Prod Switch run',
        { 'event' => 'push' } => 'not dispatched',
        { 'status' => 'completed' } => 'not in progress',
        { 'head_branch' => 'develop' } => 'not on main',
        { 'display_title' => 'Prod Switch to srv (dry run)' } => "not titled 'Prod Switch to srv'"
      }.each do |changes, message|
        check(changes: changes) do |output, status|
          expect(status.exitstatus).to eq(1), changes.inspect
          expect(output).to include("::error::Prod Switch run 77 is #{message}"), changes.inspect
        end
      end
      check(target: 'aws', changes: { 'display_title' => 'Prod Switch to aws' }) do |output, status|
        expect(status.exitstatus).to eq(1)
        expect(output).to include('::error::aws is the live prod host')
      end
    end

    it 'refuses a run id that is not a number or cannot be read' do
      check('77; true') do |output, status, root|
        expect(status.exitstatus).to eq(1)
        expect(output).to include('prod_switch_run must be a run id')
        expect(sandbox_log(root, 'gh.log')).to be_empty
      end
      check(files: { 'gh-api.fail' => '' }) do |output, status|
        expect(status.exitstatus).to eq(1)
        expect(output).to include('could not read Prod Switch run 77')
      end
    end
  end

  describe 'dns-began and abort-check' do
    def job(name, runner: nil, steps: [], started: '2026-11-01T14:09:30Z')
      { 'name' => name, 'status' => 'completed', 'conclusion' => 'cancelled', 'started_at' => started,
        'runner_name' => runner, 'steps' => steps }
    end

    let(:dns_job) { 'Switch DNS (operator approval)' }
    let(:never_began) { { 'total_count' => 2, 'jobs' => [ job('Guard (ref, confirm, version, live host)', runner: 'r1', steps: [ {} ]), job(dns_job) ] } }
    let(:began) { { 'total_count' => 1, 'jobs' => [ job(dns_job, runner: 'r2') ] } }

    def began?(pages)
      switch('dns-began', stdin: pages.map(&:to_json).join("\n")) { |output, status| return [ output, status ] }
    end

    it 'counts a job as begun only with a runner or a step, never by started_at alone' do
      expect(began?([ never_began ])).to match([ "no\n", be_success ])
      expect(began?([ began ])).to match([ "yes\n", be_success ])
      expect(began?([ { 'jobs' => [ job(dns_job, steps: [ { 'name' => 'Set up job' } ]) ] } ])).to match([ "yes\n", be_success ])
      expect(began?([ { 'jobs' => [] } ])).to match([ "no\n", be_success ])
      expect(began?([ { 'jobs' => [ job('Guard') ] }, began ])).to match([ "yes\n", be_success ])
    end

    def abort_check(jobs: never_began, files: {}, &block)
      switch('abort-check', 'prod', env: { 'GITHUB_REPOSITORY' => 'owner/be', 'GITHUB_RUN_ID' => '77' },
                                    files: { 'gh-jobs.json' => jobs.to_json }.merge(files), &block)
    end

    it 'passes when public DNS shows the source and prod-dns never began' do
      abort_check do |output, status, root|
        expect(status).to be_success, output
        expect(log_lines(root, 'gh.log')).to eq([ 'api --paginate repos/owner/be/actions/runs/77/jobs' ])
      end
    end

    it 'refuses when prod-dns began, DNS shows another host or the jobs cannot be read' do
      abort_check(jobs: began) do |output, status|
        expect(status.exitstatus).to eq(1)
        expect(output).to include('the prod-dns job began', 'prod stays in maintenance')
      end
      abort_check(files: { 'hosts.txt' => public_dns('srv') }) do |output, status, root|
        expect(status.exitstatus).to eq(1)
        expect(output).to include('public DNS shows srv, not aws', 'prod stays in maintenance')
        expect(sandbox_log(root, 'gh.log')).to be_empty
      end
      abort_check(files: { 'gh-api.fail' => '' }) do |output, status|
        expect(status.exitstatus).to eq(1)
        expect(output).to include('could not read the jobs of this run', 'prod stays in maintenance')
      end
    end
  end

  it 'refuses an unknown subcommand or a wrong number of arguments' do
    [ [], [ 'switch' ], [ 'freeze' ], [ 'move-data', 'prod', 'prod-srv' ], [ 'standby', 'aws' ], [ 'deploy-target', 'aws' ],
      [ 'abort-check' ] ].each do |args|
      switch(*args) do |output, status|
        expect(status.exitstatus).to eq(2), args.inspect
        expect(output).to include('Usage: deploy/prod_switch.sh guard')
      end
    end
  end
end
