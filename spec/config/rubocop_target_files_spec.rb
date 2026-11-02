require 'rails_helper'
require 'open3'

# RuboCop before 1.86.2 skipped every AllCops Exclude when the working directory had a hidden segment, such as
# the factory's worktrees under ~/.archon/, so the local lint gate inspected db/schema.rb and bin/* while CI
# stayed green (PILOT-360, rubocop/rubocop#15106).
RSpec.describe 'RuboCop file list' do
  around do |example|
    Dir.mktmpdir do |tmp|
      @checkout = File.join(tmp, '.archon', 'worktrees', 'checkout')
      example.run
    end
  end

  let(:listed) do
    %w[.rubocop.yml db/schema.rb bin/rails app/models/application_record.rb].each do |path|
      FileUtils.mkdir_p(File.dirname(File.join(@checkout, path)))
      FileUtils.cp(Rails.root.join(path), File.join(@checkout, path))
    end
    out, err, status = Open3.capture3({ 'BUNDLE_GEMFILE' => Rails.root.join('Gemfile').to_s },
                                      'bundle', 'exec', 'rubocop', '-L', chdir: @checkout)
    raise "rubocop -L failed: #{err}" unless status.success?

    out.lines(chomp: true)
  end

  it 'leaves out db/schema.rb and bin/* for a checkout under a hidden directory' do
    expect(listed).to include('app/models/application_record.rb')
    expect(listed).not_to include('db/schema.rb', 'bin/rails')
  end
end
