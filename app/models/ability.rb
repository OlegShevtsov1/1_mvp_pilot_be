class Ability
  include CanCan::Ability

  def initialize(user)
    return unless user.present?

    can :manage, Project, user_id: user.id
    can :manage, Task, project: { user_id: user.id }
  end
end
