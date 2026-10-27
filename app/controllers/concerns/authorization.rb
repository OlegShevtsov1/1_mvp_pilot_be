module Authorization
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::RecordNotFound, with: :render_record_not_found
    rescue_from CanCan::AccessDenied do |exception|
      render json: { error: 'You are not authorized to perform this action' }, status: :forbidden
    end
  end

  private

  def render_record_not_found
    render json: { error: 'Not Found' }, status: :not_found
  end
end
