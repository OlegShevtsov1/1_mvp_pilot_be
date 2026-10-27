require 'rails_helper'

# bundler-audit in CI checks the lock against an advisory database that changes under it; these
# floors keep the patched versions from being lost by a later lock change (PILOT-299).
RSpec.describe 'Gemfile.lock' do
  let(:locked) do
    Bundler::LockfileParser.new(Rails.root.join('Gemfile.lock').read).specs.to_h { |spec| [ spec.name, spec.version ] }
  end

  it 'locks net-ssh at 7.3.5 or later, patched for GHSA-vxj5-fg65-x765 and GHSA-rpq3-v334-f5pm' do
    expect(locked.fetch('net-ssh')).to be >= Gem::Version.new('7.3.5')
  end

  it 'locks crass at 1.0.8 or later, patched for GHSA-pq4g-8rxf-4g29' do
    expect(locked.fetch('crass')).to be >= Gem::Version.new('1.0.8')
  end
end
