module Tasks
  class Update < ApplicationService
    attr_reader :user, :project, :task, :params, :errors

    def initialize(user, project, task, params)
      @user = user
      @project = project
      @task = task
      @params = params
      @errors = []
    end

    def call
      if @task.update(task_params)
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
