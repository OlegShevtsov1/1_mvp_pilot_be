require 'rails_helper'

# A password or refresh grant that is between checking the user and issuing the token while Google is linked
# to that user must not end up with a token the link left working (AC-06).
RSpec.describe 'A token grant racing a Google link', type: :request do
  # The grant and the link run on their own database connections, as in production, so the spec transaction
  # would hide their rows from each other.
  self.use_transactional_tests = false

  let!(:web_client) { Doorkeeper::Application.create!(name: 'todolist web', uid: 'race-client', confidential: false) }
  let!(:user) { create(:user, email: 'person@example.com') }
  let(:resume_grant) { Queue.new }

  before do
    verification = instance_double('Auth::GoogleIdTokenVerifier', success?: true, email: user.email,
                                                                  uid: 'google-1', error: nil)
    allow(Auth::GoogleIdTokenVerifier).to receive(:call).and_return(verification)
  end

  after do
    User.find(user.id).destroy!
    web_client.delete
  end

  def token_request(params)
    env = Rack::MockRequest.env_for('/oauth/token', method: 'POST', params: params.merge(client_id: web_client.uid))
    env['HTTP_HOST'] = 'www.example.com'
    status, _headers, body = Rails.application.call(env)
    [ status, JSON.parse(body.each.to_a.join) ]
  end

  # Holds the grant at the receiver's method, before it runs or, with after:, once it has returned, links Google
  # meanwhile, and lets the grant go on once the link is done or, if the link waits for the grant, after two seconds.
  def grant_while_linking(params, pause_at:, receiver: OauthAccessToken, after: false)
    paused = Queue.new
    allow(receiver).to receive(pause_at).and_wrap_original do |original, *args, **options|
      next original.call(*args, **options) unless Thread.current[:grant]

      result = original.call(*args, **options) if after
      paused << true
      resume_grant.pop
      after ? result : original.call(*args, **options)
    end

    grant = Thread.new do
      Thread.current[:grant] = true
      token_request(params)
    end
    paused.pop
    link = Thread.new { ActiveRecord::Base.connection_pool.with_connection { Auth::GoogleSignIn.call('id-token') } }
    link.join(2)
    resume_grant << true
    [ grant.value, link.value ]
  end

  it 'leaves no working token from a password sign-in that raced the link' do
    (status, body), sign_in = grant_while_linking({ grant_type: 'password', username: user.email,
                                                    password: 'password' }, pause_at: :find_or_create_for)

    expect(sign_in).to be_success
    expect(user.identities.sole.uid).to eq('google-1')
    token = OauthAccessToken.by_token(body['access_token']) if status == 200
    expect(token).to be_nil.or be_revoked
  end

  it 'refuses a password sign-in that found the user before the link removed the password' do
    (status, body), sign_in = grant_while_linking({ grant_type: 'password', username: user.email,
                                                    password: 'password' },
                                                  receiver: User, pause_at: :find_for_database_authentication,
                                                  after: true)

    expect(sign_in).to be_success
    expect(status).to eq(400)
    expect(body['error']).to eq('invalid_grant')
  end

  it 'leaves no working token from a refresh that raced the link' do
    _, earlier = token_request(grant_type: 'password', username: user.email, password: 'password')

    (status, body), sign_in = grant_while_linking({ grant_type: 'refresh_token',
                                                    refresh_token: earlier['refresh_token'] }, pause_at: :create_for)

    expect(sign_in).to be_success
    token = OauthAccessToken.by_token(body['access_token']) if status == 200
    expect(token).to be_nil.or be_revoked
    expect(token_request(grant_type: 'refresh_token', refresh_token: body['refresh_token']).first).to eq(400)
  end
end
