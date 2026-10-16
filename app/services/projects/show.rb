module Projects
  class Show < ApplicationService
    attr_reader :user, :project, :errors

    def initialize(user, project)
      @user = user
      @project = project
      @errors = []
    end

    def call
      @project = Project.includes(:user, :tasks).find(@project.id) if @project.persisted?

      self
    end

    def success?
      @errors.empty?
    end

    def status
      return :not_found if @errors.include?('Project not found')

      :unprocessable_entity
    end
  end
end
