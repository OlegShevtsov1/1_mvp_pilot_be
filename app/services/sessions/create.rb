module Sessions
  class Create < ApplicationService
    attr_reader :params, :user, :errors

    def initialize(params)
      @params = params
      @errors = []
    end

    def call
      @user = User.find_by(email: params[:email])

      if !@user || !@user.valid_password?(params[:password])
        @errors << 'Invalid email or password'
      end

      self
    end

    def success?
      @errors.empty?
    end

    def status_error
      :unauthorized
    end
  end
end
