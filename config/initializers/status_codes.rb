# TODO: fasterer issue

# Register unprocessable_entity status code
ActionDispatch::ExceptionWrapper.rescue_responses['ActionController::ParameterMissing'] = :unprocessable_entity

# Make sure unprocessable_entity is available in tests
Rack::Utils::SYMBOL_TO_STATUS_CODE[:unprocessable_entity] = 422
