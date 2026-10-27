require 'rails_helper'

RSpec.describe 'Authentication with a bearer token or the legacy headers', type: :request do
  let(:user) { create(:user) }
  let!(:project) { create(:project, user: user) }
  let(:legacy) { { 'X-User-Email' => user.email, 'X-User-Token' => user.authentication_token } }
  let(:access_token) { create(:oauth_access_token, resource_owner_id: user.id) }
  let(:bearer) { { 'Authorization' => "Bearer #{access_token.plaintext_token}" } }

  around { |ex| with_env('LEGACY_AUTH_ENABLED' => nil, 'SMOKE_TOKEN' => 'smoke-test-token') { ex.run } }

  def project_ids = JSON.parse(response.body)['data'].map { |p| p['id'] }

  it 'gives a bearer token and the legacy pair the same access (AC-12)' do
    get '/api/v1/projects', headers: bearer
    expect(response).to have_http_status(:ok)
    via_bearer = project_ids
    get '/api/v1/projects', headers: legacy
    expect(response).to have_http_status(:ok)
    expect(project_ids).to eq(via_bearer).and eq([ project.id ])
  end

  it 'counts each legacy request for the user today, not bearer or pipeline-marked ones (AC-12)' do
    expect {
      2.times { get '/api/v1/projects', headers: legacy }
      post '/api/v1/projects', headers: legacy, params: { project: { name: 'Legacy', description: 'x' * 40 } }
    }.to change { LegacyTokenUse.find_by(user: user, used_on: Date.current)&.uses_count }.from(nil).to(3)
    expect { get '/api/v1/projects', headers: bearer }.not_to change(LegacyTokenUse, :count)
    expect {
      get '/api/v1/projects', headers: legacy.merge('X-Smoke-Token' => 'smoke-test-token')
    }.not_to(change { LegacyTokenUse.sum(:uses_count) })
    expect(response).to have_http_status(:ok)
    expect {
      get '/api/v1/projects', headers: legacy.merge('X-Smoke-Token' => 'wrong')
    }.to change { LegacyTokenUse.sum(:uses_count) }.by(1)
  end

  it 'refuses the legacy pair with Not Authorized when the legacy path is off (AC-13)' do
    with_env('LEGACY_AUTH_ENABLED' => 'false') do
      expect {
        patch "/api/v1/projects/#{project.id}", headers: legacy, params: { project: { name: 'Changed' } }
      }.not_to(change { project.reload.attributes })
      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)).to eq('error' => 'Not Authorized')
      expect(LegacyTokenUse.count).to eq(0)
    end
  end

  it 'refuses a revoked bearer token without falling back to the legacy pair of another user' do
    other = create(:user)
    access_token.revoke
    get '/api/v1/projects', headers: bearer.merge('X-User-Email' => other.email, 'X-User-Token' => other.authentication_token)
    expect(response).to have_http_status(:unauthorized)
    expect(LegacyTokenUse.count).to eq(0)
  end

  it 'refuses a revoked or expired bearer token without falling back to its own owner\'s legacy pair' do
    access_token.revoke
    get '/api/v1/projects', headers: bearer.merge(legacy)
    expect(response).to have_http_status(:unauthorized)

    expired = create(:oauth_access_token, resource_owner_id: user.id)
    expired.update_column(:created_at, 2.hours.ago)
    get '/api/v1/projects', headers: legacy.merge('Authorization' => "Bearer #{expired.plaintext_token}")
    expect(response).to have_http_status(:unauthorized)
    expect(LegacyTokenUse.count).to eq(0)
  end

  it 'serves a valid legacy request and reports the error when counting its use fails (AC-12)' do
    allow(LegacyTokenUse).to receive(:upsert_all).and_raise(ActiveRecord::ConnectionNotEstablished)
    expect(Sentry).to receive(:capture_exception).with(instance_of(ActiveRecord::ConnectionNotEstablished))
    get '/api/v1/projects', headers: legacy
    expect(response).to have_http_status(:ok)
    expect(project_ids).to eq([ project.id ])
  end

  it 'refuses an expired bearer token' do
    access_token.update_column(:created_at, 2.hours.ago)
    get '/api/v1/projects', headers: bearer
    expect(response).to have_http_status(:unauthorized)
  end
end
