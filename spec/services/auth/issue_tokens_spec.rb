require 'rails_helper'

RSpec.describe Auth::IssueTokens do
  include Sentry::TestHelper

  before { setup_sentry_test }
  after { teardown_sentry_test }

  let(:user) { create(:user) }

  it 'issues one token pair for the configured web client' do
    Doorkeeper::Application.create!(name: 'todolist web', uid: 'web-client-test', confidential: false)

    token = with_env('OAUTH_CLIENT_ID' => 'web-client-test') { described_class.call(user) }

    expect(token.plaintext_refresh_token).to be_present
    expect(token.expires_in).to eq(3600)
  end

  it 'issues nothing and reports nothing while OAUTH_CLIENT_ID is unset' do
    expect(with_env('OAUTH_CLIENT_ID' => nil) { described_class.call(user) }).to be_nil
    expect(sentry_events).to be_empty
  end

  it 'issues nothing and reports the misconfiguration when no application has the configured uid' do
    token = with_env('OAUTH_CLIENT_ID' => 'no-such-client') { described_class.call(user) }

    expect(token).to be_nil
    expect(OauthAccessToken.count).to eq(0)
    expect(last_sentry_event.message).to include('OAUTH_CLIENT_ID')
  end
end
