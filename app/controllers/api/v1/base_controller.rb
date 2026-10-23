class Api::V1::BaseController < ApplicationController
  include ApiExceptionHandler

  before_action :authenticate_user_from_token!
  attr_reader :current_user

  def current_ability
    @current_ability ||= Ability.new(current_user)
  end

  private

  # A bearer access token decides alone; only a request without one falls back to the legacy pair (ADR-0005).
  def authenticate_user_from_token!
    bearer = Doorkeeper::OAuth::Token.from_bearer_authorization(request)
    @current_user = bearer.present? ? user_from_bearer(bearer) : user_from_legacy_headers

    render json: { error: 'Not Authorized' }, status: :unauthorized unless @current_user
  end

  def user_from_bearer(token)
    access_token = OauthAccessToken.by_token(token)
    User.find_by(id: access_token.resource_owner_id) if access_token&.accessible?
  end

  def user_from_legacy_headers
    return unless Auth::LegacyUsage.enabled?

    user = BaseApplication::Authenticate.call(request.headers)[:current_user]
    Auth::LegacyUsage.record(user) if user && !SmokeToken.presented?(request)
    user
  end
end
