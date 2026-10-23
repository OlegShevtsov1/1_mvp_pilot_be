class Api::V1::UsersController < Api::V1::BaseController
  skip_before_action :authenticate_user_from_token!, only: [ :create ]

  SIGN_UP_LIMIT = 5
  SIGN_UP_WINDOW = 1.hour

  # Counted per source before anything is checked, so refused sign-ups count too (PRD §6: limits email probing).
  rate_limit to: SIGN_UP_LIMIT, within: SIGN_UP_WINDOW, only: :create, unless: :deploy_smoke_check?,
             by: -> { request.remote_ip }, store: ErrorsController::RateLimitStore,
             with: -> { refuse_sign_up }

  def create
    service = Users::Create.call(params)

    if service.success?
      render json: {
        status: 'success',
        message: 'User created successfully',
        data: {
          user_id: service.user.id,
          email: service.user.email,
          authentication_token: service.user.authentication_token,
          **service.token_fields
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

  def refuse_sign_up
    response.set_header('Retry-After', SIGN_UP_WINDOW.to_i.to_s)
    render json: {
      status: 'error',
      message: 'User could not be created',
      errors: [ 'Too many sign-ups from this address. Wait an hour before trying again' ]
    }, status: :too_many_requests
  end

  # The deploy smoke signs up on every dev deploy; presenting SMOKE_TOKEN keeps it out of the sign-up limit.
  def deploy_smoke_check?
    SmokeToken.presented?(request)
  end

  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation)
  end
end
