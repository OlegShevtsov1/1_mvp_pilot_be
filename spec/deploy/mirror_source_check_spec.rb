require 'rails_helper'

RSpec.describe 'deploy/mirror_source_check.sh' do
  # The primary commit is deliberately not the mirror commit: the image to deploy is the primary's.
  let(:primary_sha) { 'b' * 40 }

  around do |example|
    in_git_repo do
      Dir.mktmpdir do |origin|
        git('init', '-q', '--bare', '-b', 'main', chdir: origin)
        git('remote', 'add', 'origin', origin)
        @mirror_sha = squash('PILOT-1: first (#1)', 'feat')
        git('push', '-q', 'origin', 'main')
        example.run
      end
    end
  end

  def write_mirror_source(tags)
    File.write(File.join(@repo, 'MIRROR_SOURCE.json'), JSON.generate(
      'repo' => 'owner/app', 'source_ref' => 'main', 'source_sha' => primary_sha, 'mirror_sha' => @mirror_sha,
      'synced_at' => '2026-10-20T10:00:00Z',
      'tags' => tags.map { |tag, sha| { 'tag' => tag, 'primary_sha' => sha, 'mirror_sha' => @mirror_sha } }
    ))
  end

  def publish_tag(name)
    annotated_tag(name)
    git('push', '-q', 'origin', name)
  end

  def check(tag, source_sha)
    run_in_repo3('deploy/mirror_source_check.sh', tag, source_sha)
  end

  it 'prints the primary image version when MIRROR_SOURCE.json records that source_sha for the tag' do
    publish_tag('v0.2.0')
    write_mirror_source([ [ 'v0.2.0', primary_sha ] ])

    stdout, stderr, status = check('v0.2.0', primary_sha)
    expect(status).to be_success, stderr
    expect(stdout).to eq("version=sha-#{primary_sha}\n")
  end

  it 'refuses a source_sha that MIRROR_SOURCE.json does not record for the tag' do
    publish_tag('v0.2.0')
    write_mirror_source([ [ 'v0.2.0', primary_sha ] ])

    stdout, stderr, status = check('v0.2.0', 'c' * 40)
    expect(status.exitstatus).to eq(1)
    expect(stdout).to be_empty
    expect(stderr).to include('does not match')
  end

  it 'refuses a tag that MIRROR_SOURCE.json does not record' do
    publish_tag('v0.2.0')
    write_mirror_source([ [ 'v0.1.0', primary_sha ] ])

    stdout, stderr, status = check('v0.2.0', primary_sha)
    expect(status.exitstatus).to eq(1)
    expect(stdout).to be_empty
    expect(stderr).to include('records no')
  end

  it 'refuses a tag that is missing on the mirror' do
    write_mirror_source([ [ 'v0.2.0', primary_sha ] ])

    stdout, stderr, status = check('v0.2.0', primary_sha)
    expect(status.exitstatus).to eq(1)
    expect(stdout).to be_empty
    expect(stderr).to include('not published')
  end

  it 'applies the release tag checks to the mirror tag' do
    write_mirror_source([ [ 'v0.2.0', primary_sha ], [ 'v0.3.0', primary_sha ] ])
    git('tag', 'v0.2.0')
    git('push', '-q', 'origin', 'v0.2.0')
    git('switch', '-q', '-c', 'side')
    squash('PILOT-2: side (#2)', 'feat')
    publish_tag('v0.3.0')

    _stdout, stderr, status = check('v0.2.0', primary_sha)
    expect(status.exitstatus).to eq(1)
    expect(stderr).to include('lightweight')

    _stdout, stderr, status = check('v0.3.0', primary_sha)
    expect(status.exitstatus).to eq(1)
    expect(stderr).to include('not on main')
  end

  it 'refuses when MIRROR_SOURCE.json is missing or not valid JSON' do
    publish_tag('v0.2.0')

    _stdout, stderr, status = check('v0.2.0', primary_sha)
    expect(status.exitstatus).to eq(1)
    expect(stderr).to include('MIRROR_SOURCE.json')

    File.write(File.join(@repo, 'MIRROR_SOURCE.json'), '{"tags": [')
    stdout, stderr, status = check('v0.2.0', primary_sha)
    expect(status.exitstatus).to eq(1)
    expect(stdout).to be_empty
    expect(stderr).to include('MIRROR_SOURCE.json')
  end

  it 'refuses an ambiguous MIRROR_SOURCE.json with two entries for the tag' do
    publish_tag('v0.2.0')
    write_mirror_source([ [ 'v0.2.0', primary_sha ], [ 'v0.2.0', primary_sha ] ])

    stdout, _stderr, status = check('v0.2.0', primary_sha)
    expect(status.exitstatus).to eq(1)
    expect(stdout).to be_empty
  end

  it 'refuses a malformed source_sha or version with a usage error' do
    publish_tag('v0.2.0')
    write_mirror_source([ [ 'v0.2.0', primary_sha ] ])

    [ [ 'v0.2.0', '' ], [ 'v0.2.0', 'b' * 39 ], [ 'v0.2.0', 'B' * 40 ], [ 'v0.2.0', "sha-#{primary_sha}" ],
      [ 'v1.2', primary_sha ] ].each do |args|
      stdout, _stderr, status = check(*args)
      expect(status.exitstatus).to eq(2), args.inspect
      expect(stdout).to be_empty
    end
  end
end
