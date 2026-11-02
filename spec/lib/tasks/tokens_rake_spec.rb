require 'rails_helper'
require 'rake'

RSpec.describe 'rake tokens:purge' do
  include Sentry::TestHelper

  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?('tokens:purge')
  end

  before do
    setup_sentry_test
    Rake::Task['tokens:purge'].reenable
  end

  after { teardown_sentry_test }

  it 'deletes token rows revoked or expired more than 30 days ago and keeps recent and active ones' do
    create(:oauth_access_token, created_at: 40.days.ago, revoked_at: 31.days.ago)
    create(:oauth_access_token, created_at: 31.days.ago)
    kept = [
      create(:oauth_access_token, created_at: 2.days.ago, revoked_at: 1.day.ago),
      create(:oauth_access_token, created_at: 29.days.ago),
      create(:oauth_access_token, created_at: 10.minutes.ago),
      create(:oauth_access_token, created_at: 90.days.ago, expires_in: nil)
    ]

    expect { Rake::Task['tokens:purge'].invoke }.to output(/oauth_access_tokens=2/).to_stdout
    expect(OauthAccessToken.pluck(:id)).to contain_exactly(*kept.map(&:id))
  end

  it 'deletes legacy-use rows older than 60 days and keeps newer ones' do
    user = create(:user)
    [ 61, 60, 0 ].each { |days| create(:legacy_token_use, user:, used_on: Date.current - days) }

    expect { Rake::Task['tokens:purge'].invoke }.to output(/legacy_token_uses=1/).to_stdout
    expect(LegacyTokenUse.pluck(:used_on)).to contain_exactly(Date.current - 60, Date.current)
  end

  it 'reports a failed run to GlitchTip and exits non-zero' do
    allow(LegacyTokenUse).to receive(:where).and_raise(ActiveRecord::StatementInvalid, 'purge failed')

    expect { Rake.application.standard_exception_handling { Rake::Task['tokens:purge'].invoke } }
      .to raise_error(SystemExit).and output(/purge failed/).to_stderr_from_any_process

    exception = extract_sentry_exceptions(last_sentry_event).last
    expect(exception.type).to eq('ActiveRecord::StatementInvalid')
    expect(exception.value).to start_with('purge failed')
  end
end
