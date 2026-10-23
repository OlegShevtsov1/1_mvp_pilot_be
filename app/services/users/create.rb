module Users
  class Create < ApplicationService
    attr_reader :params, :user, :errors

    def initialize(params)
      @params = params
      @errors = []
    end

    def call
      @user = User.new(user_params)

      ActiveRecord::Base.transaction do
        if @user.save
          @user = User.find(@user.id)
          @token = Auth::IssueTokens.call(@user)
        else
          @errors = @user.errors.full_messages
        end
      end

      self
    end

    def token_fields
      return {} unless @token

      { access_token: @token.plaintext_token, refresh_token: @token.plaintext_refresh_token,
        expires_in: @token.expires_in }
    end

    def success?
      @errors.empty?
    end

    def status_error
      :unprocessable_entity
    end

    private

    def user_params
      params.require(:user).permit(:email, :password, :password_confirmation)
    end
  end
end
