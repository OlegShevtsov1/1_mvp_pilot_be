require 'rails_helper'

RSpec.describe 'Sign-up', type: :request do
  include OauthTokenHelper

  around { |example| with_env('OAUTH_CLIENT_ID' => 'web-client-test', 'SMOKE_TOKEN' => nil) { example.run } }

  # The limit's counters outlive an example; leftovers would refuse sign-ups in other specs.
  def clear_sign_up_counters
    Rails.cache.clear
    ErrorsController::RateLimitStore::FALLBACK.clear
  end

  before { clear_sign_up_counters }
  after { clear_sign_up_counters }

  def sign_up(email:, password: 'password123', confirmation: password, source: '203.0.113.7', headers: {})
    post '/api/v1/users',
         params: { user: { email:, password:, password_confirmation: confirmation } },
         headers:, as: :json, env: { 'REMOTE_ADDR' => source }
  end

  def sign_up_five_times(source: '203.0.113.7')
    5.times { |i| sign_up(email: "counted-#{i}@example.com", source:) }
    expect(response).to have_http_status(:created)
  end

  describe 'AC-02' do
    it 'signs the device in with its own token pair next to the legacy token' do
      expect { sign_up(email: 'new@example.com') }.to change(User, :count).by(1)

      expect(response).to have_http_status(:created)
      data = json_response['data']
      expect(data.keys).to contain_exactly('user_id', 'email', 'authentication_token',
                                           'access_token', 'refresh_token', 'expires_in')
      user = User.find_by!(email: 'new@example.com')
      expect(data).to include('user_id' => user.id, 'email' => user.email,
                              'authentication_token' => user.authentication_token, 'expires_in' => 3600)

      token = OauthAccessToken.by_token(data['access_token'])
      expect(token).to be_accessible
      expect(token.resource_owner_id).to eq(user.id)
      expect(token.application).to eq(web_client)

      post '/oauth/token', params: { grant_type: 'refresh_token', client_id: web_client.uid,
                                     refresh_token: data['refresh_token'] }
      expect(response).to have_http_status(:ok)
    end

    it 'returns the legacy fields only without a configured web client' do
      with_env('OAUTH_CLIENT_ID' => nil) { sign_up(email: 'legacy@example.com') }

      expect(response).to have_http_status(:created)
      expect(json_response['data'].keys).to contain_exactly('user_id', 'email', 'authentication_token')
      expect(OauthAccessToken.count).to eq(0)
    end
  end

  describe 'AC-03' do
    {
      'a malformed email' => [ { email: 'not-an-email' }, 'Email is invalid' ],
      'a short password' => [ { email: 'short@example.com', password: 'short' },
                              'Password is too short (minimum is 6 characters)' ],
      'a mismatched confirmation' => [ { email: 'mismatch@example.com', confirmation: 'different123' },
                                       "Password confirmation doesn't match Password" ]
    }.each do |case_name, (fields, message)|
      it "refuses #{case_name} and names the field" do
        expect { sign_up(**fields) }.not_to change(User, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response['errors']).to include(message)
        expect(OauthAccessToken.count).to eq(0)
      end
    end
  end

  describe 'AC-04' do
    it 'refuses a taken email and says to sign in instead' do
      create(:user, email: 'taken@example.com')

      expect { sign_up(email: 'TAKEN@example.com') }.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_response['errors']).to eq(
        [ 'Email already belongs to an account. Sign in instead, with Google sign-in or your password' ]
      )
    end
  end

  describe 'AC-04b' do
    def expect_wait_refusal
      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers['Retry-After']).to eq('3600')
      expect(json_response).to eq(
        'status' => 'error', 'message' => 'User could not be created',
        'errors' => [ 'Too many sign-ups from this address. Wait an hour before trying again' ]
      )
    end

    it 'refuses the sixth sign-up in an hour from one source' do
      sign_up_five_times

      sign_up(email: 'sixth@example.com')

      expect_wait_refusal
      expect(User.find_by(email: 'sixth@example.com')).to be_nil
    end

    it 'counts refused sign-ups too' do
      5.times { |i| sign_up(email: "bad-#{i}") }
      expect(response).to have_http_status(:unprocessable_entity)

      sign_up(email: 'valid@example.com')

      expect_wait_refusal
      expect(User.find_by(email: 'valid@example.com')).to be_nil
    end

    it 'keeps other sources open' do
      sign_up_five_times

      sign_up(email: 'elsewhere@example.com', source: '198.51.100.1')

      expect(response).to have_http_status(:created)
    end

    it 'lets the deploy smoke through when it presents SMOKE_TOKEN' do
      with_env('SMOKE_TOKEN' => 'smoke-test-token') do
        sign_up_five_times

        sign_up(email: 'smoke@example.com', headers: { 'X-Smoke-Token' => 'smoke-test-token' })
        expect(response).to have_http_status(:created)

        sign_up(email: 'impostor@example.com', headers: { 'X-Smoke-Token' => 'wrong' })
        expect_wait_refusal
      end
    end

    it 'never exempts a sign-up while SMOKE_TOKEN is unset' do
      sign_up_five_times

      sign_up(email: 'blank@example.com', headers: { 'X-Smoke-Token' => '' })

      expect_wait_refusal
    end
  end
end
