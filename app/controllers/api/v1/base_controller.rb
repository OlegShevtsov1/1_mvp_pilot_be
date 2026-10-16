class Api::V1::BaseController < ApplicationController
  include ApiExceptionHandler

  before_action :authenticate_user_from_token!
  attr_reader :current_user

  def current_ability
    @current_ability ||= Ability.new(current_user)
  end

  private

  def authenticate_user_from_token!
    authentication = BaseApplication::Authenticate.call(request.headers)
    @current_user = authentication[:current_user]

    render json: { error: 'Not Authorized' }, status: :unauthorized unless @current_user
  end
end
