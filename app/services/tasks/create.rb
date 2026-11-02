module Tasks
  class Create < ApplicationService
    attr_reader :user, :project, :params, :task, :errors

    def initialize(user, project, params)
      @user = user
      @project = project
      @params = params
      @errors = []
    end

    def call
      @task = @project.tasks.build(task_params)

      if @task.save
        @task = Task.includes(:project).find(@task.id)
      else
        @errors = @task.errors.full_messages
      end

      self
    end

    def success?
      @errors.empty?
    end

    def status_error
      :unprocessable_entity
    end

    private

    def task_params
      params.require(:task).permit(:name, :description, :status)
    end
  end
end
