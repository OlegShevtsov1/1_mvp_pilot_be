module Tasks
  class Index < ApplicationService
    attr_reader :user, :project, :tasks

    CACHE_EXPIRATION = 15.minutes

    def initialize(user, project)
      @user = user
      @project = project
    end

    def call
      @tasks = fetch_cached_tasks
      self
    end

    def success?
      true
    end

    def status
      :ok
    end

    private

    def fetch_cached_tasks
      Rails.cache.fetch(cache_key, expires_in: CACHE_EXPIRATION) do
        fetch_tasks
      end
    end

    def fetch_tasks
      @project.tasks.includes(:project).all
    end

    def cache_key
      [
        base_key,
        tasks_signature,
        version_signature
      ].compact.join(':')
    end

    def base_key
      [ 'tasks', @project.id ].join(':')
    end

    def tasks_signature
      count = @project.tasks.count
      latest_update = @project.tasks.maximum(:updated_at) || 'none'

      "stats:count=#{count}:updated=#{latest_update}"
    end

    def version_signature
      'v1'
    end
  end
end
