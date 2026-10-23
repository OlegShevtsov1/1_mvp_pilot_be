require 'rails_helper'

RSpec.describe 'Auth::GoogleSignIn' do
  def verification(success: true, email: 'person@example.com', uid: 'google-1', error: nil)
    instance_double('Auth::GoogleIdTokenVerifier', success?: success, email:, uid:, error:)
  end

  def sign_in_with(result)
    allow(Auth::GoogleIdTokenVerifier).to receive(:call).with('id-token').and_return(result)
    Auth::GoogleSignIn.call('id-token')
  end

  it 'refuses with the verifier error and creates or links nothing when Google does not vouch for the email (AC-07)' do
    create(:user, email: 'person@example.com')

    result = nil
    expect do
      result = sign_in_with(verification(success: false, email: nil, uid: nil, error: :email_not_verified))
    end.not_to change { [ User.count, Identity.count ] }

    expect(result).not_to be_success
    expect(result.error).to eq(:email_not_verified)
    expect(result.user).to be_nil
  end

  it 'refuses a user already linked to another Google account and keeps their access' do
    user = create(:user, email: 'person@example.com')
    identity = create(:identity, user:, uid: 'google-other')
    token = create(:oauth_access_token, resource_owner_id: user.id)

    result = sign_in_with(verification)

    expect(result).not_to be_success
    expect(result.user).to be_nil
    expect(user.identities.sole).to eq(identity)
    expect(token.reload).not_to be_revoked
  end

  it 'refuses, reports and persists nothing when the user cannot be saved' do
    create(:user, email: 'person@example.com')
    allow(User).to receive(:find_for_database_authentication).and_return(nil)
    allow(Sentry).to receive(:capture_message)

    result = nil
    expect { result = sign_in_with(verification) }.not_to change { [ User.count, Identity.count ] }

    expect(result).not_to be_success
    expect(result.user).to be_nil
    expect(Sentry).to have_received(:capture_message).with('Google sign-in not saved: ActiveRecord::RecordInvalid')
  end

  it 'refuses and reports a database collision without the email it names' do
    create(:user, email: 'person@example.com')
    collision = ActiveRecord::RecordNotUnique.new(
      'duplicate key value violates unique constraint DETAIL: Key (email)=(person@example.com) already exists.'
    )
    allow(Auth::LinkIdentity).to receive(:call).and_raise(collision)
    allow(Sentry).to receive(:capture_message)
    allow(Sentry).to receive(:capture_exception)

    result = sign_in_with(verification)

    expect(result).not_to be_success
    expect(result.user).to be_nil
    expect(Sentry).to have_received(:capture_message).with('Google sign-in not saved: ActiveRecord::RecordNotUnique')
    expect(Sentry).not_to have_received(:capture_exception)
  end
end
