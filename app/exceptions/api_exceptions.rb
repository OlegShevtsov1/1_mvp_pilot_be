module ApiExceptions
  # Base exception for all API-related errors
  class BaseError < StandardError; end

  # Exception for unauthorized access attempts
  class NotAuthorizedError < BaseError
    def initialize(msg = 'You are not authorized to perform this action')
      super
    end
  end

  # Exception for resource not found errors
  class ResourceNotFoundError < BaseError
    def initialize(resource = 'Resource')
      super("#{resource} not found")
    end
  end
end
