# The pipeline-only secret deploy checks present in X-Smoke-Token; a blank SMOKE_TOKEN never matches.
module SmokeToken
  module_function

  def presented?(request)
    expected = ENV['SMOKE_TOKEN']
    expected.present? && ActiveSupport::SecurityUtils.secure_compare(request.headers['X-Smoke-Token'].to_s, expected)
  end
end
