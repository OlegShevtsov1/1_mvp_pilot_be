require 'rails_helper'
require 'open3'

# The production image installs the bundle with BUNDLE_WITHOUT=development:test (Dockerfile), and
# config/application.rb requires every gem of the default group at boot (PILOT-376).
RSpec.describe 'Gemfile groups' do
  let(:development_and_test_gems) do
    %w[bullet factory_bot_rails listen rails-controller-testing rspec-rails rspec_junit_formatter rubocop
       rubocop-rails shoulda-matchers]
  end

  it 'keeps the development and test gems out of the default group' do
    dsl = Bundler::Dsl.new
    dsl.eval_gemfile(Rails.root.join('Gemfile'))
    in_default = dsl.dependencies.select { |dep| dep.groups.include?(:default) }.map(&:name)

    expect(in_default & development_and_test_gems).to be_empty
  end

  it 'boots production without loading them when the bundle excludes development and test' do
    marker = 'loaded='
    env = {
      'RAILS_ENV' => 'production',
      'BUNDLE_WITHOUT' => 'development:test',
      'SECRET_KEY_BASE' => 'gemfile_groups_spec',
      # Never opened: booting and listing the loaded gems needs no database.
      'DATABASE_URL' => 'postgres://nobody:nobody@127.0.0.1:1/nope'
    }
    script = "puts '#{marker}' + Gem.loaded_specs.keys.join(',')"
    output, status = Open3.capture2e(env, 'bin/rails', 'runner', script, chdir: Rails.root.to_s)
    raise "production boot failed (#{status.exitstatus}):\n#{output}" unless status.success?

    expect(output[/^#{marker}(.*)$/, 1].split(',') & development_and_test_gems).to be_empty
  end
end
