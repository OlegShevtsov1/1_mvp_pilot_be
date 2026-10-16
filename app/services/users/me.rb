module Users
  class Me < ApplicationService
    attr_reader :user, :errors

    def initialize(user)
      @user = user
      @errors = []
    end

    def call
      self
    end

    def success?
      @errors.empty?
    end

    def status_error
      :unprocessable_entity
    end
  end
end
