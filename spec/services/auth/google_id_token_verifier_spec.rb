require 'rails_helper'

RSpec.describe 'Auth::GoogleIdTokenVerifier' do
  include ActiveSupport::Testing::TimeHelpers

  after { travel_back }

  # Fixture keys stand in for Google's; generated once per run, never committed.
  rsa_keys = Array.new(3) { OpenSSL::PKey::RSA.generate(2048) }

  let(:certs_url) { 'https://www.googleapis.com/oauth2/v3/certs' }
  let(:client_id) { 'test-client.apps.googleusercontent.com' }
  let(:keys) { Auth::GoogleIdTokenVerifier::KeySet.new }
  let(:key1) { rsa_keys[0] }
  let(:key2) { rsa_keys[1] }
  let(:stranger_key) { rsa_keys[2] }

  def jwks(*pairs)
    { keys: pairs.map { |key, kid| JWT::JWK.new(key, kid: kid, use: 'sig', alg: 'RS256').export } }.to_json
  end

  def certs_response(*pairs)
    { status: 200, body: jwks(*pairs), headers: { 'Content-Type' => 'application/json' } }
  end

  def id_token(key: key1, kid: 'key-1', **claims)
    now = Time.now.to_i
    payload = { iss: 'https://accounts.google.com', aud: client_id, sub: '1234567890',
                email: 'person@example.com', email_verified: true, iat: now, exp: now + 600 }
    JWT.encode(payload.merge(claims).compact, key, 'RS256', kid: kid)
  end

  def verify(token, **opts)
    Auth::GoogleIdTokenVerifier.call(token, client_id: client_id, keys: keys, **opts)
  end

  def expect_refusal(result, error)
    expect(result).not_to be_success
    expect(result.email).to be_nil
    expect(result.uid).to be_nil
    expect(result.error).to eq(error)
  end

  context 'when Google serves its signing keys' do
    before { stub_request(:get, certs_url).to_return(certs_response([ key1, 'key-1' ])) }

    it 'accepts a Google-signed token for our client with a verified email' do
      result = verify(id_token)

      expect(result).to be_success
      expect(result.email).to eq('person@example.com')
      expect(result.uid).to eq('1234567890')
      expect(result.error).to be_nil
    end

    it 'accepts the issuer form without the scheme' do
      expect(verify(id_token(iss: 'accounts.google.com'))).to be_success
    end

    it 'refuses a token signed by another key under a known key id (AC-07)' do
      expect_refusal(verify(id_token(key: stranger_key)), :invalid_token)
    end

    it 'refuses a token issued for another client (AC-07)' do
      expect_refusal(verify(id_token(aud: 'someone-else.apps.googleusercontent.com')), :invalid_token)
    end

    it 'refuses a token from another issuer (AC-07)' do
      expect_refusal(verify(id_token(iss: 'https://evil.example')), :invalid_token)
    end

    it 'refuses an expired token (AC-07)' do
      expect_refusal(verify(id_token(exp: Time.now.to_i - 60)), :invalid_token)
    end

    it 'refuses a token whose email Google has not verified (AC-07)' do
      expect_refusal(verify(id_token(email_verified: false)), :email_not_verified)
    end

    it 'refuses a token that does not say the email is verified (AC-07)' do
      expect_refusal(verify(id_token(email_verified: nil)), :email_not_verified)
    end

    it 'accepts a token whose email_verified is the string "true"' do
      expect(verify(id_token(email_verified: 'true'))).to be_success
    end

    it 'refuses a token without an email (AC-07)' do
      expect_refusal(verify(id_token(email: nil)), :email_not_verified)
    end

    it 'refuses a token signed with a shared secret instead of a Google key' do
      token = JWT.encode({ iss: 'https://accounts.google.com', aud: client_id, sub: '1',
                           email: 'person@example.com', email_verified: true, exp: Time.now.to_i + 600 },
                         'secret', 'HS256', kid: 'key-1')

      expect_refusal(verify(token), :invalid_token)
    end

    it 'refuses something that is not a token' do
      expect_refusal(verify('not-a-token'), :invalid_token)
    end

    it 'refuses a missing token' do
      expect_refusal(verify(nil), :invalid_token)
      expect_refusal(verify(''), :invalid_token)
    end

    it 'refuses every token when no client id is configured, without asking Google' do
      expect_refusal(verify(id_token, client_id: nil), :not_configured)
      expect(a_request(:get, certs_url)).not_to have_been_made
    end

    it 'reads the client id from GOOGLE_CLIENT_ID' do
      token = id_token

      result = with_env('GOOGLE_CLIENT_ID' => client_id) do
        Auth::GoogleIdTokenVerifier.call(token, keys: keys)
      end

      expect(result).to be_success
    end

    it 'fetches the keys once for several tokens' do
      2.times { expect(verify(id_token)).to be_success }

      expect(a_request(:get, certs_url)).to have_been_made.once
    end

    it 'fetches the keys again after an hour' do
      verify(id_token)
      travel 61.minutes

      expect(verify(id_token)).to be_success
      expect(a_request(:get, certs_url)).to have_been_made.twice
    end
  end

  context 'when Google rotates its keys' do
    before do
      stub_request(:get, certs_url)
        .to_return(certs_response([ key1, 'key-1' ]))
        .then.to_return(certs_response([ key1, 'key-1' ], [ key2, 'key-2' ]))
    end

    it 'fetches the keys again for an unknown key id and accepts the token' do
      expect(verify(id_token)).to be_success
      travel 2.minutes

      expect(verify(id_token(key: key2, kid: 'key-2'))).to be_success
      expect(a_request(:get, certs_url)).to have_been_made.twice
    end

    it 'does not fetch again for an unknown key id right after a fetch' do
      expect(verify(id_token)).to be_success

      expect_refusal(verify(id_token(key: key2, kid: 'key-2')), :invalid_token)
      expect(a_request(:get, certs_url)).to have_been_made.once
    end
  end

  context 'when Google cannot be reached' do
    it 'refuses with keys_unavailable on an error status and reports it' do
      stub_request(:get, certs_url).to_return(status: 503)
      expect(Sentry).to receive(:capture_exception)

      expect_refusal(verify(id_token), :keys_unavailable)
    end

    it 'refuses with keys_unavailable on a timeout' do
      stub_request(:get, certs_url).to_timeout

      expect_refusal(verify(id_token), :keys_unavailable)
    end

    it 'refuses with keys_unavailable on a malformed key set' do
      stub_request(:get, certs_url).to_return(status: 200, body: 'not json')

      expect_refusal(verify(id_token), :keys_unavailable)
    end

    [ '{}', '{"keys":[]}', '[]', 'null', '"error"', '{"keys":"x"}', '{"keys":[{"kty":"FOO","kid":"z"}]}' ]
      .each do |body|
      it "refuses with keys_unavailable and reports it when Google's key set is #{body}" do
        stub_request(:get, certs_url).to_return(status: 200, body: body)
        expect(Sentry).to receive(:capture_exception)

        expect_refusal(verify(id_token), :keys_unavailable)
      end
    end

    it 'does not call Google again within a minute of a failed fetch' do
      stub_request(:get, certs_url).to_return(status: 503)
      allow(Sentry).to receive(:capture_exception)

      2.times { expect_refusal(verify(id_token), :keys_unavailable) }
      expect(a_request(:get, certs_url)).to have_been_made.once

      travel 61.seconds
      expect_refusal(verify(id_token), :keys_unavailable)
      expect(a_request(:get, certs_url)).to have_been_made.twice
    end

    it 'does not call Google for made-up key ids after a failed refetch' do
      stub_request(:get, certs_url).to_return(certs_response([ key1, 'key-1' ])).then.to_return(status: 503)
      allow(Sentry).to receive(:capture_exception)

      expect(verify(id_token)).to be_success
      travel 2.minutes
      results = Array.new(5) { verify(id_token(kid: 'made-up')) }

      expect(results).to all(satisfy { |r| !r.success? })
      expect(a_request(:get, certs_url)).to have_been_made.twice
    end

    it 'refuses made-up key ids with keys_unavailable after a failed refetch, and still accepts known keys' do
      stub_request(:get, certs_url).to_return(certs_response([ key1, 'key-1' ])).then.to_return(status: 503)
      expect(Sentry).to receive(:capture_exception).exactly(3).times

      expect(verify(id_token)).to be_success
      travel 2.minutes
      3.times { expect_refusal(verify(id_token(kid: 'made-up')), :keys_unavailable) }

      expect(verify(id_token)).to be_success
      expect(a_request(:get, certs_url)).to have_been_made.twice
    end

    [ Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, EOFError, IOError, Net::HTTPBadResponse,
      OpenSSL::SSL::SSLError, Zlib::BufError ].each do |error|
      it "refuses with keys_unavailable and reports it when the call to Google raises #{error}" do
        stub_request(:get, certs_url).to_raise(error)
        expect(Sentry).to receive(:capture_exception)

        expect_refusal(verify(id_token), :keys_unavailable)
      end
    end

    it "refuses with keys_unavailable and reports it when a key in Google's set cannot be built" do
      stub_request(:get, certs_url)
        .to_return(status: 200, body: '{"keys":[{"kty":"RSA","kid":"key-1","n":5,"e":"AQAB"}]}')
      expect(Sentry).to receive(:capture_exception)

      expect_refusal(verify(id_token), :keys_unavailable)
    end
  end

  context 'when several threads share one key set' do
    it 'calls Google once while the first fetch is still running' do
      stub_request(:get, certs_url).to_return do
        sleep 0.2
        certs_response([ key1, 'key-1' ])
      end

      results = Array.new(5) { Thread.new { keys.call(kid: 'key-1') } }.map(&:value)

      expect(results).to all(be_a(JWT::JWK::Set))
      expect(a_request(:get, certs_url)).to have_been_made.once
    end
  end
end
