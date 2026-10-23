class Api::V1::SessionsController < Api::V1::BaseController
  include FailedSignInLimited

  skip_before_action :authenticate_user_from_token!, only: [ :create ]
  around_action :limit_failed_sign_ins, only: :create

  def create
    service = Sessions::Create.call(params)

    if service.success?
      render json: {
        status: 'success',
        message: 'Signed in successfully',
        data: {
          user_id: service.user.id,
          email: service.user.email,
          authentication_token: service.user.authentication_token
        }
      }
    else
      failed_sign_in!
      render json: {
        status: 'error',
        message: service.errors.first
      }, status: service.status_error
    end
  end
end
