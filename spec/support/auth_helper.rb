module AuthHelper
  EMAIL_HEADER = :'X-User-Email'
  TOKEN_HEADER = :'X-User-Token'

  def authenticate_user(user)
    request.headers[EMAIL_HEADER.to_s] = user.email
    request.headers[TOKEN_HEADER.to_s] = user.authentication_token
    controller.instance_variable_set(:@current_user, user)
  end

  def authenticate_with_token
    let(EMAIL_HEADER) { email }
    let(TOKEN_HEADER) { token }
  end

  def authenticate_with_user
    let(EMAIL_HEADER) { user.email }
    let(TOKEN_HEADER) { user.authentication_token }
  end

  def auth_parameters
    parameter name: TOKEN_HEADER.to_s, in: :header, type: :string, required: true
    parameter name: EMAIL_HEADER.to_s, in: :header, type: :string, required: true
  end

  def auth_security
    security [ { x_auth_token: [], x_auth_email: [] } ]
  end
end

RSpec.configure do |config|
  config.include AuthHelper, type: :controller
  config.extend AuthHelper, type: :request
end
