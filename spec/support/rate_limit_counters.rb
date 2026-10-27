# The rate-limit counters outlive an example; leftovers from one spec's wrong passwords would refuse sign-ins in
# another.
RSpec.configure do |config|
  %i[request controller].each do |type|
    config.before(:each, type:) do
      Rails.cache.clear
      ErrorsController::RateLimitStore::FALLBACK.clear
    end
  end
end
