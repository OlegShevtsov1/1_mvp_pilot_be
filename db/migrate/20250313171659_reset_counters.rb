class ResetCounters < ActiveRecord::Migration[7.2]
  def up
    # Reset projects_count for users
    User.find_each do |user|
      User.reset_counters(user.id, :projects)
    end

    # Reset tasks_count for projects
    Project.find_each do |project|
      Project.reset_counters(project.id, :tasks)
    end
  end

  def down
    # No rollback needed
  end
end
