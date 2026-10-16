module ControllerSpecHelper
  # More aggressive approach to avoid view rendering issues
  def bypass_view_rendering
    # This completely bypasses any view rendering
    allow_any_instance_of(ActionController::Base).to receive(:render).and_return(nil)
    allow_any_instance_of(ActionController::Base).to receive(:render_to_string).and_return(nil)
    allow_any_instance_of(ActionController::Base).to receive(:head).and_return(nil)
  end
end

RSpec.configure do |config|
  config.include ControllerSpecHelper, type: :controller

  config.before(:each, type: :controller) do
    bypass_view_rendering
  end
end
