module Authorization
  extend ActiveSupport::Concern

  included do
    rescue_from CanCan::AccessDenied do |exception|
      render json: { error: 'You are not authorized to perform this action' }, status: :forbidden
    end
  end

  def authorize_project!(project)
    authorize! :manage, project
  end
end
