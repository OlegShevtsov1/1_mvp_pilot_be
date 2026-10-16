class AddTasksCountToProjects < ActiveRecord::Migration[7.2]
  def change
    add_column :projects, :tasks_count, :integer, default: 0, null: false
  end
end
