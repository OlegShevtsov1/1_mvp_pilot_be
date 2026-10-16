class Api::V1::UsersController < Api::V1::BaseController
  skip_before_action :authenticate_user_from_token!, only: [ :create ]

  def create
    service = Users::Create.call(params)

    if service.success?
      render json: {
        status: 'success',
        message: 'User created successfully',
        data: {
          user_id: service.user.id,
          email: service.user.email,
          authentication_token: service.user.authentication_token
        }
      }, status: :created
    else
      render json: {
        status: 'error',
        message: 'User could not be created',
        errors: service.errors
      }, status: :unprocessable_entity
    end
  end

  def me
    service = Users::Me.call(current_user)

    render json: {
      status: 'success',
      message: 'User profile',
      data: {
        user_id: service.user.id,
        email: service.user.email
      }
    }
  end

  private

  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation)
  end
end
