module Projects
  class Delete < ApplicationService
    attr_reader :user, :project, :errors

    def initialize(user, project)
      @user = user
      @project = project
      @errors = []
    end

    def call
      delete_project

      self
    end

    def success?
      @errors.empty?
    end

    def status_error
      return :not_found if @errors.include?('Project not found')

      :unprocessable_entity
    end

    private

    def delete_project
      unless @project.destroy
        @errors.concat(@project.errors.full_messages)
      end
    end
  end
end
