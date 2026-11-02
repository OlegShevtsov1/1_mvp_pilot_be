module Schemas
  class Users
    SIGN_UP_RESULT = {
      type: :object,
      properties: {
        status: { type: :string, enum: %w[success] },
        message: { type: :string },
        data: {
          type: :object,
          description: 'The three token fields are present together, or absent while no web client is configured',
          properties: {
            user_id: { type: :integer },
            email: { type: :string, format: :email },
            authentication_token: { type: :string, description: 'legacy access token, removed at the cutoff' },
            access_token: { type: :string },
            refresh_token: { type: :string },
            expires_in: { type: :integer, enum: [ 3600 ] }
          },
          required: %w[user_id email authentication_token],
          additionalProperties: false
        }
      },
      required: %w[status message data],
      additionalProperties: false
    }.freeze

    PROFILE = {
      type: :object,
      properties: {
        status: { type: :string, enum: %w[success] },
        message: { type: :string },
        data: {
          type: :object,
          properties: {
            user_id: { type: :integer },
            email: { type: :string, format: :email }
          },
          required: %w[user_id email],
          additionalProperties: false
        }
      },
      required: %w[status message data],
      additionalProperties: false
    }.freeze

    ERROR_LIST = {
      type: :object,
      properties: {
        status: { type: :string, enum: %w[error] },
        message: { type: :string },
        errors: { type: :array, items: { type: :string } }
      },
      required: %w[errors]
    }.freeze

    ERROR_MESSAGE = {
      type: :object,
      properties: {
        error: { type: :string }
      },
      required: %w[error],
      additionalProperties: false
    }.freeze

    CREATE_REQUEST_SCHEMA = {
      type: :object,
      properties: {
        user: {
          type: :object,
          properties: {
            email: { type: :string, example: Examples::UserData.email },
            password: { type: :string, example: Examples::UserData.password },
            password_confirmation: { type: :string, example: Examples::UserData.password }
          },
          required: %w[email password password_confirmation]
        }
      }
    }.freeze
  end
end
