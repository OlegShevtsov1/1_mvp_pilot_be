RSpec.describe Tasks::Index do
  let(:user) { create(:user) }
  let(:project) { create(:project, user: user) }
  let!(:tasks) { create_list(:task, 3, project: project) }

  describe '#call' do
    let(:service) { described_class.new(user, project) }

    subject { service.call }

    it 'returns all tasks for the project' do
      expect(subject.tasks.count).to eq(3)
      expect(subject.tasks).to match_array(project.tasks)
    end

    it 'includes the project association for each task' do
      subject.tasks.each do |task|
        expect(task.project).to eq(project)
      end
    end

    it 'returns success' do
      expect(subject.success?).to be_truthy
    end
  end

  describe 'caching' do
    let(:service) { described_class.new(user, project) }
    let(:cache_key) { service.send(:cache_key) }

    before do
      allow(Rails.cache).to receive(:fetch).and_call_original
    end

    it 'uses Rails cache' do
      expect(Rails.cache).to receive(:fetch).with(String, hash_including(:expires_in))
      service.call
    end

    it 'builds unique cache key based on project id' do
      key = service.send(:cache_key)
      expect(key).to include(project.id.to_s)
    end

    it 'includes the count of tasks in the cache key' do
      key = service.send(:cache_key)
      expect(key).to include("stats:count=#{project.tasks.count}")
    end

    it 'includes the latest task update timestamp in the cache key' do
      latest_update = project.tasks.maximum(:updated_at)
      key = service.send(:cache_key)
      expect(key).to include("stats:count=#{project.tasks.count}:updated=#{latest_update || 'none'}")
    end

    it 'returns cached results on subsequent calls' do
      cached_tasks = double("tasks")
      cache_key = service.send(:cache_key)

      expect(Rails.cache).to receive(:fetch).with(cache_key, hash_including(:expires_in)).and_yield
      expect(service).to receive(:fetch_tasks).once.and_return(cached_tasks)

      service.call

      allow(Rails.cache).to receive(:fetch).with(cache_key, hash_including(:expires_in))
                                          .and_return(cached_tasks)

      service.call
    end

    it 'invalidates cache when a task is updated' do
      service1 = described_class.new(user, project)
      first_tasks_signature = service1.send(:tasks_signature)

      task = project.tasks.first
      new_time = Time.now + 1.day
      task.update_column(:updated_at, new_time)

      service2 = described_class.new(user, project)
      second_tasks_signature = service2.send(:tasks_signature)

      expect(second_tasks_signature).not_to eq(first_tasks_signature)
    end

    it 'invalidates cache when a task is added' do
      service1 = described_class.new(user, project)

      first_key = service1.send(:cache_key)
      service1.call

      create(:task, project: project)

      service2 = described_class.new(user, project)
      second_key = service2.send(:cache_key)

      expect(second_key).not_to eq(first_key)
    end

    it 'invalidates cache when a task is removed' do
      service1 = described_class.new(user, project)

      first_key = service1.send(:cache_key)
      service1.call

      project.tasks.first.destroy

      service2 = described_class.new(user, project)
      second_key = service2.send(:cache_key)

      expect(second_key).not_to eq(first_key)
    end
  end
end
