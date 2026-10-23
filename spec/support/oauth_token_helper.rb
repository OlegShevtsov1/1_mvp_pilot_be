module OauthTokenHelper
  def self.included(group)
    group.let!(:web_client) do
      Doorkeeper::Application.create!(name: 'todolist web', uid: 'web-client-test', confidential: false)
    end
  end

  def refresh(refresh_token)
    post '/oauth/token', params: { grant_type: 'refresh_token', client_id: web_client.uid, refresh_token: }
    response.parsed_body
  end
end
