class Api::V1::ProjectsController < Api::V1::BaseController
  include Authorization

  load_and_authorize_resource

  def index
    service = Projects::Index.call(current_user, params.permit(:task_status))

    render json: {
      data: ActiveModelSerializers::SerializableResource.new(
        service.projects, each_serializer: ProjectSerializer
      )
    }
  end

  def show
    service = Projects::Show.call(current_user, @project)

    render json: {
      data: ActiveModelSerializers::SerializableResource.new(
        service.project, serializer: ProjectSerializer
      )
    }
  end

  def create
    service = Projects::Create.call(current_user, params)

    if service.success?
      render json: {
        data: ActiveModelSerializers::SerializableResource.new(
          service.project, serializer: ProjectSerializer
        )
      }, status: :created
    else
      render json: { errors: service.errors }, status: service.status_error
    end
  end

  def update
    service = Projects::Update.call(current_user, @project, params)

    if service.success?
      render json: {
        data: ActiveModelSerializers::SerializableResource.new(
          service.project, serializer: ProjectSerializer
        )
      }
    else
      render json: { errors: service.errors }, status: service.status_error
    end
  end

  def destroy
    service = Projects::Delete.call(current_user, @project)

    if service.success?
      head :no_content
    else
      render json: { errors: service.errors }, status: service.status_error
    end
  end

  private

  def project_params
    params.require(:project).permit(:name, :description)
  end
end
