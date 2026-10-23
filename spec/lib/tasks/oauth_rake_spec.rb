require 'rails_helper'
require 'rake'

RSpec.describe 'rake oauth:web_application' do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?('oauth:web_application')
  end

  before { Rake::Task['oauth:web_application'].reenable }

  def run_task(client_id)
    with_env('OAUTH_CLIENT_ID' => client_id) { Rake::Task['oauth:web_application'].invoke }
    Rake::Task['oauth:web_application'].reenable
  end

  it 'creates the public web client whose uid is OAUTH_CLIENT_ID, once' do
    2.times { run_task('placeholder-oauth-client-id') }

    expect(Doorkeeper::Application.sole).to have_attributes(
      uid: 'placeholder-oauth-client-id', name: 'todolist web', confidential: false
    )
  end

  it 'does nothing when OAUTH_CLIENT_ID is unset or blank' do
    [ nil, '', '  ' ].each { |client_id| run_task(client_id) }

    expect(Doorkeeper::Application.count).to eq(0)
  end
end
