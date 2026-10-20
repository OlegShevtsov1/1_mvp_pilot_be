require 'rails_helper'

# The public mirror of this repository cannot use actions from the owner's private 1_mvp_infra, and GitHub
# resolves every remote uses: of a job before its first step. So each job that needs vpn-up, vpn-down or
# notify-telegram checks 1_mvp_infra out into infra-helpers/ with INFRA_READ_TOKEN and runs them from there.
RSpec.describe 'shared actions from a checkout of 1_mvp_infra' do
  workflows = Dir.glob('.github/workflows/*.yml', base: Rails.root.to_s).sort
  expected_jobs = {
    'dev-deploy.yml' => %w[probe deploy notify],
    'kamal-deploy.yml' => %w[probe deploy release-watch notify],
    'kamal-manage.yml' => %w[probe manage notify],
    'release.yml' => %w[notify],
    'main-guard.yml' => %w[guard],
    'develop-guard.yml' => %w[guard]
  }
  deploy_workflows = %w[dev-deploy.yml kamal-deploy.yml kamal-manage.yml]
  helper_actions = %w[vpn-up vpn-down notify-telegram].map { |name| "./infra-helpers/.github/actions/#{name}" }
  checkout_with = {
    'repository' => '${{ github.repository_owner }}/1_mvp_infra',
    'ref' => 'env/dev',
    'path' => 'infra-helpers',
    'token' => '${{ secrets.INFRA_READ_TOKEN }}',
    'persist-credentials' => false,
    'sparse-checkout' => ".github/actions\nscripts\nhost\nprojects\n"
  }
  token_check = 'Check that INFRA_READ_TOKEN is set'
  files_check = 'Check that vpn-up, vpn-down and notify-telegram are there'

  def jobs_of(file)
    YAML.load_file(Rails.root.join('.github/workflows', file).to_s).fetch('jobs')
  end

  def steps_of(job)
    job.fetch('steps') { [] }
  end

  def checkout?(step)
    step['uses'].to_s.start_with?('actions/checkout@')
  end

  def find_step(job, name)
    steps_of(job).find { |step| step['name'] == name } || raise("no step #{name}")
  end

  define_method(:infra_checkout?) { |step| checkout?(step) && step.dig('with', 'repository') == checkout_with['repository'] }
  define_method(:helper_step?) { |step| step['uses'].to_s.start_with?('./infra-helpers/') }

  workflows.each do |path|
    file = File.basename(path)

    describe file do
      let(:jobs) { jobs_of(file) }

      it 'uses no action from a remote 1_mvp_infra' do
        jobs.each_value do |job|
          steps_of(job).each do |step|
            expect(step['uses'].to_s).not_to include('1_mvp_infra'), step['name']
            expect(step['uses'].to_s).not_to end_with('@env/dev'), step['name']
          end
        end
      end

      it 'uses the shared actions only from ./infra-helpers' do
        jobs.each_value do |job|
          steps_of(job).select { |step| helper_step?(step) }.each { |step| expect(helper_actions).to include(step['uses']) }
        end
      end

      it 'checks out 1_mvp_infra in exactly the jobs that need it' do
        with_checkout = jobs.select { |_, job| steps_of(job).any? { |step| infra_checkout?(step) } }.keys
        with_helpers = jobs.select { |_, job| steps_of(job).any? { |step| helper_step?(step) } }.keys

        expect(with_checkout).to match_array(expected_jobs.fetch(file) { [] })
        expect(with_helpers - with_checkout).to be_empty
      end
    end
  end

  expected_jobs.each do |file, job_names|
    job_names.each do |job_name|
      describe "#{file} job #{job_name}" do
        let(:steps) { steps_of(jobs_of(file).fetch(job_name)) }
        let(:checkout_index) { steps.index { |step| infra_checkout?(step) } }

        it 'checks out 1_mvp_infra once, pinned and read-only' do
          checkouts = steps.select { |step| infra_checkout?(step) }

          expect(checkouts.size).to eq(1)
          expect(checkouts.first.fetch('uses')).to eq('actions/checkout@v4')
          expect(checkouts.first.fetch('with')).to eq(checkout_with)
          expect(checkouts.first).not_to have_key('if')
        end

        it 'checks out 1_mvp_infra before any step uses it' do
          steps.select { |step| helper_step?(step) }.each do |step|
            expect(steps.index(step)).to be > checkout_index, step['name']
          end
        end

        it "runs the infra checkout first, after only this repository's own checkout" do
          steps.first(checkout_index).each do |step|
            own_checkout = checkout?(step) && !step.fetch('with') { {} }.key?('repository')
            expect(own_checkout || step['name'] == token_check).to be(true), step.inspect
          end
        end

        it 'never checks out this repository after 1_mvp_infra, which would delete infra-helpers' do
          expect(steps.drop(checkout_index + 1).select { |step| checkout?(step) }).to be_empty
        end
      end
    end
  end

  # These jobs exist to deliver a message, and the infra checkout fails exactly when INFRA_READ_TOKEN
  # is broken, which is also what the probes report; so they must still get the message out without it.
  alerting_jobs = {
    'dev-deploy.yml' => 'notify', 'kamal-deploy.yml' => 'notify', 'kamal-manage.yml' => 'notify',
    'release.yml' => 'notify', 'main-guard.yml' => 'guard', 'develop-guard.yml' => 'guard'
  }
  direct_send = 'Send the message without the shared actions'

  alerting_jobs.each do |file, job_name|
    describe "#{file} job #{job_name} when 1_mvp_infra cannot be checked out" do
      let(:job) { jobs_of(file).fetch(job_name) }
      let(:steps) { steps_of(job) }
      let(:checkout) { steps.find { |step| infra_checkout?(step) } }
      let(:shared) { steps.find { |step| step['uses'] == './infra-helpers/.github/actions/notify-telegram' } }
      let(:fallback) { find_step(job, direct_send) }

      it 'goes on past a failed infra checkout' do
        expect(checkout).to include('id' => 'infra', 'continue-on-error' => true)
      end

      it 'sends to the same topic without any action once the shared one could not run' do
        topic = shared.dig('with', 'topic')

        expect(steps.index(fallback)).to be > steps.index(shared)
        expect(fallback['if']).to eq("!cancelled() && steps.infra.outcome == 'failure'")
        expect(fallback).not_to have_key('uses')
        expect(fallback.fetch('run')).not_to include('${{')
        %w[BOT_TOKEN CHAT_ID THREAD_ID].each do |part|
          expect(fallback.dig('env', part)).to eq(shared.dig('env', "TELEGRAM_#{topic}_#{part}")), part
        end
      end

      it 'sends the message the shared action would have sent' do
        if job_name == 'guard'
          expect(fallback.dig('env', 'MESSAGE')).to include('steps.check.outputs.message', 'INFRA_READ_TOKEN')
        else
          expect(fallback.dig('env', 'MESSAGE')).to eq(shared.dig('with', 'message'))
        end
      end

      it 'posts the message to the Telegram Bot API, keeps the token out of argv and fails naming INFRA_READ_TOKEN' do
        Dir.mktmpdir do |dir|
          FileUtils.mkdir_p(File.join(dir, 'bin'))
          write_executable(File.join(dir, 'bin/curl'), <<~SH)
            #!/usr/bin/env bash
            printf '%s\\n' "$@" > "#{dir}/argv"
            cat > "#{dir}/stdin"
          SH
          env = {
            'PATH' => "#{dir}/bin:#{ENV.fetch('PATH')}", 'GITHUB_REPOSITORY_OWNER' => 'owner',
            'BOT_TOKEN' => 'bot-secret', 'CHAT_ID' => 'chat', 'THREAD_ID' => 'thread', 'MESSAGE' => 'hello'
          }

          output, status = Open3.capture2e(env, 'bash', '-e', '-c', fallback.fetch('run'), chdir: dir)
          argv = File.read(File.join(dir, 'argv'))

          expect(status).not_to be_success
          expect(output).to include('INFRA_READ_TOKEN', 'owner/1_mvp_infra')
          expect(argv).to include('chat_id=chat', 'message_thread_id=thread', 'text=hello')
          expect(argv).not_to include('bot-secret')
          expect(File.read(File.join(dir, 'stdin'))).to include('https://api.telegram.org/botbot-secret/sendMessage')
        end
      end
    end
  end

  deploy_workflows.each do |file|
    describe file do
      let(:jobs) { jobs_of(file) }
      let(:preflight) { find_step(jobs.fetch('preflight'), 'Check that every required secret is set') }
      let(:probe) { jobs.fetch('probe') }

      def run_step(step, env, chdir: Rails.root.to_s)
        Open3.capture2e(env, 'bash', '-e', '-c', step.fetch('run'), chdir: chdir)
      end

      it 'the preflight maps INFRA_READ_TOKEN' do
        expect(preflight.fetch('env')).to include('INFRA_READ_TOKEN' => '${{ secrets.INFRA_READ_TOKEN }}')
      end

      it 'the preflight fails naming INFRA_READ_TOKEN when it is missing' do
        all_set = preflight.fetch('env').keys.index_with { 'x' }.merge('GITHUB_WORKFLOW' => 'Test')

        output, status = run_step(preflight, all_set.merge('INFRA_READ_TOKEN' => ''))
        expect(status).not_to be_success
        expect(output).to include('missing secrets: INFRA_READ_TOKEN (')

        output, status = run_step(preflight, all_set)
        expect(status).to be_success, output
      end

      it 'the probe checks the token, then checks out 1_mvp_infra, then looks for the three actions' do
        steps = steps_of(probe)

        expect(probe.fetch('name')).to eq('Probe (shared VPN actions)')
        expect(steps.size).to eq(3)
        expect(steps[0]['name']).to eq(token_check)
        expect(infra_checkout?(steps[1])).to be(true)
        expect(steps[2]['name']).to eq(files_check)
      end

      it 'the probe fails naming INFRA_READ_TOKEN when it is not set' do
        step = find_step(probe, token_check)

        output, status = run_step(step, { 'INFRA_READ_TOKEN' => '', 'GITHUB_REPOSITORY_OWNER' => 'owner' })
        expect(status).not_to be_success
        expect(output).to include('INFRA_READ_TOKEN is not set', 'owner/1_mvp_infra')

        output, status = run_step(step, { 'INFRA_READ_TOKEN' => 'x', 'GITHUB_REPOSITORY_OWNER' => 'owner' })
        expect(status).to be_success, output
      end

      it 'the probe fails naming a shared action the checkout lacks' do
        step = find_step(probe, files_check)

        Dir.mktmpdir do |dir|
          add_action = lambda do |name|
            FileUtils.mkdir_p(File.join(dir, 'infra-helpers/.github/actions', name))
            File.write(File.join(dir, 'infra-helpers/.github/actions', name, 'action.yml'), "name: #{name}\n")
          end
          %w[vpn-up vpn-down].each(&add_action)

          output, status = run_step(step, { 'GITHUB_REPOSITORY_OWNER' => 'owner' }, chdir: dir)
          expect(status).not_to be_success
          expect(output).to include('notify-telegram', 'INFRA_READ_TOKEN')

          add_action.call('notify-telegram')
          output, status = run_step(step, { 'GITHUB_REPOSITORY_OWNER' => 'owner' }, chdir: dir)
          expect(status).to be_success, output
        end
      end

      it 'the report explains a probe failure by INFRA_READ_TOKEN' do
        summary = find_step(jobs.fetch('report'), 'Summarize the job results').fetch('run')

        expect(summary).to include('INFRA_READ_TOKEN')
        expect(summary).not_to include('Actions access')
      end
    end
  end
end
