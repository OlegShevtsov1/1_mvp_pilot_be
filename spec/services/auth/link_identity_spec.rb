require 'rails_helper'

RSpec.describe 'Auth::LinkIdentity' do
  let(:user) { create(:user) }

  it 'links Google and cancels the password, every token of the user and the legacy token (AC-06)' do
    tokens = create_list(:oauth_access_token, 2, resource_owner_id: user.id)
    other_users_token = create(:oauth_access_token)
    legacy_token = user.authentication_token

    Auth::LinkIdentity.call(user, 'google-1')

    expect(user.identities.sole).to have_attributes(provider: 'google', uid: 'google-1')
    expect(tokens.map(&:reload)).to all(be_revoked)
    expect(tokens.map(&:application).uniq.size).to eq(2)
    expect(other_users_token.reload).not_to be_revoked
    user.reload
    expect(user.valid_password?('password')).to be(false)
    expect(user.authentication_token).to be_present
    expect(user.authentication_token).not_to eq(legacy_token)
  end

  it 'links nothing and cancels nothing when the user cannot be saved (AC-06)' do
    token = create(:oauth_access_token, resource_owner_id: user.id)
    legacy_token = user.authentication_token
    allow(user).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(user))

    expect { Auth::LinkIdentity.call(user, 'google-1') }.to raise_error(ActiveRecord::RecordInvalid)

    expect(Identity.count).to eq(0)
    expect(token.reload).not_to be_revoked
    stored = User.find(user.id)
    expect(stored.valid_password?('password')).to be(true)
    expect(stored.authentication_token).to eq(legacy_token)
  end
end
