require 'rails_helper'

RSpec.describe 'Failed sign-in limit', type: :request do
  let!(:web_client) { Doorkeeper::Application.create!(name: 'todolist web', uid: 'web-client-test', confidential: false) }
  let(:user) { create(:user) }

  def legacy_sign_in(email: user.email, password: 'wrong-password', env: { 'REMOTE_ADDR' => '203.0.113.7' }, headers: {})
    post '/api/v1/sign_in', params: { email:, password: }, as: :json, env:, headers:
  end

  def token_sign_in(email: user.email, password: 'wrong-password', env: { 'REMOTE_ADDR' => '203.0.113.7' })
    post '/oauth/token', params: { grant_type: 'password', client_id: web_client.uid, username: email, password: }, env:
  end

  def fail_legacy_sign_ins(count, **options)
    count.times do
      legacy_sign_in(**options)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  def fail_token_sign_ins(count, **options)
    count.times do
      token_sign_in(**options)
      expect(response).to have_http_status(:bad_request)
    end
  end

  def expect_wait_refusal
    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers['Retry-After']).to eq('60')
    expect(json_response).to eq('errors' => [ 'Too many failed sign-ins from this address. Wait a minute before trying again' ])
  end

  describe 'AC-09' do
    it 'gives an unknown email and a wrong password the same refusal at sign_in' do
      legacy_sign_in(email: 'nobody@example.com')
      unknown_email = [ response.status, json_response ]
      legacy_sign_in
      wrong_password = [ response.status, json_response ]

      expect(unknown_email).to eq(wrong_password)
      expect(wrong_password).to eq([ 401, { 'status' => 'error', 'message' => 'Invalid email or password' } ])
    end

    it 'gives an unknown email and a wrong password the same refusal at /oauth/token' do
      token_sign_in(email: 'nobody@example.com')
      unknown_email = [ response.status, json_response ]
      token_sign_in
      wrong_password = [ response.status, json_response ]

      expect(unknown_email).to eq(wrong_password)
      expect(wrong_password.first).to eq(400)
      expect(wrong_password.last['error']).to eq('invalid_grant')
    end
  end

  describe 'AC-10' do
    it 'refuses the eleventh failed sign-in in a minute at /oauth/token before the password is checked' do
      fail_token_sign_ins(10)
      expect(User).not_to receive(:find_for_database_authentication)

      token_sign_in(password: 'password')

      expect_wait_refusal
      expect(OauthAccessToken.count).to eq(0)
    end

    it 'refuses the eleventh failed sign-in in a minute at /api/v1/sign_in before the password is checked' do
      fail_legacy_sign_ins(10)
      expect(Sessions::Create).not_to receive(:call)

      legacy_sign_in(password: 'password')

      expect_wait_refusal
    end

    it 'counts failures at both doors together' do
      fail_token_sign_ins(5)
      fail_legacy_sign_ins(5)

      token_sign_in

      expect_wait_refusal
    end

    it 'counts an unknown email like a wrong password' do
      fail_legacy_sign_ins(10, email: 'nobody@example.com')

      legacy_sign_in(email: 'nobody@example.com')

      expect_wait_refusal
    end

    it 'counts an unknown email like a wrong password at /oauth/token' do
      fail_token_sign_ins(10, email: 'nobody@example.com')

      token_sign_in(email: 'nobody@example.com')

      expect_wait_refusal
    end

    it 'does not count successful sign-ins' do
      10.times do
        legacy_sign_in(password: 'password')
        expect(response).to have_http_status(:ok)
        token_sign_in(password: 'password')
        expect(response).to have_http_status(:ok)
      end
      fail_legacy_sign_ins(10)

      legacy_sign_in

      expect_wait_refusal
    end

    it 'keeps the failures counted before a successful sign-in' do
      fail_legacy_sign_ins(9)
      legacy_sign_in(password: 'password')
      expect(response).to have_http_status(:ok)
      fail_legacy_sign_ins(1)

      legacy_sign_in

      expect_wait_refusal
    end

    it 'does not let a success whose window ended during its check lower the next window' do
      fail_legacy_sign_ins(1)
      allow_any_instance_of(User).to receive(:valid_password?).and_wrap_original do |original, *args|
        Rails.cache.clear
        ErrorsController::RateLimitStore::FALLBACK.clear
        original.call(*args)
      end
      legacy_sign_in(password: 'password')
      expect(response).to have_http_status(:ok)
      allow_any_instance_of(User).to receive(:valid_password?).and_call_original
      fail_legacy_sign_ins(10)

      legacy_sign_in

      expect_wait_refusal
    end

    it 'does not count an attempt whose check failed with a server error at sign_in' do
      allow_any_instance_of(User).to receive(:valid_password?).and_raise(BCrypt::Errors::InvalidHash)
      10.times { expect { legacy_sign_in }.to raise_error(BCrypt::Errors::InvalidHash) }
      allow_any_instance_of(User).to receive(:valid_password?).and_call_original

      legacy_sign_in

      expect(response).to have_http_status(:unauthorized)
    end

    it 'does not count an attempt whose check failed with a server error at /oauth/token' do
      allow_any_instance_of(User).to receive(:valid_password?).and_raise(BCrypt::Errors::InvalidHash)
      10.times { expect { token_sign_in }.to raise_error(BCrypt::Errors::InvalidHash) }
      allow_any_instance_of(User).to receive(:valid_password?).and_call_original

      token_sign_in

      expect(response).to have_http_status(:bad_request)
    end

    it 'gives back an attempt once when a server error follows its right password at /oauth/token' do
      fail_token_sign_ins(9)
      allow(OauthAccessToken).to receive(:find_or_create_for).and_raise(ActiveRecord::ConnectionTimeoutError)
      expect { token_sign_in(password: 'password') }.to raise_error(ActiveRecord::ConnectionTimeoutError)
      allow(OauthAccessToken).to receive(:find_or_create_for).and_call_original
      fail_token_sign_ins(1)

      token_sign_in

      expect_wait_refusal
    end

    it 'refuses an attempt that arrives while the tenth failure is still being checked' do
      fail_legacy_sign_ins(9)
      first_in_check = Queue.new
      second_done = Queue.new
      checks = 0
      allow_any_instance_of(User).to receive(:valid_password?).and_wrap_original do |original, *args|
        checks += 1
        if checks == 1
          first_in_check << true
          second_done.pop(timeout: 5)
        end
        original.call(*args)
      end

      first = Thread.new do
        open_session.tap do |session|
          session.post '/api/v1/sign_in', params: { email: user.email, password: 'wrong-password' }, as: :json,
                                          env: { 'REMOTE_ADDR' => '203.0.113.7' }
        end
      end
      first_in_check.pop(timeout: 5)
      legacy_sign_in
      second_done << true

      expect_wait_refusal
      expect(first.value.response).to have_http_status(:unauthorized)
      expect(checks).to eq(1)
    end

    it 'keeps each source apart' do
      fail_legacy_sign_ins(10)

      legacy_sign_in(env: { 'REMOTE_ADDR' => '203.0.113.8' })

      expect(response).to have_http_status(:unauthorized)
    end

    it 'keeps limiting when the cache store fails' do
      allow(Rails.cache).to receive(:increment).and_return(nil)
      fail_legacy_sign_ins(10)

      legacy_sign_in

      expect_wait_refusal
    end
  end

  # 127.0.0.1 stands for the kamal-proxy hop: the public-repo check forbids private-range literals, and Rails trusts
  # loopback and private ranges alike.
  describe 'client address behind kamal-proxy' do
    let(:through_proxy) { { 'REMOTE_ADDR' => '127.0.0.1' } }

    it 'keys on the address the proxy forwards' do
      10.times do |i|
        legacy_sign_in(env: through_proxy, headers: { 'X-Forwarded-For' => "203.0.113.#{100 + i}, 203.0.113.10" })
        expect(response).to have_http_status(:unauthorized)
      end

      legacy_sign_in(env: through_proxy, headers: { 'X-Forwarded-For' => '203.0.113.10' })
      expect_wait_refusal

      legacy_sign_in(env: through_proxy, headers: { 'X-Forwarded-For' => '203.0.113.11' })
      expect(response).to have_http_status(:unauthorized)
    end

    it 'ignores the forwarded header from a caller that is not the proxy' do
      direct = { 'REMOTE_ADDR' => '198.51.100.7' }
      10.times do |i|
        legacy_sign_in(env: direct, headers: { 'X-Forwarded-For' => "203.0.113.#{i + 1}" })
        expect(response).to have_http_status(:unauthorized)
      end

      legacy_sign_in(env: direct, headers: { 'X-Forwarded-For' => '203.0.113.50' })

      expect_wait_refusal
    end

    it 'accepts a trusted-proxy list written as patterns, as Rails does' do
      allow(Rails.application.config.action_dispatch).to receive(:trusted_proxies).and_return([ /\A127\.0\.0\.1\z/ ])
      10.times do |i|
        legacy_sign_in(env: through_proxy, headers: { 'X-Forwarded-For' => "203.0.113.#{100 + i}, 203.0.113.10" })
        expect(response).to have_http_status(:unauthorized)
      end

      legacy_sign_in(env: through_proxy, headers: { 'X-Forwarded-For' => '203.0.113.10' })

      expect_wait_refusal
    end
  end
end
