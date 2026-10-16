module ApiExceptionHandler
  extend ActiveSupport::Concern

  included do
    rescue_from ApiExceptions::NotAuthorizedError, with: :render_forbidden
    rescue_from ApiExceptions::ResourceNotFoundError, with: :render_not_found
  end

  private

  def render_forbidden(exception)
    render json: { error: exception.message }, status: :forbidden
  end

  def render_not_found(exception)
    render json: { error: exception.message }, status: :not_found
  end
end
