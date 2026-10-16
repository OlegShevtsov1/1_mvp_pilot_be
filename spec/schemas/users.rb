module Schemas
  class Users
    # CREATE_RESPONSE_SCHEMA = {
    #   type: :object,
    #   properties: {
    #     id: { type: :integer },
    #     email: { type: :string, format: :email },
    #     authentication_token: { type: :string }
    #   },
    #   required: %w[id email]
    # }.freeze

    CREATE_RESPONSE_SCHEMA = {
      type: :object,
      properties: {
        user_id: { type: :integer },
        email: { type: :string, format: :email },
        authentication_token: { type: :string }
      },
      required: %w[user_id email]
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
