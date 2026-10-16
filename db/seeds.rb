# Create example user
example_user_params = {
  email: Examples::UserData.email,
  password: Examples::UserData.password,
  password_confirmation: Examples::UserData.password
}
User.create(example_user_params) until User.find_by(email: Examples::UserData.email)
example_user = User.find_by(email: Examples::UserData.email)

# Create example project
example_project_params = {
  name: Examples::ProjectData.name,
  description: Examples::ProjectData.description,
  user_id: example_user.id
}
Project.create(example_project_params) until Project.find_by(name: Examples::ProjectData.name)

# Create example task for the example project
example_project = Project.find_by(name: Examples::ProjectData.name)
if example_project
  example_task_params = {
    name: Examples::TaskData.name,
    description: Examples::TaskData.description,
    status: Examples::TaskData.status,
    project_id: example_project.id
  }
  Task.create(example_task_params) until Task.find_by(name: Examples::TaskData.name, project_id: example_project.id)
end
