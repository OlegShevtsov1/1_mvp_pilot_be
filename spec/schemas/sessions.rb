module Schemas
  class Sessions
    CREATE_REQUEST_SCHEMA =
      {
        type: :object,
        properties: {
          email: { type: :string, example: Examples::UserData.email },
          password: { type: :string, example: Examples::UserData.password }
        },
        required: %w[email password]
      }.freeze

    LEGACY_SIGN_IN_RESULT = {
      type: :object,
      properties: {
        status: { type: :string, enum: %w[success] },
        message: { type: :string },
        data: {
          type: :object,
          properties: {
            user_id: { type: :integer },
            email: { type: :string, format: :email },
            authentication_token: { type: :string }
          },
          required: %w[user_id email authentication_token],
          additionalProperties: false
        }
      },
      required: %w[status message data],
      additionalProperties: false
    }.freeze

    STATUS_MESSAGE = {
      type: :object,
      properties: {
        status: { type: :string, enum: %w[error success] },
        message: { type: :string }
      },
      required: %w[status message],
      additionalProperties: false
    }.freeze
  end
end
