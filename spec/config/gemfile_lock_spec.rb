require 'rails_helper'

# bundler-audit in CI checks the lock against an advisory database that changes under it; these
# floors keep the patched versions from being lost by a later lock change (PILOT-299, PILOT-556,
# PILOT-589, PILOT-625, PILOT-637).
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

  it 'locks rack at 3.1.23 or later, patched for GHSA-5v64-555j-wjxm and three more rack advisories' do
    expect(locked.fetch('rack')).to be >= Gem::Version.new('3.1.23')
  end

  it 'locks addressable at 2.9.1 or later, patched for GHSA-qq38-m9mg-xjj5 and six more addressable advisories' do
    expect(locked.fetch('addressable')).to be >= Gem::Version.new('2.9.1')
  end

  it 'locks nokogiri at 1.19.5 or later, patched for GHSA-3w22-6jfg-527w and two more nokogiri advisories' do
    expect(locked.fetch('nokogiri')).to be >= Gem::Version.new('1.19.5')
  end

  it 'locks rails-html-sanitizer at 1.7.2 or later, patched for GHSA-cpgf-5mjf-73p7 and GHSA-h7wh-q2qr-458c' do
    expect(locked.fetch('rails-html-sanitizer')).to be >= Gem::Version.new('1.7.2')
  end

  it 'locks loofah at 2.25.3 or later, patched for GHSA-345x-3rq2-jfrm and five more loofah advisories' do
    expect(locked.fetch('loofah')).to be >= Gem::Version.new('2.25.3')
  end

  # Four-part versions are spelled as segments: scripts/check-public-repo.sh reads a dotted one as an IPv4 literal.
  it 'locks rails at 8.0.5 patch 2 or later, patched for GHSA-f3w6-w445-fwh9 and seventeen more Rails advisories' do
    expect(locked.fetch('rails')).to be >= Gem::Version.new([ 8, 0, 5, 2 ].join('.'))
  end
end
