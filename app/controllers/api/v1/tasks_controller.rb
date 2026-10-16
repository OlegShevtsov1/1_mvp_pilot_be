class Api::V1::TasksController < Api::V1::BaseController
  include Authorization

  load_and_authorize_resource :project
  load_and_authorize_resource :task, through: :project

  def index
    service = Tasks::Index.call(current_user, @project)

    render json: {
      data: ActiveModelSerializers::SerializableResource.new(
        service.tasks, each_serializer: TaskSerializer
      )
    }
  end

  def show
    service = Tasks::Show.call(current_user, @project, @task)

    render json: {
      data: ActiveModelSerializers::SerializableResource.new(
        service.task, serializer: TaskSerializer
      )
    }
  end

  def create
    begin
      service = Tasks::Create.call(current_user, @project, params)

      if service.success?
        render json: {
          data: ActiveModelSerializers::SerializableResource.new(
            service.task, serializer: TaskSerializer
          )
        }, status: :created
      else
        render json: { errors: service.errors }, status: service.status_error
      end
    rescue ArgumentError => e
      render json: { errors: [ e.message ] }, status: :unprocessable_entity
    end
  end

  def update
    service = Tasks::Update.call(current_user, @project, @task, params)

    if service.success?
      render json: {
        data: ActiveModelSerializers::SerializableResource.new(
          service.task, serializer: TaskSerializer
        )
      }
    else
      render json: { errors: service.errors }, status: service.status_error
    end
  end

  def destroy
    service = Tasks::Delete.call(current_user, @project, @task)

    if service.success?
      head :no_content
    else
      render json: { errors: service.errors }, status: service.status_error
    end
  end

  private

  def task_params
    params.require(:task).permit(:name, :description, :status)
  end
end
