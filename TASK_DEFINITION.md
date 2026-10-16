# Test Assignment for RoR Developer: Project Management System

You are required to implement a simple Project Management System, allowing users to create, edit, and track projects and their tasks. The system should have a simple RESTful API for interaction with the frontend.

## Primary Requirements

### Database Modelling:

- Create `Project` and `Task` models.
- Projects should have a `title` and `description`.
- Tasks should have a `title`, `description`, `status` (new, in progress, completed) and a reference to project.
- Implement associations between projects and tasks.

### API Implementation:

- Develop an API for creating, updating, deleting, and viewing `projects` and `tasks`.
- Authenticate user via API (you can use `Devise` and `Simple token authentication`).

### Active Record Queries:

- Implement queries to obtain projects with all their tasks.
- Implement queries to filter tasks based on their status.

### Query and Code Optimization:

- Ensure your database queries are optimized (Use `includes`, `select`, `where`, etc).
- Implement caching for frequently used queries to boost performance.
- Adhere to Rails best practices for code optimization (DRY, SOLID principles).

### Writing Tests:

- Write `unit` and `integration` tests to validate functionality of models and API.
- Use `RSpec` or `Minitest` for writing tests.

### Additional Requirements:

- Code should be clean and well-organized.
- Use Git for maintaining version/change history.
- Pay attention to API security.

## Result:

Your task is to provide a link to your Git repository with the project and instructions on how to run it.
