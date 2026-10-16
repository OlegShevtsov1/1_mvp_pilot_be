module Users
  class Create < ApplicationService
    attr_reader :params, :user, :errors

    def initialize(params)
      @params = params
      @errors = []
    end

    def call
      @user = User.new(user_params)

      if @user.save
        @user = User.find(@user.id)
      else
        @errors = @user.errors.full_messages
      end

      self
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
