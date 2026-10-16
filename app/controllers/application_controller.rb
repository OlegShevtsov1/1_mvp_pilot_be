class ApplicationController < ActionController::API
  before_action :authenticate_user!

  def authenticate_user!
    # This will be overridden in the base controller
  end
end
