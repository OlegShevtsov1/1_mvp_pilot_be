require 'rails_helper'

RSpec.describe 'bin/docker-entrypoint' do
  it 'creates the web client after preparing the database' do
    expect(File.read(Rails.root.join('bin/docker-entrypoint'))).to include('./bin/rails db:prepare oauth:web_application')
  end
end
