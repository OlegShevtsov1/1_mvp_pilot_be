module Projects
  class Update < ApplicationService
    attr_reader :user, :project, :params, :errors

    def initialize(user, project, params)
      @user = user
      @project = project
      @params = params
      @errors = []
    end

    def call
      update_project

      @project = Project.includes(:user, :tasks).find(@project.id) if @project.persisted? && @errors.empty?

      self
    end

    def success?
      @errors.empty?
    end

    def status_error
      :unprocessable_entity
    end

    private

    def update_project
      unless @project.update(project_params)
        @errors = @project.errors.full_messages
      end
    end

    def project_params
      params.require(:project).permit(:name, :description)
    end
  end
end
