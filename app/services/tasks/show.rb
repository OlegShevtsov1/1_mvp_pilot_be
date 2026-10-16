module Tasks
  class Show < ApplicationService
    attr_reader :user, :project, :task, :errors

    def initialize(user, project, task)
      @user = user
      @project = project
      @task = task
      @errors = []
    end

    def call
      @task = Task.includes(:project).find(@task.id)
      self
    end

    def success?
      @errors.empty?
    end

    def status
      :ok
    end
  end
end
