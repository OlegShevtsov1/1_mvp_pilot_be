# /oauth/token with the failed sign-in limit in front of the password grant (AC-10, ADR-0009).
class Oauth::TokensController < Doorkeeper::TokensController
  include FailedSignInLimited

  around_action :limit_failed_sign_ins, only: :create, if: -> { params[:grant_type] == 'password' }
end
