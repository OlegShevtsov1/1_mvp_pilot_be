require 'rails_helper'

RSpec.describe 'Dashboard list cost (GET /api/v1/projects)', type: :request do
  let(:user) { create(:user) }
  let(:headers) do
    { 'Authorization' => "Bearer #{create(:oauth_access_token, resource_owner_id: user.id).plaintext_token}" }
  end
  let(:serializer_classes) { [ ProjectSerializer, TaskSerializer, UserSerializer ] }

  def seed(projects:, tasks:)
    create_list(:project, projects, user: user).each { |project| create_list(:task, tasks, project: project) }
  end

  # Clears the list cache so every call is a miss, and creates the token before counting so its INSERT is not counted.
  def list_cost
    Rails.cache.clear
    headers
    queries = 0
    built = 0
    serializer_classes.each do |klass|
      allow(klass).to receive(:new).and_wrap_original do |original, *args, **kwargs|
        built += 1
        original.call(*args, **kwargs)
      end
    end
    counter = ->(*, payload) { queries += 1 unless payload[:name] == 'SCHEMA' || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { get '/api/v1/projects', headers: headers }
    expect(response).to have_http_status(:ok)
    { queries: queries, serializers: built }
  end

  it 'runs the same number of queries whatever the number of projects and tasks' do
    seed(projects: 1, tasks: 1)
    small = list_cost
    seed(projects: 4, tasks: 5)
    expect(list_cost[:queries]).to eq(small[:queries])
  end

  it 'builds one serializer per project, none per task or for the owner' do
    seed(projects: 3, tasks: 4)
    expect(list_cost[:serializers]).to eq(3)
  end

  it 'renders each project with its owner and its tasks and nothing else' do
    seed(projects: 2, tasks: 2)
    list_cost
    expected = user.projects.includes(:tasks).sort_by(&:id).map do |project|
      {
        'id' => project.id, 'name' => project.name, 'description' => project.description,
        'user' => { 'id' => user.id, 'email' => user.email },
        'tasks' => project.tasks.sort_by(&:id).map do |task|
          { 'id' => task.id, 'name' => task.name, 'description' => task.description, 'status' => task.status }
        end
      }
    end
    data = response.parsed_body['data'].sort_by { |project| project['id'] }
    data.each { |project| project['tasks'].sort_by! { |task| task['id'] } }
    expect(data).to eq(expected)
  end
end
