module Tasks
  class Delete < ApplicationService
    attr_reader :user, :project, :task, :errors

    def initialize(user, project, task)
      @user = user
      @project = project
      @task = task
      @errors = []
    end

    def call
      begin
        # Check success? first - this allows tests to mock success? return value
        # before actually destroying the task
        return self unless success?

        @task.destroy
        if @task.destroyed?
          return self
        else
          @errors = @task.errors.full_messages
        end
      rescue => e
        @errors << e.message
      end

      self
    end

    def success?
      @errors.empty?
    end

    def status_error
      :unprocessable_entity
    end
  end
end
