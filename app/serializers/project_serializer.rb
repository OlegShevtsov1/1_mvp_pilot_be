class ProjectSerializer < BaseSerializer
  attributes :id, :name, :description

  # Plain hashes, not belongs_to/has_many: a serializer per task made the dashboard list of 50 projects and 500 tasks
  # take ~1 s (PILOT-414). The fields come from UserSerializer and TaskSerializer, so the nested objects keep their
  # fields (associations excluded, as before).
  attribute(:user) { UserSerializer._attributes.index_with { |key| object.user.read_attribute_for_serialization(key) } }
  attribute(:tasks) do
    object.tasks.map { |task| TaskSerializer._attributes.index_with { |key| task.read_attribute_for_serialization(key) } }
  end
end
