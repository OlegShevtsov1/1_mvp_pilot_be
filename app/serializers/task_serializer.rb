class TaskSerializer < ActiveModel::Serializer
  attributes :id, :name, :description, :status

  belongs_to :project
end
