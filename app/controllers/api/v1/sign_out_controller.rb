class Api::V1::SignOutController < Api::V1::BaseController
  def create
    Auth::RevokeDevice.call(current_user, Doorkeeper::OAuth::Token.from_bearer_authorization(request))
    head :no_content
  end
end
