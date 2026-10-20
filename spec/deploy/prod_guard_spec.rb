require 'rails_helper'

RSpec.describe 'deploy/prod_guard.sh' do
  let(:sha) { 'f' * 40 }

  def guard(mode, env)
    full_env = { 'REF' => 'refs/heads/main', 'ENVIRONMENT' => nil, 'CONFIRM' => nil, 'VERSION' => nil, 'ACTION' => nil,
                 'MIRROR' => nil, 'SOURCE_SHA' => nil }
    Open3.capture2e(full_env.merge(env), Rails.root.join('deploy/prod_guard.sh').to_s, mode)
  end

  describe 'deploy' do
    let(:valid) { { 'ENVIRONMENT' => 'prod', 'CONFIRM' => 'prod', 'VERSION' => 'v0.1.0' } }

    it 'runs only from main' do
      output, status = guard('deploy', valid.merge('REF' => 'refs/heads/feature'))
      expect(status.exitstatus).to eq(1)
      expect(output).to include('::error::prod runs only from main (got refs/heads/feature)')
    end

    it 'needs confirm=prod exactly' do
      output, status = guard('deploy', valid.merge('CONFIRM' => 'yes'))
      expect(status.exitstatus).to eq(1)
      expect(output).to include("confirm must be exactly 'prod'")
    end

    it 'needs environment=prod' do
      _output, status = guard('deploy', valid.merge('ENVIRONMENT' => 'dev'))
      expect(status.exitstatus).to eq(1)
    end

    it 'refuses a version that is not a release tag' do
      %w[latest v1.2 v01.2.3 1.2.3].each do |version|
        output, status = guard('deploy', valid.merge('VERSION' => version))
        expect(status.exitstatus).to eq(1), version
        expect(output).not_to include('tag=')
      end
    end

    it 'refuses a bare sha, with or without the sha- prefix: prod deploys only a release tag' do
      [ sha, "sha-#{sha}" ].each do |version|
        output, status = guard('deploy', valid.merge('VERSION' => version))
        expect(status.exitstatus).to eq(1)
        expect(output).to include('::error::', 'release tag vX.Y.Z')
        expect(output).not_to include('tag=')
      end
    end

    it 'prints the release tag for the next checks' do
      output, status = guard('deploy', valid)
      expect(status).to be_success, output
      expect(output).to eq("tag=v0.1.0\n")
    end

    it 'on the mirror (MIRROR=true) prints the tag and the source_sha' do
      output, status = guard('deploy', valid.merge('VERSION' => 'v0.2.0', 'MIRROR' => 'true', 'SOURCE_SHA' => sha))
      expect(status).to be_success, output
      expect(output).to eq("tag=v0.2.0\nsource_sha=#{sha}\n")
    end

    it 'on the mirror refuses a missing or malformed source_sha, naming mirror mode' do
      [ nil, 'f' * 39, 'F' * 40, "sha-#{sha}" ].each do |source_sha|
        output, status = guard('deploy', valid.merge('MIRROR' => 'true', 'SOURCE_SHA' => source_sha))
        expect(status.exitstatus).to eq(1), source_sha.inspect
        expect(output).to include('::error::', 'mirror mode')
        expect(output).not_to include('tag=')
      end
    end

    it 'on the mirror still refuses a bare sha as the version' do
      output, status = guard('deploy', valid.merge('VERSION' => sha, 'MIRROR' => 'true', 'SOURCE_SHA' => sha))
      expect(status.exitstatus).to eq(1)
      expect(output).not_to include('tag=')
    end

    it 'on the primary refuses a source_sha, naming primary mode' do
      [ nil, 'false' ].each do |mirror|
        output, status = guard('deploy', valid.merge('MIRROR' => mirror, 'SOURCE_SHA' => sha))
        expect(status.exitstatus).to eq(1), mirror.inspect
        expect(output).to include('::error::', 'primary mode')
        expect(output).not_to include('tag=')
      end
    end
  end

  describe 'manage' do
    it 'lets status and logs run without a confirm' do
      %w[status logs].each do |action|
        output, status = guard('manage', 'ACTION' => action)
        expect(status).to be_success
        expect(output).to eq("version=\n")
      end
    end

    it 'needs confirm=prod to restart' do
      _output, status = guard('manage', 'ACTION' => 'restart')
      expect(status.exitstatus).to eq(1)
    end

    it 'restarts with confirm=prod' do
      output, status = guard('manage', 'ACTION' => 'restart', 'CONFIRM' => 'prod')
      expect(status).to be_success, output
    end

    it 'rolls back with confirm=ROLLBACK-prod to the previous version when none is given' do
      output, status = guard('manage', 'ACTION' => 'rollback', 'CONFIRM' => 'ROLLBACK-prod')
      expect(status).to be_success
      expect(output).to eq("version=\n")
    end

    it 'normalises an explicit rollback version' do
      output, status = guard('manage', 'ACTION' => 'rollback', 'CONFIRM' => 'ROLLBACK-prod', 'VERSION' => sha)
      expect(status).to be_success
      expect(output).to eq("version=sha-#{sha}\n")
    end

    it 'refuses a rollback with confirm=prod, with or without a version' do
      [ {}, { 'VERSION' => sha } ].each do |extra|
        output, status = guard('manage', { 'ACTION' => 'rollback', 'CONFIRM' => 'prod' }.merge(extra))
        expect(status.exitstatus).to eq(1)
        expect(output).to include('rollback needs confirm=ROLLBACK-prod')
      end
    end

    it 'needs confirm=remove-prod to remove' do
      output, status = guard('manage', 'ACTION' => 'remove', 'CONFIRM' => 'prod')
      expect(status.exitstatus).to eq(1)
      expect(output).to include('remove needs confirm=remove-prod')
    end

    it 'refuses an unknown action' do
      _output, status = guard('manage', 'ACTION' => 'reboot', 'CONFIRM' => 'prod')
      expect(status.exitstatus).to eq(1)
    end

    it 'runs only from main' do
      _output, status = guard('manage', 'ACTION' => 'status', 'REF' => 'refs/heads/feature')
      expect(status.exitstatus).to eq(1)
    end
  end
end
