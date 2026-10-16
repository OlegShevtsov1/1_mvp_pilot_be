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
  end

  CREATE_RESPONSE_SCHEMA = {
    type: :object,
    properties: {
      id: { type: :integer },
      email: { type: :string, format: :email },
      authentication_token: { type: :string }
    },
    required: %w[id email]
  }.freeze
end
