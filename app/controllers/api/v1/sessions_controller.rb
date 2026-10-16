class Api::V1::SessionsController < Api::V1::BaseController
  skip_before_action :authenticate_user_from_token!, only: [ :create ]

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
      render json: {
        status: 'error',
        message: service.errors.first
      }, status: service.status_error
    end
  end
end
