module Schemas
  module Oauth
    TOKEN_REQUEST = {
      type: :object,
      properties: {
        grant_type: { type: :string, enum: %w[password google_id_token refresh_token] },
        client_id: { type: :string, description: 'the public id of the registered web client' },
        username: { type: :string, format: :email, description: 'required for password' },
        password: { type: :string, description: 'required for password' },
        id_token: { type: :string, description: 'the Google ID token, required for google_id_token' },
        refresh_token: { type: :string, description: 'required for refresh_token' }
      },
      required: %w[grant_type client_id],
      additionalProperties: false
    }.freeze

    TOKEN_PAIR = {
      type: :object,
      properties: {
        access_token: { type: :string },
        token_type: { type: :string, enum: %w[Bearer] },
        expires_in: { type: :integer, enum: [ 3600 ] },
        refresh_token: { type: :string },
        created_at: { type: :integer, description: 'Unix time of issue' }
      },
      required: %w[access_token token_type expires_in refresh_token created_at],
      additionalProperties: false
    }.freeze

    OAUTH_ERROR = {
      type: :object,
      properties: {
        error: { type: :string },
        error_description: { type: :string }
      },
      required: %w[error],
      additionalProperties: false
    }.freeze

    REVOKE_REQUEST = {
      type: :object,
      properties: {
        client_id: { type: :string },
        token: { type: :string, description: 'the access token or refresh token to revoke' }
      },
      required: %w[client_id token],
      additionalProperties: false
    }.freeze
  end
end
