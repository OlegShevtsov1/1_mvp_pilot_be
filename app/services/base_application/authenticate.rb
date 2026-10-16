module BaseApplication
  class Authenticate < ApplicationService
    attr_reader :headers, :current_user

    def initialize(headers)
      @headers = headers
      @current_user = nil
    end

    def call
      authenticate_user_from_token
      { success: user_authenticated?, current_user: @current_user }
    end

    private

    def authenticate_user_from_token
      email = headers['X-User-Email']
      token = headers['X-User-Token']

      user = User.find_by(email: email)

      if user && token.present? && user.authentication_token.present? &&
         Devise.secure_compare(user.authentication_token, token)
        @current_user = user
      end
    end

    def user_authenticated?
      !@current_user.nil?
    end
  end
end
