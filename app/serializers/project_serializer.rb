class ProjectSerializer < BaseSerializer
  attributes :id, :name, :description

  belongs_to :user
  has_many :tasks
end
