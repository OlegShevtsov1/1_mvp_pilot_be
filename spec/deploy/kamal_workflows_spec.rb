require 'rails_helper'

RSpec.describe 'prod workflows' do
  def load_workflow(file)
    # YAML 1.1 reads the `on:` key as true.
    YAML.load_file(Rails.root.join('.github/workflows', file)).transform_keys { |key| key == true ? 'on' : key }
  end

  def needs(job)
    Array(job['needs'])
  end

  def transitive_needs(jobs, name)
    needs(jobs.fetch(name)).flat_map { |parent| [ parent, *transitive_needs(jobs, parent) ] }.uniq
  end

  def step(job, name)
    job.fetch('steps').find { |candidate| candidate['name'] == name } || raise("no step #{name}")
  end

  let(:kamal_secrets) do
    output, status = Open3.capture2e('bash', '-c', 'source deploy/_common.sh && secret_names .kamal/secrets.prod', chdir: Rails.root)
    expect(status).to be_success
    output.split - %w[PROJECT_NAME KAMAL_REGISTRY_PASSWORD]
  end

  # The public mirror runs these workflows unchanged with its own VPN client; on the primary the values are
  # empty and vpn-up keeps its default profile. Addresses stay in secrets and variables, never in the file.
  let(:vpn_up_inputs) do
    [
      [ 'ovpn', '${{ secrets.VPN_CI_OVPN }}' ],
      [ 'ci-vpn-ip', '${{ secrets.CI_VPN_IP }}' ],
      [ 'dev-host', '${{ secrets.DEV_HOST }}' ],
      [ 'dns-zones', '${{ vars.DNS_ZONES }}' ]
    ]
  end

  # Concurrency groups are shared across workflow and job level: Kamal Manage holds kamal-prod for
  # the whole run, Kamal Deploy only for its deploy job, so a rollback never waits for release-watch.
  shared_examples 'a guarded prod workflow' do |file, job_name, run_step, concurrency_job, extra_prod_jobs = []|
    let(:workflow) { load_workflow(file) }
    let(:jobs) { workflow.fetch('jobs') }
    let(:kamal_prod) { { 'group' => 'kamal-prod', 'cancel-in-progress' => false } }

    # Only Kamal Deploy dispatched by Prod Switch (prod_switch_run, checked in its guard) takes a group of its own:
    # Prod Switch holds kamal-prod for its whole run and waits for that deploy.
    it 'shares the kamal-prod concurrency group and never cancels a running operation' do
      if concurrency_job
        expect(workflow).not_to have_key('concurrency')
        concurrency = jobs.fetch(concurrency_job).fetch('concurrency')
        group = ->(run) { GithubExpression.interpolate(concurrency.fetch('group'), 'inputs' => { 'prod_switch_run' => run }) }
        expect(concurrency.merge('group' => group.call(''))).to eq(kamal_prod)
        expect(group.call('77')).to eq('kamal-prod-switch')
        (jobs.keys - [ concurrency_job ]).each { |name| expect(jobs.fetch(name)).not_to have_key('concurrency'), name }
      else
        expect(workflow.fetch('concurrency')).to eq(kamal_prod)
      end
    end

    it 'runs the guard first and makes every other job wait for it' do
      expect(jobs.fetch('guard')).not_to have_key('needs')
      (jobs.keys - %w[guard]).each { |name| expect(transitive_needs(jobs, name)).to include('guard'), name }
    end

    it 'keeps the prod secrets in the prod environment' do
      [ 'preflight', job_name, 'notify', *extra_prod_jobs ].each { |name| expect(jobs.fetch(name)['environment']).to eq('prod'), name }
      expect(jobs.fetch('guard')).not_to have_key('environment')
    end

    # A variable .kamal/secrets.prod reads but a step does not map would reach Kamal as an empty string.
    it 'maps every secret .kamal/secrets.prod reads, and both host addresses, into the preflight and the run step' do
      expect(kamal_secrets).not_to be_empty
      [ step(jobs.fetch('preflight'), 'Check that every required secret is set'), step(jobs.fetch(job_name), run_step) ].each do |checked|
        (kamal_secrets + %w[PROD_VPN_IP PROD_SRV_VPN_IP]).each { |name| expect(checked.fetch('env')[name]).to eq("${{ secrets.#{name} }}") }
      end
    end

    it 'offers target aws (the default) or srv and maps it to a destination in the guard' do
      target = workflow.dig('on', 'workflow_dispatch', 'inputs', 'target')
      expect(target).to include('type' => 'choice', 'options' => %w[aws srv], 'default' => 'aws', 'required' => true)
      expect(step(jobs.fetch('guard'), 'Check the ref and the inputs').fetch('env')).to include('TARGET' => '${{ inputs.target }}')
      expect(jobs.fetch('guard').fetch('outputs')).to include('destination' => '${{ steps.inputs.outputs.destination }}')
      expect(jobs.fetch(job_name).fetch('env')).to include('DESTINATION' => '${{ needs.guard.outputs.destination }}')
      expect(step(jobs.fetch('report'), 'Summarize the job results').fetch('env'))
        .to include('WHERE' => "${{ needs.guard.outputs.destination || 'prod' }}")
    end

    # `secrets.PROD_SRV_X || secrets.PROD_X` would fall back to the AWS host when an srv secret is empty.
    it 'picks the srv secrets in shell, never with an expression that can fall back to AWS' do
      text = Rails.root.join('.github/workflows', file).read
      expect(text.lines.grep(/PROD_SRV_/).grep(/\|\|/)).to be_empty
    end

    it 'requires the secrets of the chosen host only' do
      preflight = step(jobs.fetch('preflight'), 'Check that every required secret is set')
      expect(preflight.fetch('env')).to include('PROD_SRV_SSH_KEY' => '${{ secrets.PROD_SRV_SSH_KEY }}',
                                                'DESTINATION' => '${{ needs.guard.outputs.destination }}')
      all_set = preflight.fetch('env').keys.index_with { 'x' }.merge('GITHUB_WORKFLOW' => 'Test')
      {
        'prod' => [ %w[PROD_SSH_KEY PROD_VPN_IP], %w[PROD_SRV_SSH_KEY PROD_SRV_VPN_IP] ],
        'prod-srv' => [ %w[PROD_SRV_SSH_KEY PROD_SRV_VPN_IP], %w[PROD_SSH_KEY PROD_VPN_IP] ]
      }.each do |destination, (needed, unused)|
        env = all_set.merge('DESTINATION' => destination)
        output, status = Open3.capture2e(env.merge(unused.index_with { '' }), 'bash', '-e', '-c', preflight.fetch('run'), chdir: Rails.root)
        expect(status).to be_success, "#{destination}: #{output}"
        output, status = Open3.capture2e(env.merge(needed.index_with { '' }), 'bash', '-e', '-c', preflight.fetch('run'), chdir: Rails.root)
        expect(status).not_to be_success
        expect(output).to include("missing secrets: #{needed.join(' ')} ("), destination
      end
    end

    it "loads the chosen host's SSH key and checks that host's SSH port" do
      key_step = step(jobs.fetch(job_name), 'Load the prod SSH key into an agent (never written to disk)')
      reach_step = step(jobs.fetch(job_name), 'Check that prod is reachable over the VPN')
      expect(key_step.fetch('env')).to include('PROD_SRV_SSH_KEY' => '${{ secrets.PROD_SRV_SSH_KEY }}')
      expect(reach_step.fetch('env')).to include('PROD_SRV_VPN_IP' => '${{ secrets.PROD_SRV_VPN_IP }}')

      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, 'bin'))
        write_executable(File.join(dir, 'bin/ssh-agent'), "#!/usr/bin/env bash\necho 'SSH_AUTH_SOCK=sock; export SSH_AUTH_SOCK;'\n")
        write_executable(File.join(dir, 'bin/ssh-add'), "#!/usr/bin/env bash\ncat > \"#{dir}/key\"\n")
        write_executable(File.join(dir, 'bin/nc'), "#!/usr/bin/env bash\necho \"$*\" > \"#{dir}/nc\"\n")
        base = { 'PATH' => "#{dir}/bin:#{ENV.fetch('PATH')}", 'RUNNER_TEMP' => dir, 'GITHUB_ENV' => File.join(dir, 'env'),
                 'PROD_SSH_KEY' => 'aws-key', 'PROD_SRV_SSH_KEY' => 'srv-key',
                 'PROD_VPN_IP' => '192.0.2.70', 'PROD_SRV_VPN_IP' => '192.0.2.80' }
        { 'prod' => [ 'aws-key', '192.0.2.70' ], 'prod-srv' => [ 'srv-key', '192.0.2.80' ] }.each do |destination, (key, host)|
          env = base.merge('DESTINATION' => destination)
          [ key_step, reach_step ].each do |checked|
            output, status = Open3.capture2e(env, 'bash', '-e', '-c', checked.fetch('run'), chdir: dir)
            expect(status).to be_success, output
          end
          expect(File.read(File.join(dir, 'key')).strip).to eq(key), destination
          expect(File.read(File.join(dir, 'nc')).strip).to eq("-z -w 5 #{host} 22"), destination
        end
      end
    end

    it 'passes the GOOGLE_CLIENT_ID environment variable to Kamal in the run step' do
      expect(step(jobs.fetch(job_name), run_step).dig('env', 'GOOGLE_CLIENT_ID')).to eq('${{ vars.GOOGLE_CLIENT_ID }}')
    end

    it 'passes the OAUTH_CLIENT_ID environment variable to Kamal in the run step' do
      expect(step(jobs.fetch(job_name), run_step).dig('env', 'OAUTH_CLIENT_ID')).to eq('${{ vars.OAUTH_CLIENT_ID }}')
    end

    it 'connects the VPN before Kamal and always disconnects it' do
      uses = jobs.fetch(job_name).fetch('steps').map { |s| s['uses'].to_s }
      up = uses.index { |u| u == './infra-helpers/.github/actions/vpn-up' }
      down = uses.index { |u| u == './infra-helpers/.github/actions/vpn-down' }
      run = jobs.fetch(job_name).fetch('steps').index { |s| s['name'] == run_step }

      expect([ up, run, down ]).to all(be_a(Integer))
      expect(up).to be < run
      expect(run).to be < down
      expect(jobs.fetch(job_name).fetch('steps')[down]['if']).to eq('always()')
    end

    it 'passes the mirror VPN client inputs to every vpn-up step' do
      vpn_ups = jobs.values.flat_map { |job| job.fetch('steps') { [] } }.select { |s| s['uses'].to_s == './infra-helpers/.github/actions/vpn-up' }

      expect(vpn_ups).not_to be_empty
      vpn_ups.each { |s| expect(s.fetch('with').to_a).to eq(vpn_up_inputs), s['name'] }
    end

    # A run queued behind a Prod Switch must see the host that switch left live, not the one before it.
    it 'reads the live prod host from public DNS inside the kamal-prod lock, before the VPN, and hands it to the run step' do
      reader_name = concurrency_job || 'guard'
      reader = jobs.fetch(reader_name)
      reader_steps = reader.fetch('steps')
      active = step(reader, 'Find the live prod host (public DNS)')
      vpn_up = reader_steps.index { |s| s['uses'].to_s == './infra-helpers/.github/actions/vpn-up' }

      expect(active).to include('id' => 'active', 'run' => 'deploy/prod_active_target.sh >> "${GITHUB_OUTPUT}"')
      expect(reader_steps.index(active)).to be < vpn_up if vpn_up
      expect(reader.fetch('outputs')).to include('active_target' => '${{ steps.active.outputs.active_target }}')
      handed = reader_name == job_name ? '${{ steps.active.outputs.active_target }}' : "${{ needs.#{reader_name}.outputs.active_target }}"
      expect(step(jobs.fetch(job_name), run_step).fetch('env')).to include('PROD_ACTIVE_TARGET' => handed)
      (jobs.keys - [ reader_name ]).each { |name| expect(jobs.fetch(name).fetch('outputs') { {} }).not_to have_key('active_target'), name }
    end

    it 'only runs Kamal through the deploy scripts and has no Kamal 1 leftovers' do
      text = Rails.root.join('.github/workflows', file).read
      expect(text).not_to match(/traefik/i)
      expect(text).not_to match(/\bkamal /)
    end
  end

  describe '.github/workflows/kamal-deploy.yml' do
    it_behaves_like 'a guarded prod workflow', 'kamal-deploy.yml', 'deploy', 'Deploy', 'deploy', %w[release-watch]

    let(:workflow) { load_workflow('kamal-deploy.yml') }
    let(:jobs) { workflow.fetch('jobs') }

    it 'connects the VPN in deploy and release-watch only' do
      with_vpn = jobs.select { |_, job| job.fetch('steps') { [] }.any? { |s| s['uses'].to_s == './infra-helpers/.github/actions/vpn-up' } }
      expect(with_vpn.keys).to contain_exactly('deploy', 'release-watch')
    end

    it 'takes exactly environment (prod only), target, version, an optional source_sha, confirm and an optional prod_switch_run' do
      inputs = workflow.dig('on', 'workflow_dispatch', 'inputs')
      expect(inputs.keys).to eq(%w[environment target version source_sha confirm prod_switch_run])
      expect(inputs.dig('environment', 'options')).to eq(%w[prod])
      expect(inputs.fetch('source_sha')).to include('type' => 'string', 'required' => false)
      expect(inputs.fetch('prod_switch_run')).to include('type' => 'string', 'required' => false, 'default' => '')
    end

    it 'checks a prod_switch_run in the guard, after the live host is known, and names it in the run title' do
      guard = jobs.fetch('guard')
      names = guard.fetch('steps').map { |s| s['name'] }
      check = step(guard, 'Check the Prod Switch run')
      expect(names.index('Check the Prod Switch run')).to eq(names.index('Find the live prod host (public DNS)') + 1)
      expect(check.fetch('run')).to eq('deploy/prod_switch.sh switch-run-check "${RUN_ID}"')
      expect(check.fetch('env')).to eq('RUN_ID' => '${{ inputs.prod_switch_run }}', 'TARGET' => '${{ inputs.target }}',
                                       'ACTIVE_TARGET' => '${{ steps.active.outputs.active_target }}', 'GH_TOKEN' => '${{ github.token }}')
      expect(GithubExpression.evaluate(check.fetch('if'), 'inputs' => { 'prod_switch_run' => '77' })).to be(true)
      expect(GithubExpression.evaluate(check.fetch('if'), 'inputs' => { 'prod_switch_run' => '' })).to be(false)
      expect(guard.fetch('permissions')).to eq('contents' => 'read', 'actions' => 'read')
      expect(needs(jobs.fetch('deploy'))).to include('guard')
      title = ->(run) { GithubExpression.interpolate(workflow.fetch('run-name'), 'inputs' => { 'target' => 'aws', 'version' => 'v0.1.0', 'prod_switch_run' => run }) }
      expect(title.call('')).to eq('Kamal Deploy aws v0.1.0')
      expect(title.call('77')).to eq('Kamal Deploy aws v0.1.0 for Prod Switch 77')
    end

    it 'checks the inputs with deploy/prod_guard.sh deploy and the tag with deploy/release_tag_check.sh' do
      guard = jobs.fetch('guard')
      checkout = guard.fetch('steps').find { |s| s['uses'].to_s.start_with?('actions/checkout@') }
      tag_check = step(guard, 'Check that the version is an annotated release tag on main')

      expect(checkout.fetch('with')).to include('fetch-depth' => 0)
      expect(step(guard, 'Check the ref and the inputs')['run']).to include('deploy/prod_guard.sh deploy')
      expect(tag_check.fetch('env')).to include('TAG' => '${{ steps.inputs.outputs.tag }}')
      expect(tag_check.fetch('run')).to include('deploy/release_tag_check.sh "${TAG}"', 'GITHUB_OUTPUT')
      expect(step(guard, 'Check the ref and the inputs').fetch('env')).to include(
        'MIRROR' => "${{ vars.MIRROR == 'true' }}", 'SOURCE_SHA' => '${{ inputs.source_sha }}'
      )
      expect(tag_check).not_to have_key('if')
      expect(guard.fetch('outputs')).to include(
        'tag' => '${{ steps.inputs.outputs.tag }}',
        'version' => '${{ steps.mirror.outputs.version || steps.tag.outputs.version }}',
        'source_sha' => '${{ steps.inputs.outputs.source_sha }}'
      )
    end

    it 'checks MIRROR_SOURCE.json with deploy/mirror_source_check.sh only in mirror mode' do
      guard = jobs.fetch('guard')
      names = guard.fetch('steps').map { |s| s['name'] }
      mirror = step(guard, 'Check the version and source_sha against MIRROR_SOURCE.json')

      expect(mirror.fetch('id')).to eq('mirror')
      expect(names.index(mirror['name'])).to be > names.index('Check that the version is an annotated release tag on main')
      expect(mirror.fetch('env')).to include('TAG' => '${{ steps.inputs.outputs.tag }}',
                                             'SOURCE_SHA' => '${{ steps.inputs.outputs.source_sha }}')
      expect(mirror.fetch('run')).to include('deploy/mirror_source_check.sh "${TAG}" "${SOURCE_SHA}"', 'GITHUB_OUTPUT')
      expect(GithubExpression.evaluate(mirror.fetch('if'), 'vars' => { 'MIRROR' => 'true' })).to be(true)
      [ {}, { 'MIRROR' => 'false' } ].each do |vars|
        expect(GithubExpression.evaluate(mirror.fetch('if'), 'vars' => vars)).to be(false), vars.inspect
      end
    end

    it 'deploys the tag, and on the mirror its source_sha, with deploy/deploy.sh to the chosen destination' do
      deploy = jobs.fetch('deploy')
      checkout = deploy.fetch('steps').find { |s| s['uses'].to_s.start_with?('actions/checkout@') }

      expect(checkout.fetch('with')).to include('fetch-depth' => 0)
      expect(deploy.fetch('env')).to include('TAG' => '${{ needs.guard.outputs.tag }}',
                                             'SOURCE_SHA' => '${{ needs.guard.outputs.source_sha }}')
      expect(step(deploy, 'Deploy').fetch('run')).to eq('deploy/deploy.sh "${DESTINATION}" "${TAG}" ${SOURCE_SHA:+"${SOURCE_SHA}"}')
    end

    it 'never builds an image: prod only promotes what Dev Deploy built' do
      jobs.each_value do |job|
        job.fetch('steps') { [] }.each do |s|
          expect(s['uses'].to_s).not_to match(%r{docker/(build-push|setup-buildx)-action}), s['name']
          expect(s['run'].to_s).not_to match(/docker (buildx )?build|kamal build/), s['name']
        end
      end
    end

    it 'names the mode in the guard job and in the report' do
      name = jobs.fetch('guard').fetch('name')
      expect(GithubExpression.interpolate(name, 'vars' => { 'MIRROR' => 'true' })).to start_with('Guard, mirror mode')
      [ {}, { 'MIRROR' => 'false' } ].each do |vars|
        expect(GithubExpression.interpolate(name, 'vars' => vars)).to eq('Guard, primary mode (ref, confirm, version)'), vars.inspect
      end
      summarize = step(jobs.fetch('report'), 'Summarize the job results')
      expect(summarize.fetch('env')).to include('MODE' => "${{ vars.MIRROR == 'true' && 'mirror' || 'primary' }}")
      expect(summarize.fetch('run')).to include('MIRROR_SOURCE.json', '${MODE}')
    end

    describe 'release-watch' do
      let(:watch) { jobs.fetch('release-watch') }
      let(:watch_steps) { watch.fetch('steps') }

      def index(name)
        watch_steps.index { |s| s['name'] == name } || raise("no step #{name}")
      end

      it 'runs after a successful deploy, in the prod environment' do
        expect(needs(watch)).to include('deploy')
        expect(watch.fetch('timeout-minutes')).to be_between(11, 30)
      end

      # The public URL of an AWS host that is not the live prod answers from the srv host.
      it 'skips only an aws deploy while srv is the live prod, as the deploy job read it' do
        runs = lambda do |destination, active|
          GithubExpression.evaluate(watch.fetch('if'), 'needs' => { 'guard' => { 'outputs' => { 'destination' => destination } },
                                                                    'deploy' => { 'outputs' => { 'active_target' => active } } })
        end
        expect(runs.call('prod', 'aws')).to be(true)
        expect(runs.call('prod', 'srv')).to be(false)
        expect(runs.call('prod-srv', 'aws')).to be(true)
        expect(runs.call('prod-srv', 'srv')).to be(true)
      end

      def runs?(name, destination)
        condition = step(watch, name)['if']
        condition.nil? || GithubExpression.evaluate(condition, 'needs' => { 'guard' => { 'outputs' => { 'destination' => destination } } })
      end

      it 'watches /health before taking the VPN, and always releases it' do
        uses = watch_steps.map { |s| s['uses'].to_s }
        up = index('VPN up')
        down = uses.index { |u| u == './infra-helpers/.github/actions/vpn-down' }

        expect(step(watch, 'Watch /health').fetch('run')).to include('deploy/release_watch.sh health')
        expect(index('Watch /health')).to be < up
        expect(up).to be < index('Count new GlitchTip issues')
        expect(index('Count new GlitchTip issues')).to be < down
        expect(watch_steps[down]['if']).to eq('always()')
      end

      it 'on AWS takes the VPN only after the watch, on srv before it: the srv host is reachable only over the VPN' do
        srv_up = 'VPN up before the srv watch'
        expect(step(watch, srv_up)['uses']).to eq('./infra-helpers/.github/actions/vpn-up')
        expect(index(srv_up)).to be < index('Watch /health')
        expect(index('Watch /health')).to be < index('VPN up')

        expect([ runs?(srv_up, 'prod'), runs?('VPN up', 'prod') ]).to eq([ false, true ])
        expect([ runs?(srv_up, 'prod-srv'), runs?('VPN up', 'prod-srv') ]).to eq([ true, false ])
        expect(runs?('Count new GlitchTip issues', 'prod-srv')).to be(true)
      end

      it 'watches and judges the chosen destination' do
        expect(step(watch, 'Watch /health').fetch('env')).to include(
          'WATCH_DESTINATION' => '${{ needs.guard.outputs.destination }}', 'PROD_SRV_VPN_IP' => '${{ secrets.PROD_SRV_VPN_IP }}'
        )
        expect(step(watch, 'Verdict').fetch('env')).to include('WATCH_DESTINATION' => '${{ needs.guard.outputs.destination }}')
      end

      it "leaves the watch length to deploy/release_watch.sh, whose srv default fits the shared VPN lock's wait" do
        envs = [ watch['env'], step(watch, 'Watch /health')['env'], step(watch, 'Verdict')['env'] ].compact
        envs.each { |env| expect(env.keys).not_to include('WATCH_SECONDS', 'WATCH_INTERVAL') }
      end

      it 'reads GlitchTip with the token and the DSN from the prod secrets' do
        glitchtip = step(watch, 'Count new GlitchTip issues')
        expect(glitchtip.fetch('env')).to include('GLITCHTIP_API_TOKEN' => '${{ secrets.GLITCHTIP_API_TOKEN }}',
                                                  'SENTRY_DSN' => '${{ secrets.SENTRY_DSN }}')
        expect(glitchtip.fetch('run')).to include('deploy/glitchtip_issues.sh')
        expect(glitchtip['continue-on-error']).to be(true)
      end

      it 'always reports ✅ or ❌ to the prod alerts topic' do
        verdict = step(watch, 'Verdict')
        telegram = watch_steps.find { |s| s['uses'].to_s == './infra-helpers/.github/actions/notify-telegram' }

        expect(verdict.fetch('run')).to include('deploy/release_watch.sh verdict')
        expect(verdict['if']).to eq('always()')
        expect(telegram['if']).to eq('always()')
        expect(telegram.dig('with', 'topic')).to eq('PILOT_PROD_ALERTS')
      end

      it 'never rolls back' do
        watch_steps.each { |s| expect(s['run'].to_s).not_to include('rollback'), s['name'] }
      end
    end
  end

  describe '.github/workflows/kamal-manage.yml' do
    it_behaves_like 'a guarded prod workflow', 'kamal-manage.yml', 'manage', 'Run the action', nil

    let(:workflow) { load_workflow('kamal-manage.yml') }
    let(:jobs) { workflow.fetch('jobs') }

    it 'offers status, logs, restart, rollback and remove' do
      expect(workflow.dig('on', 'workflow_dispatch', 'inputs', 'action', 'options')).to eq(%w[status logs restart rollback remove])
    end

    it 'names each run after its action, so rollbacks can be counted' do
      expect(workflow.fetch('run-name')).to include('${{ inputs.action }}')
    end

    it 'rolls back and manages the chosen destination' do
      run = step(jobs.fetch('manage'), 'Run the action').fetch('run')
      expect(run).to include('deploy/rollback.sh "${DESTINATION}" "${VERSION}"', 'deploy/manage.sh "${ACTION}" "${DESTINATION}"')
      expect(workflow.dig('on', 'workflow_dispatch', 'inputs').keys).to eq(%w[action target version confirm])
    end

    it 'hands the typed confirm to deploy/rollback.sh' do
      expect(step(jobs.fetch('manage'), 'Run the action').dig('env', 'CONFIRM')).to eq('${{ inputs.confirm }}')
    end

    it 'puts remove behind a backup gate that fails until it exists' do
      gate = jobs.fetch('backup-gate')
      expect(gate['if']).to include("'remove'")
      expect(gate.fetch('steps').last['run']).to match(/exit 1\s*\z/)
    end

    it 'runs manage only after the backup gate and hands its result to deploy/manage.sh' do
      manage = jobs.fetch('manage')
      expect(needs(manage)).to include('backup-gate')
      expect(manage['if']).to include("needs.backup-gate.result == 'success' || needs.backup-gate.result == 'skipped'")
      expect(step(manage, 'Run the action').dig('env', 'BACKUP_GATE')).to eq('${{ needs.backup-gate.outputs.passed }}')
    end
  end

  describe '.github/workflows/prod-switch.yml' do
    let(:file) { 'prod-switch.yml' }
    let(:workflow) { load_workflow(file) }
    let(:jobs) { workflow.fetch('jobs') }
    let(:text) { Rails.root.join('.github/workflows', file).read }

    def uses?(step, action)
      step['uses'].to_s == "./infra-helpers/.github/actions/#{action}"
    end

    # if: ${{ <expression> }} without the always() or !cancelled() GithubExpression does not know.
    def condition(expression, context)
      GithubExpression.evaluate(expression.delete_prefix('${{').delete_suffix('}}').sub(/\A\s*(always\(\)|!cancelled\(\)) && /, ''), context)
    end

    def script_step(job, run)
      jobs.fetch(job).fetch('steps').find { |s| s['run'].to_s.start_with?("deploy/prod_switch.sh #{run}") } || raise("no #{run} in #{job}")
    end

    it 'takes exactly to (srv or aws, no default), version, an optional source_sha, confirm and dry_run (default true)' do
      inputs = workflow.dig('on', 'workflow_dispatch', 'inputs')
      expect(inputs.keys).to eq(%w[to version source_sha confirm dry_run])
      expect(inputs.fetch('to')).to include('type' => 'choice', 'options' => %w[srv aws], 'required' => true)
      expect(inputs.fetch('to')).not_to have_key('default')
      expect(inputs.fetch('source_sha')).to include('type' => 'string', 'required' => false)
      expect(inputs.fetch('dry_run')).to include('type' => 'boolean', 'default' => true)
    end

    it 'holds kamal-prod for the whole run and never cancels a running switch' do
      expect(workflow.fetch('concurrency')).to eq('group' => 'kamal-prod', 'cancel-in-progress' => false)
      jobs.each { |name, job| expect(job).not_to have_key('concurrency'), name }
    end

    it 'runs the guard first, outside any environment, and makes every other job wait for it' do
      expect(jobs.fetch('guard')).not_to have_key('needs')
      expect(jobs.fetch('guard')).not_to have_key('environment')
      (jobs.keys - %w[guard]).each { |name| expect(transitive_needs(jobs, name)).to include('guard'), name }
      %w[preflight prepare target data abort finalize notify].each { |name| expect(jobs.fetch(name)['environment']).to eq('prod'), name }
    end

    it 'checks main, confirm=prod and the release with the Kamal Deploy guards, then the live host and the direction' do
      guard = jobs.fetch('guard')
      names = guard.fetch('steps').map { |s| s['name'] }
      inputs = step(guard, 'Check the ref and the inputs')
      expect(inputs.fetch('run')).to eq('deploy/prod_guard.sh deploy >> "${GITHUB_OUTPUT}"')
      expect(inputs.fetch('env')).to include('REF' => '${{ github.ref }}', 'ENVIRONMENT' => 'prod', 'CONFIRM' => '${{ inputs.confirm }}',
                                             'VERSION' => '${{ inputs.version }}', 'TARGET' => '${{ inputs.to }}')
      expect(step(guard, 'Check that the version is an annotated release tag on main').fetch('run')).to include('deploy/release_tag_check.sh')
      expect(step(guard, 'Check the version and source_sha against MIRROR_SOURCE.json').fetch('if')).to eq("vars.MIRROR == 'true'")
      expect(step(guard, 'Find the live prod host (public DNS)').fetch('run')).to eq('deploy/prod_active_target.sh >> "${GITHUB_OUTPUT}"')
      switch = step(guard, 'Check the direction of the switch')
      expect(switch.fetch('run')).to eq('deploy/prod_switch.sh guard >> "${GITHUB_OUTPUT}"')
      expect(switch.fetch('env')).to eq('TO' => '${{ inputs.to }}', 'ACTIVE_TARGET' => '${{ steps.active.outputs.active_target }}')
      expect(names.last(2)).to eq([ 'Find the live prod host (public DNS)', 'Check the direction of the switch' ])
      expect(guard.fetch('outputs').keys).to include('tag', 'version', 'source_sha', 'to', 'from', 'to_destination', 'from_destination')
    end

    it 'requires the secrets of both hosts and of the app before anything starts' do
      preflight = step(jobs.fetch('preflight'), 'Check that every required secret is set')
      all_set = preflight.fetch('env').keys.index_with { 'x' }.merge('GITHUB_WORKFLOW' => 'Prod Switch')
      output, status = Open3.capture2e(all_set, 'bash', '-e', '-c', preflight.fetch('run'), chdir: Rails.root)
      expect(status).to be_success, output
      (%w[PROD_SSH_KEY PROD_VPN_IP PROD_SRV_SSH_KEY PROD_SRV_VPN_IP] + kamal_secrets).each do |name|
        output, status = Open3.capture2e(all_set.merge(name => ''), 'bash', '-e', '-c', preflight.fetch('run'), chdir: Rails.root)
        expect(status).not_to be_success, name
        expect(output).to include("missing secrets: #{name} ("), name
      end
    end

    it 'maps every secret .kamal/secrets.prod reads and both host addresses into each job that runs Kamal' do
      %w[prepare target data abort finalize].each do |name|
        env = jobs.fetch(name).fetch('env')
        (kamal_secrets + %w[PROD_VPN_IP PROD_SRV_VPN_IP]).each { |secret| expect(env[secret]).to eq("${{ secrets.#{secret} }}"), "#{name} #{secret}" }
        expect(env).to include('DRY_RUN' => "${{ inputs.dry_run && '1' || '' }}")
      end
    end

    it 'prepares the target, freezes the live prod and moves the data in order, and aborts on a failure after the freeze' do
      data = jobs.fetch('data')
      runs = data.fetch('steps').map { |s| s['run'].to_s }
      order = [ 'prod_switch.sh prepare "${TO_DESTINATION}" "${TAG}" ${SOURCE_SHA:+"${SOURCE_SHA}"}',
                'prod_switch.sh freeze "${FROM_DESTINATION}"',
                'prod_switch.sh move-data "${FROM_DESTINATION}" "${TO_DESTINATION}" "${VERSION}"',
                'prod_switch.sh abort "${FROM_DESTINATION}" "${VERSION}"' ].map { |run| runs.index("deploy/#{run}") }
      expect(order).to all(be_a(Integer))
      expect(order).to eq(order.sort)
      expect(needs(data)).to include('preflight', 'target')
      expect(data.fetch('steps').find { |s| s['run'].to_s.start_with?('deploy/prod_switch.sh') })
        .to include('name' => 'Check that the target runs the release', 'env' => { 'REQUIRE_READY' => '1' })
      expect(data.fetch('if')).to start_with('${{ !cancelled() && ')
      { 'success' => true, 'skipped' => false, 'failure' => false }.each do |result, runs|
        expect(condition(data.fetch('if'), 'needs' => { 'target' => { 'result' => result } })).to be(runs), result
      end
      expect(data.fetch('env')).to include('PROD_ACTIVE_TARGET' => '${{ needs.guard.outputs.from }}')
      abort_if = step(data, 'Abort, bring the live prod back').fetch('if')
      expect(abort_if).to include('failure() || cancelled()', "steps.freeze.outcome != 'skipped'")
      expect(step(data, 'Freeze the live prod').fetch('id')).to eq('freeze')
    end

    it 'cannot fail the data job after its abort step, so a moved database never leaves prod frozen unreported' do
      data = jobs.fetch('data')
      steps = data.fetch('steps')
      after_abort = steps.drop(steps.index { |s| s['name'] == 'Abort, bring the live prod back' } + 1)
      expect(after_abort.map { |s| s['name'] }).to eq([ 'VPN down', 'Ask for the prod-dns approval (Telegram)' ])
      after_abort.each { |s| expect(s['continue-on-error']).to be(true), s['name'] }
      expect(step(data, 'Abort, bring the live prod back').fetch('id')).to eq('abort')
      expect(data.fetch('outputs')).to eq('freeze' => '${{ steps.freeze.outcome }}', 'abort' => '${{ steps.abort.outcome }}')
    end

    it 'switches DNS only in the prod-dns job, behind the prod-dns environment, after the data is verified' do
      dns = jobs.fetch('prod-dns')
      expect(dns.fetch('environment')).to eq('prod-dns')
      expect(needs(dns)).to include('data')
      expect(dns.fetch('if')).to start_with('${{ !cancelled() && ')
      { 'success' => true, 'skipped' => false, 'failure' => false }.each do |result, runs|
        expect(condition(dns.fetch('if'), 'needs' => { 'data' => { 'result' => result } })).to be(runs), result
      end
      expect(dns.fetch('outputs')).to eq('touched' => '${{ steps.touched.outputs.touched }}')
      expect(dns.fetch('steps').first).to include('id' => 'touched', 'run' => 'echo "touched=true" >> "${GITHUB_OUTPUT}"')
      switch = step(dns, 'Switch DNS through the infra prod stack')
      expect(switch.fetch('run')).to eq('deploy/prod_switch.sh dns "${TO}"')
      expect(switch.fetch('env')).to include('GH_TOKEN' => '${{ secrets.INFRA_PROD_DISPATCH_TOKEN }}')
      readers = jobs.select { |_, job| job.to_yaml.include?('secrets.INFRA_PROD_DISPATCH_TOKEN') }
      expect(readers.keys).to contain_exactly('standby', 'prod-dns')
      readers.each_value { |job| expect(job.fetch('environment')).to eq('prod-dns') }
      expect(dns.fetch('steps').none? { |s| uses?(s, 'vpn-up') }).to be(true)
    end

    it 'aborts only before DNS: after the data moved, when prod-dns did not succeed and never started' do
      abort_if = jobs.fetch('abort').fetch('if')
      expect(abort_if).to start_with('${{ always() && ')
      runs = lambda do |data, dns, touched|
        condition(abort_if, 'needs' => { 'data' => { 'result' => data }, 'prod-dns' => { 'result' => dns, 'outputs' => { 'touched' => touched } } })
      end
      expect(runs.call('success', 'failure', '')).to be(true)
      expect(runs.call('success', 'cancelled', '')).to be(true)
      expect(runs.call('success', 'failure', 'true')).to be(false)
      expect(runs.call('success', 'success', 'true')).to be(false)
      expect(runs.call('failure', 'skipped', '')).to be(false)
      expect(step(jobs.fetch('abort'), 'Bring the live prod back').fetch('run')).to eq('deploy/prod_switch.sh abort "${FROM_DESTINATION}" "${VERSION}"')
    end

    # A cancelled prod-dns job may never set touched, so the abort checks the facts first: public DNS and
    # whether that job ever began.
    it 'checks that DNS was never touched before it reaches the live prod in the abort' do
      abort = jobs.fetch('abort')
      steps = abort.fetch('steps')
      check = steps.index { |s| s['run'] }
      expect(steps[check]).to include('name' => 'Check that DNS was never touched', 'run' => 'deploy/prod_switch.sh abort-check "${FROM_DESTINATION}"')
      expect(steps[check].fetch('env')).to eq('GH_TOKEN' => '${{ github.token }}')
      expect(check).to be < steps.index { |s| uses?(s, 'vpn-up') }
      expect(abort.fetch('permissions')).to include('actions' => 'read')
      expect(jobs.fetch('prod-dns').fetch('name')).to eq(Rails.root.join('deploy/prod_switch.sh').read[/^DNS_JOB_NAME='(.*)'$/, 1])
    end

    it 'checks the target in prepare over the VPN and asks for the standby approval when the AWS instance is down' do
      prepare = jobs.fetch('prepare')
      expect(needs(prepare)).to contain_exactly('guard', 'preflight')
      probe = script_step('prepare', 'prepare')
      expect(probe.fetch('run')).to eq('deploy/prod_switch.sh prepare "${TO_DESTINATION}" "${TAG}" ${SOURCE_SHA:+"${SOURCE_SHA}"}')
      expect(probe.fetch('id')).to eq('steps')
      expect(prepare.fetch('outputs')).to eq('steps' => '${{ steps.steps.outputs.steps }}')
      steps = prepare.fetch('steps')
      expect(steps.index { |s| uses?(s, 'vpn-up') }).to be < steps.index(probe)
      expect(steps.index { |s| uses?(s, 'vpn-down') }).to be > steps.index(probe)
      ask = steps.find { |s| uses?(s, 'notify-telegram') }
      expect(ask['continue-on-error']).to be(true)
      expect(ask.fetch('with').fetch('message')).to include('Approve prod-dns')
      expect(condition(ask.fetch('if'), 'steps' => { 'steps' => { 'outputs' => { 'steps' => 'standby' } } })).to be(true)
      expect(condition(ask.fetch('if'), 'steps' => { 'steps' => { 'outputs' => { 'steps' => 'live deploy' } } })).to be(false)
    end

    it 'starts the AWS standby only behind the prod-dns approval, and only when prepare asked for it' do
      standby = jobs.fetch('standby')
      expect(standby.fetch('environment')).to eq('prod-dns')
      expect(needs(standby)).to contain_exactly('guard', 'prepare')
      %w[standby live deploy].zip([ true, false, false ]).each do |steps, runs|
        expect(condition(standby.fetch('if'), 'needs' => { 'prepare' => { 'outputs' => { 'steps' => steps } } })).to be(runs), steps
      end
      run = script_step('standby', 'standby')
      expect(run.fetch('id')).to eq('standby')
      expect(run.fetch('env')).to include('GH_TOKEN' => '${{ secrets.INFRA_PROD_DISPATCH_TOKEN }}', 'DRY_RUN' => "${{ inputs.dry_run && '1' || '' }}",
                                          'INFRA_PROD_REPO' => step(jobs.fetch('prod-dns'), 'Switch DNS through the infra prod stack').dig('env', 'INFRA_PROD_REPO'))
      expect(standby.fetch('outputs')).to eq('dispatched' => '${{ steps.standby.outputs.dispatched }}')
      expect(standby.fetch('steps').none? { |s| uses?(s, 'vpn-up') }).to be(true)
    end

    it 'runs the target job after prepare, and after the standby only when it succeeded or was skipped' do
      target = jobs.fetch('target')
      expect(needs(target)).to contain_exactly('guard', 'prepare', 'standby')
      expect(target.fetch('if')).to start_with('${{ !cancelled() && ')
      expect(target.fetch('permissions')).to eq('actions' => 'write', 'contents' => 'read', 'id-token' => 'write')
      runs = ->(prepare, standby) { condition(target.fetch('if'), 'needs' => { 'prepare' => { 'result' => prepare }, 'standby' => { 'result' => standby } }) }
      expect(runs.call('success', 'skipped')).to be(true)
      expect(runs.call('success', 'success')).to be(true)
      expect(runs.call('success', 'failure')).to be(false)
      expect(runs.call('failure', 'skipped')).to be(false)
    end

    # standby is skipped on every switch that needs no AWS standby, and GitHub's implicit success() skips every job
    # downstream of a skipped job unless its if: uses a status function.
    it 'gives every job downstream of the standby an if: with !cancelled() or always(), so a skipped standby skips nothing' do
      downstream = jobs.keys.select { |name| transitive_needs(jobs, name).include?('standby') }
      expect(downstream).to include('target', 'data', 'prod-dns', 'abort', 'finalize')
      downstream.each do |name|
        expect(jobs.fetch(name)['if'].to_s).to match(/\A(\$\{\{\s*)?(!cancelled\(\)|always\(\))/), name
      end
    end

    it 'waits for the AWS instance after a standby, re-probes it, and dispatches Kamal Deploy only outside the VPN' do
      steps = jobs.fetch('target').fetch('steps')
      wait = script_step('target', 'wait-host')
      reprobe = steps.find { |s| s['id'] == 'reprobe' }
      deploy = script_step('target', 'deploy-target')
      expect(wait.fetch('run')).to eq('deploy/prod_switch.sh wait-host prod "${STANDBY_WAIT_MINUTES:-20}"')
      expect(reprobe.fetch('run')).to eq('deploy/prod_switch.sh prepare "${TO_DESTINATION}" "${TAG}" ${SOURCE_SHA:+"${SOURCE_SHA}"}')
      expect(reprobe.fetch('env')).to eq('AFTER_STANDBY' => '1')
      expect(deploy.fetch('run')).to eq('deploy/prod_switch.sh deploy-target "${TO}" "${TAG}" ${SOURCE_SHA:+"${SOURCE_SHA}"}')
      expect(deploy.fetch('env')).to eq('GH_TOKEN' => '${{ github.token }}')
      up = steps.index { |s| uses?(s, 'vpn-up') }
      down = steps.index { |s| uses?(s, 'vpn-down') }
      expect([ up, steps.index(wait), steps.index(reprobe), down, steps.index(deploy) ]).to eq([ up, steps.index(wait), steps.index(reprobe), down, steps.index(deploy) ].sort)
      expect(steps.drop(steps.index(deploy)).none? { |s| uses?(s, 'vpn-up') }).to be(true)

      after_standby = { 'needs' => { 'prepare' => { 'outputs' => { 'steps' => 'standby' } } }, 'inputs' => { 'dry_run' => false } }
      [ wait, reprobe ].each do |s|
        expect(condition(s.fetch('if'), after_standby)).to be(true)
        expect(condition(s.fetch('if'), 'needs' => { 'prepare' => { 'outputs' => { 'steps' => 'live deploy' } } })).to be(false)
      end
      expect(condition(steps[up].fetch('if'), after_standby)).to be(true)
      expect(condition(steps[up].fetch('if'), after_standby.merge('inputs' => { 'dry_run' => true }))).to be(false)
      expect(condition(steps[up].fetch('if'), 'needs' => { 'prepare' => { 'outputs' => { 'steps' => 'deploy' } } }, 'inputs' => { 'dry_run' => false })).to be(false)

      deploys = lambda do |prepared, reprobed|
        condition(deploy.fetch('if'), 'needs' => { 'prepare' => { 'outputs' => { 'steps' => prepared } } },
                                      'steps' => { 'reprobe' => { 'outputs' => { 'steps' => reprobed } } })
      end
      expect(deploys.call('deploy', '')).to be(true)
      expect(deploys.call('live deploy', '')).to be(true)
      expect(deploys.call('live', '')).to be(false)
      expect(deploys.call('', '')).to be(false)
      expect(deploys.call('standby', 'live deploy')).to be(true)
      expect(deploys.call('standby', 'live')).to be(false)
      expect(deploys.call('standby', '')).to be(false)
    end

    it 'checks the public URLs before vpn-up, then stops the old host over the VPN' do
      finalize = jobs.fetch('finalize')
      steps = finalize.fetch('steps')
      public_checks = steps.index { |s| s['run'] == 'deploy/prod_switch.sh finalize-public "${TO_DESTINATION}" "${VERSION}"' }
      stop = steps.index { |s| s['run'] == 'deploy/prod_switch.sh stop-old "${FROM_DESTINATION}"' }
      up = steps.index { |s| uses?(s, 'vpn-up') }
      expect([ public_checks, up, stop ]).to all(be_a(Integer))
      expect(public_checks).to be < up
      expect(up).to be < stop
      expect(needs(finalize)).to include('prod-dns')
      expect(finalize.fetch('if')).to start_with('${{ !cancelled() && ')
      { 'success' => true, 'skipped' => false, 'failure' => false, 'cancelled' => false }.each do |result, runs|
        expect(condition(finalize.fetch('if'), 'needs' => { 'prod-dns' => { 'result' => result } })).to be(runs), result
      end
      expect(finalize.fetch('env')).to include('PROD_ACTIVE_TARGET' => '${{ needs.guard.outputs.to }}')
    end

    it 'passes the mirror VPN client inputs to every vpn-up and always disconnects after it, outside a dry run' do
      jobs.each do |name, job|
        steps = job.fetch('steps') { [] }
        up = steps.index { |s| uses?(s, 'vpn-up') }
        next unless up

        expect(steps[up].fetch('with').to_a).to eq(vpn_up_inputs), name
        expect(steps[up].fetch('if')).to start_with('${{ !inputs.dry_run'), name
        expect(condition(steps[up].fetch('if'), 'inputs' => { 'dry_run' => true })).to be(false), name
        down = steps.index { |s| uses?(s, 'vpn-down') }
        expect(down).to be > up
        expect(steps[down].fetch('if')).to eq(steps[up].fetch('if').sub('${{ ', '${{ always() && ')), name
      end
      expect(jobs.keys.select { |name| jobs.fetch(name).fetch('steps').any? { |s| uses?(s, 'vpn-up') } })
        .to contain_exactly('prepare', 'target', 'data', 'abort', 'finalize')
    end

    it 'touches no host, ECR or AWS in a dry run' do
      jobs.each_value do |job|
        job.fetch('steps').each do |s|
          next unless s['name'].to_s.match?(/crane|SSH keys/) || s['uses'].to_s.start_with?('aws-actions/')

          expect(s.fetch('if')).to start_with('${{ !inputs.dry_run'), s['name'] || s['uses']
          expect(condition(s.fetch('if'), 'inputs' => { 'dry_run' => true })).to be(false), s['name'] || s['uses']
        end
      end
    end

    it 'runs Kamal only through the deploy scripts and never uploads the dump' do
      expect(text).not_to match(/\bkamal /)
      expect(text).not_to include('upload-artifact')
    end

    it 'reports a failed data job as brought back only when its abort step succeeded' do
      summarize = step(jobs.fetch('report'), 'Summarize the job results')
      expect(summarize.fetch('env')).to include('FREEZE' => '${{ needs.data.outputs.freeze }}', 'DATA_ABORT' => '${{ needs.data.outputs.abort }}')
      report = lambda do |freeze, abort|
        Dir.mktmpdir do |dir|
          env = summarize.fetch('env').keys.index_with { '' }.merge(
            'GUARD' => 'success', 'PREFLIGHT' => 'success', 'DATA' => 'failure', 'PROD_DNS' => 'skipped', 'ABORT' => 'skipped',
            'FINALIZE' => 'skipped', 'FROM' => 'aws', 'TO' => 'srv', 'FREEZE' => freeze, 'DATA_ABORT' => abort,
            'GITHUB_STEP_SUMMARY' => "#{dir}/summary", 'GITHUB_OUTPUT' => "#{dir}/output", 'GITHUB_ENV' => "#{dir}/env"
          )
          _, status = Open3.capture2e(env, 'bash', '-e', '-c', summarize.fetch('run'), chdir: Rails.root)
          expect(status).to be_success
          File.read("#{dir}/output")
        end
      end
      expect(report.call('skipped', 'skipped')).to include('failed in data:', 'nothing touched prod')
      expect(report.call('success', 'success')).to include('the abort step brought aws back')
      [ %w[success failure], %w[failure skipped], %w[success cancelled], [ '', '' ] ].each do |freeze, abort|
        message = report.call(freeze, abort)
        expect(message).to include('the abort did not succeed: prod on aws may still be in maintenance'), [ freeze, abort ].inspect
        expect(message).not_to include('brought aws back')
      end
    end

    it 'reports a failure before the freeze as nothing touched, and a failed abort as possibly moved DNS' do
      summarize = step(jobs.fetch('report'), 'Summarize the job results')
      expect(summarize.fetch('env')).to include('PREPARE' => '${{ needs.prepare.result }}', 'STANDBY' => '${{ needs.standby.result }}',
                                                'TARGET' => '${{ needs.target.result }}')
      report = lambda do |results|
        Dir.mktmpdir do |dir|
          env = summarize.fetch('env').keys.index_with { 'skipped' }.merge(
            'GUARD' => 'success', 'PREFLIGHT' => 'success', 'FROM' => 'srv', 'TO' => 'aws', 'VERSION' => 'v0.1.0', 'DRY' => '', 'RUN_URL' => 'url',
            'GITHUB_STEP_SUMMARY' => "#{dir}/summary", 'GITHUB_OUTPUT' => "#{dir}/output", 'GITHUB_ENV' => "#{dir}/env"
          ).merge(results)
          _, status = Open3.capture2e(env, 'bash', '-e', '-c', summarize.fetch('run'), chdir: Rails.root)
          expect(status).to be_success
          File.read("#{dir}/output")
        end
      end
      expect(report.call('PREPARE' => 'failure')).to include('failed in prepare:', 'nothing touched prod')
      expect(report.call('PREPARE' => 'success', 'STANDBY' => 'failure')).to include('failed in standby:', 'the AWS instance may be running now', 'DNS stayed on srv')
      expect(report.call('PREPARE' => 'success', 'STANDBY' => 'success', 'TARGET' => 'failure')).to include('failed in target:', 'nothing touched prod')
      aborted = report.call('PREPARE' => 'success', 'TARGET' => 'success', 'DATA' => 'success', 'PROD_DNS' => 'cancelled', 'ABORT' => 'failure')
      expect(aborted).to include('failed in abort:', 'DNS may have moved', 'prod stays in maintenance')
    end

    it 'reports every job and always notifies the prod alerts topic' do
      summarize = step(jobs.fetch('report'), 'Summarize the job results')
      expect(jobs.fetch('report').fetch('if')).to eq('always()')
      expect(needs(jobs.fetch('report'))).to contain_exactly('guard', 'preflight', 'prepare', 'standby', 'target', 'data', 'prod-dns', 'abort', 'finalize')
      expect(summarize.fetch('env')).to include('TOUCHED' => '${{ needs.prod-dns.outputs.touched }}')
      expect(summarize.fetch('run')).to include('DNS may have moved')
      telegram = jobs.fetch('notify').fetch('steps').find { |s| uses?(s, 'notify-telegram') }
      expect(telegram.dig('with', 'topic')).to eq('PILOT_PROD_ALERTS')
    end
  end
end
