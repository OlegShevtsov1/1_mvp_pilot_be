class Task < ApplicationRecord
  belongs_to :project, counter_cache: true, touch: true

  enum status: { not_started: 'not_started', in_progress: 'in_progress', completed: 'completed' }

  validates :name, presence: true
  validates :description, presence: true
  validates :status, presence: true, inclusion: { in: statuses.keys }
end
