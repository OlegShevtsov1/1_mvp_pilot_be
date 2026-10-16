class UserSerializer < BaseSerializer
  attributes :id, :email

  has_many :projects
end
