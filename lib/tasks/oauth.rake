namespace :oauth do
  desc 'Create the public web client whose uid is OAUTH_CLIENT_ID; does nothing when it is unset'
  task web_application: :environment do
    uid = ENV.fetch('OAUTH_CLIENT_ID', '').strip
    next if uid.empty?

    Doorkeeper::Application.find_or_create_by!(uid:) do |application|
      application.name = 'todolist web'
      application.confidential = false
    end
  end
end
