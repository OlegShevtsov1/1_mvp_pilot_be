module Projects
  class Index < ApplicationService
    attr_reader :user, :projects, :errors

    CACHE_EXPIRATION = 15.minutes

    def initialize(user, params = {})
      @user = user
      @params = params
      @errors = []
    end

    def call
      @projects = fetch_cached_projects

      self
    end

    def success?
      @errors.empty?
    end

    private

    def fetch_cached_projects
      Rails.cache.fetch(cache_key, expires_in: CACHE_EXPIRATION) do
        fetch_projects
      end
    end

    def fetch_projects
      build_query.includes(:user, :tasks)
    end

    def build_query
      apply_status_filter(base_query)
    end

    def base_query
      @user.projects
    end

    def apply_status_filter(query)
      return query unless @params[:task_status].present?

      query.joins(:tasks)
           .where(tasks: { status: @params[:task_status] })
           .distinct
    end

    def cache_key
      [
        base_key,
        projects_signature,
        filter_signature,
        version_signature
      ].compact.join(':')
    end

    def base_key
      [ 'projects', @user.id ].join(':')
    end

    def projects_signature
      count = @user.projects.count
      latest_update = @user.projects.maximum(:updated_at) || 'none'

      "stats:count=#{count}:updated=#{latest_update}"
    end

    def filter_signature
      "filter:#{@params[:task_status]}" if @params[:task_status].present?
    end

    def version_signature
      'v1'
    end
  end
end
