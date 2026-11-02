#!/usr/bin/env ruby
# Runs the todolist PRD §6 load scenarios against dev and reports p50/p95/p99 and the error rate against the
# 300 ms p95 targets: the dashboard list (GET /api/v1/projects) for a user with 50 projects and 500 tasks, and a
# task status change (PUT /api/v1/projects/:id/tasks/:id).
# Usage: ruby perf/nfr_load.rb BASE_URL   (https://dev.pilot.up.km.ua or a local server; never prod)
# NFR_REQUESTS (default 100), NFR_RATE (requests a second, default 10) and NFR_CONCURRENCY (default 10) shape each
# scenario.
# It signs up one throwaway user (one of the 5 sign-ups an hour per source IP, refused ones included), seeds it through the public API with
# its bearer token only, never signs in, deletes the tasks and projects it created and signs out. The user itself
# stays: the API has no way to delete it. The verdict uses the server timing (X-Runtime), the PRD's measure;
# the client round trip is printed alongside it.
# Exit status: 0 when both scenarios pass, 1 when one fails, 2 when the run is refused or aborted or the cleanup left
# data behind.

require 'json'
require 'net/http'
require 'securerandom'
require 'uri'

module NfrLoad
  ALLOWED_HOSTS = %w[dev.pilot.up.km.ua localhost 127.0.0.1].freeze
  TARGET_MS = 300
  PROJECTS = 50
  TASKS_PER_PROJECT = 10
  SEED_CONCURRENCY = 5
  BASELINE_REQUESTS = 10

  class Abort < StandardError; end

  def self.host_allowed?(base_url)
    ALLOWED_HOSTS.include?(URI.parse(base_url).host)
  rescue URI::InvalidURIError
    false
  end

  def self.now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # Runs the block once for every item on `concurrency` threads, each with its own client; with a `rate` item i
  # starts no earlier than i / rate seconds after the first, whatever the earlier ones are still waiting for.
  # When a worker raises or the run is interrupted, no new item starts and the items in flight finish before the
  # exception reaches the caller, so whatever they created is known to the cleanup.
  def self.parallel(items, concurrency:, client:, rate: nil)
    queue = Queue.new
    items.size.times { |index| queue << [ items[index], index ] }
    queue.close
    results = Array.new(items.size)
    started = now
    threads = Array.new([ concurrency, items.size ].min) do
      Thread.new do
        Thread.current.report_on_exception = false
        worker = client.call
        while (item, index = queue.pop)
          delay = rate && started + index / rate - now
          sleep(delay) if delay&.positive?
          results[index] = yield(worker, item)
        end
      rescue Exception # rubocop:disable Lint/RescueException
        queue.clear
        raise
      ensure
        worker&.finish
      end
    end
    begin
      await(threads)
    rescue Exception # rubocop:disable Lint/RescueException
      queue.clear
      threads.each { |thread| thread.join rescue nil } # rubocop:disable Style/RescueModifier
      raise
    end
    results
  end

  # The main thread waits here while the workers of parallel run, so this is where a Ctrl-C reaches it.
  def self.await(threads)
    threads.each(&:join)
  end

  def self.json(response, what)
    JSON.parse(response[:body])
  rescue JSON::ParserError, TypeError
    raise Abort, "#{what} answered #{response[:status]} with a body that is not JSON"
  end

  module Stats
    module_function

    # Nearest rank: the smallest value with at least pct % of the values at or below it.
    def percentile(values, pct)
      return nil if values.empty?

      sorted = values.sort
      sorted[(pct * sorted.size).fdiv(100).ceil - 1]
    end

    # Errors are non-2xx answers and requests that raised; latencies are taken over the successful requests only.
    def summary(samples)
      ok = samples.select { |sample| sample[:status]&.between?(200, 299) }
      errors = samples.size - ok.size
      server = ok.map { |sample| sample[:server_ms] }
      { count: samples.size, errors: errors, error_rate: samples.empty? ? 0.0 : errors.fdiv(samples.size),
        server_timed: server.none?(&:nil?),
        server: percentiles(server.compact), client: percentiles(ok.map { |sample| sample[:client_ms] }) }
    end

    def verdict(summary, target_ms)
      basis = summary[:server_timed] ? :server : :client
      p95 = summary[basis][:p95]
      pass = summary[:errors].zero? && !p95.nil? && p95 <= target_ms
      { result: pass ? 'PASS' : 'FAIL', basis: basis, p95: p95 }
    end

    def percentiles(values)
      { p50: percentile(values, 50), p95: percentile(values, 95), p99: percentile(values, 99) }
    end
  end

  # One keep-alive connection; not thread-safe, so every thread gets its own.
  class Client
    TIMEOUT = 10

    def initialize(base_url, token = nil)
      @uri = URI.parse(base_url)
      @token = token
    end

    def call(method, path, body = nil)
      started = NfrLoad.now
      response = connection.request(build(method, path, body))
      runtime = response['X-Runtime']
      { status: response.code.to_i, client_ms: elapsed_ms(started), server_ms: runtime && runtime.to_f * 1000,
        body: response.body }
    rescue StandardError => e
      finish
      { status: nil, client_ms: elapsed_ms(started), error: e.class.name }
    end

    def finish
      @connection&.finish if @connection&.started?
      @connection = nil
    end

    private

    def connection
      @connection ||= Net::HTTP.start(@uri.host, @uri.port, use_ssl: @uri.scheme == 'https',
                                      open_timeout: TIMEOUT, read_timeout: TIMEOUT)
    end

    def build(method, path, body)
      request = Net::HTTPGenericRequest.new(method, !body.nil?, true, path,
                                            'Accept' => 'application/json', 'Content-Type' => 'application/json')
      request['Authorization'] = "Bearer #{@token}" if @token
      request.body = JSON.generate(body) if body
      request
    end

    def elapsed_ms(started)
      ((NfrLoad.now - started) * 1000).round(1)
    end
  end

  class Run
    def self.main(argv, env = ENV)
      base_url = argv.first.to_s.chomp('/')
      unless NfrLoad.host_allowed?(base_url)
        warn "usage: ruby perf/nfr_load.rb BASE_URL  (one of #{ALLOWED_HOSTS.join(', ')}; never prod)"
        exit 2
      end

      exit new(base_url, requests: Integer(env.fetch('NFR_REQUESTS') { '100' }),
                         rate: Float(env.fetch('NFR_RATE') { '10' }),
                         concurrency: Integer(env.fetch('NFR_CONCURRENCY') { '10' })).call
    end

    def initialize(base_url, requests:, rate:, concurrency:, out: $stdout)
      @base_url = base_url
      @requests = requests
      @rate = rate
      @concurrency = concurrency
      @out = out
      @projects = []
      @tasks = []
    end

    def call
      status = begin
        measure
      ensure
        cleaned = @token.nil? || clean_up
      end
      cleaned ? status : 2
    end

    private

    def measure
      parameters
      sign_up
      seed
      verdicts = { 'dashboard list' => dashboard_list, 'task status change' => status_change }.map do |name, samples|
        report(name, samples)
      end
      verdicts.all? { |verdict| verdict[:result] == 'PASS' } ? 0 : 1
    rescue Abort => e
      say "ABORT: #{e.message}"
      2
    end

    def say(line = '')
      @out.puts(line)
      @out.flush
    end

    def parameters
      probe = client
      health = probe.call('GET', '/health')
      raise Abort, "GET /health answered #{health[:status] || health[:error]}" unless health[:status] == 200

      rtt = Array.new(BASELINE_REQUESTS) { probe.call('GET', '/health')[:client_ms] }
      probe.finish
      say "Base URL:     #{@base_url}"
      say "Release:      #{NfrLoad.json(health, 'GET /health')['release']}"
      say "Started:      #{Time.now.utc.strftime('%Y-%m-%d %H:%M:%S UTC')}"
      say "Seed:         #{PROJECTS} projects x #{TASKS_PER_PROJECT} tasks = #{PROJECTS * TASKS_PER_PROJECT} tasks"
      say "Scenario:     #{@requests} requests at #{@rate} a second, concurrency #{@concurrency}"
      say "Target:       p95 <= #{TARGET_MS} ms on server timing (X-Runtime), 0 % errors"
      say "Network:      GET /health round trip p50 #{Stats.percentile(rtt, 50)} ms, " \
          "max #{rtt.max} ms (#{BASELINE_REQUESTS} sequential)"
    end

    def sign_up
      @email = "nfr-load-#{Time.now.to_i}-#{SecureRandom.hex(2)}@example.com"
      password = SecureRandom.hex(16)
      response = once('POST', '/api/v1/users',
                      user: { email: @email, password: password, password_confirmation: password })
      say "User:         #{@email} (stays on the server: there is no API to delete it)"
      raise Abort, "sign-up answered #{response[:status] || response[:error]}; not retried" unless response[:status] == 201

      @token = NfrLoad.json(response, 'sign-up').dig('data', 'access_token')
      raise Abort, 'sign-up returned no access token (server without OAUTH_CLIENT_ID); legacy headers are not used' unless @token
    end

    def seed
      started = NfrLoad.now
      create_all(Array.new(PROJECTS) { |i| i + 1 }, @projects) do |api, i|
        [ api.call('POST', '/api/v1/projects',
                   project: { name: format('nfr p%02d', i), description: format('NFR load seed project number %02d', i) }) ]
      end
      create_all(@projects.product(Array.new(TASKS_PER_PROJECT) { |i| i + 1 }), @tasks) do |api, (project, i)|
        [ api.call('POST', "/api/v1/projects/#{project}/tasks",
                   task: { name: format('nfr task %03d', i), description: 'NFR load seed task', status: 'not_started' }),
          project ]
      end
      say "Seeded:       #{@projects.size} projects, #{@tasks.size} tasks in #{(NfrLoad.now - started).round(1)} s"
    end

    # Records every id as soon as the server returns it, so the cleanup deletes it whatever stops the run.
    def create_all(items, ids)
      lock = Mutex.new
      responses = NfrLoad.parallel(items, concurrency: SEED_CONCURRENCY, client: -> { client }) do |api, item|
        response, project = yield(api, item)
        if response[:status] == 201
          id = NfrLoad.json(response, 'a create').dig('data', 'id')
          lock.synchronize { ids << (project ? [ project, id ] : id) }
        end
        response
      end
      failed = responses.reject { |response| response[:status] == 201 }
      return if failed.empty?

      raise Abort, "seeding failed: #{failed.size} of #{items.size} answered " \
                   "#{failed.map { |response| response[:status] || response[:error] }.tally}"
    end

    def dashboard_list
      samples = load_run(Array.new(@requests)) { |api, _| api.call('GET', '/api/v1/projects') }
      first = samples.find { |sample| sample[:status] == 200 }
      if first
        projects = NfrLoad.json(first, 'GET /api/v1/projects')['data']
        tasks = projects.sum { |project| project['tasks'].size }
        raise Abort, "dashboard list returned #{projects.size} projects and #{tasks} tasks" \
          unless projects.size == PROJECTS && tasks == PROJECTS * TASKS_PER_PROJECT
      end
      samples
    end

    def status_change
      statuses = %w[in_progress completed]
      changes = Array.new(@requests) { |i| [ @tasks[i % @tasks.size], statuses[(i / @tasks.size) % 2] ] }
      load_run(changes) do |api, ((project, task), status)|
        api.call('PUT', "/api/v1/projects/#{project}/tasks/#{task}", task: { status: status })
      end
    end

    def load_run(items, &)
      NfrLoad.parallel(items, concurrency: @concurrency, rate: @rate, client: -> { client }, &)
    end

    def report(name, samples)
      summary = Stats.summary(samples)
      verdict = Stats.verdict(summary, TARGET_MS)
      say
      say "#{name}: #{summary[:count]} requests, #{summary[:errors]} errors (#{(summary[:error_rate] * 100).round(1)} %)"
      %i[server client].each do |basis|
        timing = summary[basis].map { |pct, ms| "#{pct} #{ms.nil? ? '-' : ms.round(1)} ms" }.join(', ')
        say "  #{basis.to_s.ljust(6)} #{timing}"
      end
      say "  #{verdict[:result]} (p95 #{verdict[:p95]&.round(1) || '-'} ms on #{verdict[:basis]} timing, " \
          "target #{TARGET_MS} ms)"
      verdict
    end

    def clean_up
      say
      tasks = deleted(@tasks) { |(project, task)| "/api/v1/projects/#{project}/tasks/#{task}" }
      projects = deleted(@projects) { |project| "/api/v1/projects/#{project}" }
      sign_out = once('POST', '/api/v1/sign_out')
      say "Cleanup:      deleted #{tasks.count(true)} of #{@tasks.size} tasks, " \
          "#{projects.count(true)} of #{@projects.size} projects; sign-out #{sign_out[:status] || sign_out[:error]}"
      complete = tasks.all? && projects.all?
      say "CLEANUP INCOMPLETE: #{@email} keeps what was not deleted" unless complete
      complete
    end

    def deleted(items)
      NfrLoad.parallel(items, concurrency: SEED_CONCURRENCY, client: -> { client }) do |api, item|
        api.call('DELETE', yield(item))[:status] == 204
      end
    end

    def client
      Client.new(@base_url, @token)
    end

    def once(...)
      api = client
      api.call(...)
    ensure
      api.finish
    end
  end
end

NfrLoad::Run.main(ARGV) if $PROGRAM_NAME == __FILE__
