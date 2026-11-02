require 'rails_helper'
require Rails.root.join('perf/nfr_load').to_s

RSpec.describe NfrLoad do
  describe NfrLoad::Stats do
    describe '.percentile' do
      it 'uses the nearest rank of the sorted values' do
        values = (1..100).to_a.shuffle

        expect(described_class.percentile(values, 50)).to eq(50)
        expect(described_class.percentile(values, 95)).to eq(95)
        expect(described_class.percentile(values, 99)).to eq(99)
      end

      it 'rounds the rank up on small samples' do
        expect(described_class.percentile([ 30, 10, 20 ], 50)).to eq(20)
        expect(described_class.percentile([ 30, 10, 20 ], 95)).to eq(30)
      end

      it 'returns the only value for a single sample' do
        expect([ 50, 95, 99 ].map { |p| described_class.percentile([ 42 ], p) }).to eq([ 42, 42, 42 ])
      end

      it 'returns nil when there are no values' do
        expect(described_class.percentile([], 95)).to be_nil
      end
    end

    describe '.summary' do
      let(:successes) { (1..18).map { |i| { status: 200, client_ms: 300.0 + i, server_ms: i * 10.0 } } }
      let(:samples) do
        successes + [ { status: 500, client_ms: 1.0, server_ms: 1.0 }, { status: nil, error: 'Net::ReadTimeout' } ]
      end

      it 'counts non-2xx statuses and raised errors as errors' do
        summary = described_class.summary(samples)

        expect(summary).to include(count: 20, errors: 2, error_rate: 0.1)
      end

      it 'computes latency percentiles over successful requests only' do
        summary = described_class.summary(samples)

        expect(summary[:server]).to eq(p50: 90.0, p95: 180.0, p99: 180.0)
        expect(summary[:client]).to eq(p50: 309.0, p95: 318.0, p99: 318.0)
      end
    end

    describe '.verdict' do
      def summary(p95:, errors: 0, server: true)
        { count: 100, errors: errors, error_rate: errors / 100.0, server_timed: server,
          server: { p50: 10.0, p95: p95, p99: p95 }, client: { p50: 400.0, p95: 500.0, p99: 600.0 } }
      end

      it 'passes when the server p95 is within the target and nothing failed' do
        expect(described_class.verdict(summary(p95: 300.0), 300)).to eq(result: 'PASS', basis: :server, p95: 300.0)
      end

      it 'fails when the server p95 is above the target' do
        expect(described_class.verdict(summary(p95: 301.0), 300)).to include(result: 'FAIL', basis: :server)
      end

      it 'fails on any error even when the p95 is within the target' do
        expect(described_class.verdict(summary(p95: 100.0, errors: 1), 300)).to include(result: 'FAIL')
      end

      it 'falls back to the client p95 when a successful response had no server timing' do
        expect(described_class.verdict(summary(p95: 100.0, server: false), 300))
          .to eq(result: 'FAIL', basis: :client, p95: 500.0)
      end
    end
  end

  describe '.host_allowed?' do
    it 'allows dev and local hosts' do
      expect(described_class.host_allowed?('https://dev.pilot.up.km.ua')).to be(true)
      expect(described_class.host_allowed?('http://localhost:3000')).to be(true)
      expect(described_class.host_allowed?('http://127.0.0.1:3000')).to be(true)
    end

    it 'refuses any other host' do
      expect(described_class.host_allowed?('https://example.org')).to be(false)
      expect(described_class.host_allowed?('not a url')).to be(false)
    end
  end

  describe NfrLoad::Run do
    let(:base) { 'http://nfr.test' }
    let(:out) { StringIO.new }
    let(:run) { described_class.new(base, requests: 5, rate: 1000.0, concurrency: 2, out: out) }
    let(:ids) { Hash.new(0) }
    let(:lock) { Mutex.new }
    let(:dashboard) do
      projects = Array.new(NfrLoad::PROJECTS) do |p|
        { id: p + 1, tasks: Array.new(NfrLoad::TASKS_PER_PROJECT) { |t| { id: (p * 10) + t + 1 } } }
      end
      JSON.generate(data: projects)
    end

    def next_id(kind)
      lock.synchronize { ids[kind] += 1 }
    end

    def created(kind)
      { status: 201, body: JSON.generate(data: { id: next_id(kind) }) }
    end

    def deletes(pattern)
      WebMock::RequestRegistry.instance.requested_signatures.hash
        .select { |signature, _| signature.method == :delete && signature.uri.path.match?(pattern) }.values.sum
    end

    before do
      stub_request(:get, "#{base}/health").to_return(status: 200, body: '{"release":"abc1234"}')
      stub_request(:post, "#{base}/api/v1/users").to_return(status: 201, body: '{"data":{"access_token":"t0k"}}')
      stub_request(:post, "#{base}/api/v1/projects").to_return { created(:projects) }
      stub_request(:post, %r{\A#{base}/api/v1/projects/\d+/tasks\z}).to_return { created(:tasks) }
      stub_request(:get, "#{base}/api/v1/projects")
        .to_return(status: 200, body: dashboard, headers: { 'X-Runtime' => '0.050' })
      stub_request(:put, %r{/tasks/\d+\z}).to_return(status: 200, body: '{}', headers: { 'X-Runtime' => '0.020' })
      stub_request(:delete, /nfr\.test/).to_return(status: 204)
      stub_request(:post, "#{base}/api/v1/sign_out").to_return(status: 204)
    end

    it 'exits 0 when both scenarios pass and deletes every project and task it created without signing in' do
      expect(run.call).to eq(0)

      expect(deletes(%r{/tasks/})).to eq(500)
      expect(deletes(%r{\A/api/v1/projects/\d+\z})).to eq(50)
      expect(a_request(:post, "#{base}/api/v1/sign_in")).not_to have_been_made
      expect(a_request(:post, %r{/oauth/token})).not_to have_been_made
      expect(a_request(:post, "#{base}/api/v1/sign_out")).to have_been_made.once
    end

    it 'exits 1 when a scenario is above the target and still cleans up' do
      stub_request(:get, "#{base}/api/v1/projects")
        .to_return(status: 200, body: dashboard, headers: { 'X-Runtime' => '0.400' })

      expect(run.call).to eq(1)
      expect(out.string).to include('FAIL')
      expect(deletes(%r{/tasks/})).to eq(500)
    end

    it 'exits 2 and reports the leftovers when the cleanup could not delete everything' do
      stub_request(:delete, %r{/tasks/7\z}).to_return(status: 500)

      expect(run.call).to eq(2)
      expect(out.string).to include('CLEANUP INCOMPLETE')
    end

    it 'exits 2 when seeding fails and deletes every id the server did create' do
      stub_request(:post, %r{\A#{base}/api/v1/projects/3/tasks\z}).to_return(status: 500)

      expect(run.call).to eq(2)
      expect(out.string).to include('ABORT: seeding failed')
      expect(deletes(%r{/tasks/})).to eq(ids[:tasks])
      expect(deletes(%r{\A/api/v1/projects/\d+\z})).to eq(50)
    end

    it 'aborts with exit 2, not a scenario verdict, when the dashboard answers with a body that is not JSON' do
      stub_request(:get, "#{base}/api/v1/projects")
        .to_return(status: 200, body: '<html>Bad gateway</html>', headers: { 'X-Runtime' => '0.010' })

      expect(run.call).to eq(2)
      expect(out.string).to include('ABORT')
      expect(deletes(%r{/tasks/})).to eq(500)
    end

    it 'aborts with exit 2 and still cleans up when a created project answers with a body that is not JSON' do
      stub_request(:post, "#{base}/api/v1/projects").to_return do
        id = next_id(:projects)
        id == 10 ? { status: 201, body: '<html></html>' } : { status: 201, body: JSON.generate(data: { id: id }) }
      end

      expect(run.call).to eq(2)
      expect(out.string).to include('ABORT')
      expect(deletes(%r{\A/api/v1/projects/\d+\z})).to eq(ids[:projects] - 1)
    end

    it 'aborts with exit 2 and still cleans up when the dashboard list does not hold the seeded dataset' do
      thin = JSON.generate(data: JSON.parse(dashboard)['data'].first(NfrLoad::PROJECTS - 1))
      stub_request(:get, "#{base}/api/v1/projects")
        .to_return(status: 200, body: thin, headers: { 'X-Runtime' => '0.010' })

      expect(run.call).to eq(2)
      expect(out.string).to include('ABORT: dashboard list returned 49 projects and 490 tasks')
      expect(deletes(%r{/tasks/})).to eq(500)
      expect(deletes(%r{\A/api/v1/projects/\d+\z})).to eq(50)
    end

    [
      [ 'answers 429', { status: 429, body: '{}' } ],
      [ 'returns no access token', { status: 201, body: '{"data":{}}' } ]
    ].each do |failure, response|
      it "aborts with exit 2 after one sign-up attempt that #{failure}, without signing in or seeding" do
        stub_request(:post, "#{base}/api/v1/users").to_return(response)

        expect(run.call).to eq(2)
        expect(out.string).to include('ABORT: sign-up')
        expect(a_request(:post, "#{base}/api/v1/users")).to have_been_made.once
        expect(a_request(:post, "#{base}/api/v1/sign_in")).not_to have_been_made
        expect(a_request(:post, %r{/oauth/token})).not_to have_been_made
        expect(a_request(:post, "#{base}/api/v1/projects")).not_to have_been_made
      end
    end

    it 'deletes what it created before a Ctrl-C during seeding' do
      # The Ctrl-C reaches the main thread while it waits for the task seeding, its second wait, once the 25th task
      # exists; that create and the ones in flight with it answer only when the main thread has cleared the
      # remaining work and waits for them, so the seeding is interrupted whatever the scheduler does.
      created = Queue.new
      interrupted = false
      waits = 0
      allow(NfrLoad).to receive(:await).and_wrap_original do |original, threads|
        waits += 1
        next original.call(threads) unless waits == 2

        created.pop
        interrupted = true
        raise Interrupt
      end
      stub_request(:post, %r{\A#{base}/api/v1/projects/\d+/tasks\z}).to_return do
        id = next_id(:tasks)
        if id >= 25
          created << id if id == 25
          deadline = NfrLoad.now + 10
          sleep(0.001) until (interrupted && Thread.main.stop?) || NfrLoad.now > deadline
        end
        { status: 201, body: JSON.generate(data: { id: id }) }
      end

      expect { run.call }.to raise_error(Interrupt)
      expect(ids[:tasks]).to be_between(25, 24 + NfrLoad::SEED_CONCURRENCY)
      expect(deletes(%r{/tasks/})).to eq(ids[:tasks])
      expect(deletes(%r{\A/api/v1/projects/\d+\z})).to eq(50)
    end
  end
end
