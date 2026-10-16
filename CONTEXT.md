---
status: Living
updated_at: "2026-10-15"
---

# Domain Context — 1_mvp_pilot_be

## Glossary

- access token — the secret string a user presents, together with their email, to prove who they are on every
  request. NOT a password: it is issued by the system at sign-up and is never chosen by the user.
- error report — an error that happened in the frontend and is forwarded through this system to error tracking.
  NOT an error of this system itself: those are reported directly, without the forwarding step.
- health check — the public answer that the running system is up and which release it runs. NOT a measure of
  correctness: it says nothing about whether the features work.
- project — a named piece of work with a description that a user creates to group their tasks. NOT shared: a
  project has exactly one owner and nobody else can see it.
- project owner — the user who created a project and the only one who can see, change or delete it and its tasks.
  NOT a role that can be granted: ownership comes only from creating the project.
- release — the exact code version that is running, identified by its commit. NOT a published version number or
  tag: every deployed commit is a release.
- sign-in — exchanging email and password for the user's access token. NOT a server-side session: nothing is
  remembered between requests.
- smoke event — a deliberate error triggered by the operator to prove that a deployment's errors reach error
  tracking. NOT a real fault: it carries a marker so it can be found and ignored.
- task — one unit of work inside a project, with a name, a description and a status. NOT independent: a task
  cannot exist outside its project.
- task status — where a task stands: not started, in progress or completed. NOT free text: only these three values
  exist.
- user — a person identified by a unique email who owns projects. NOT an operator or administrator: every user has
  the same rights over their own data only.

## Invariants

- A task always belongs to exactly one project.
- A user can only ever see and change their own projects and the tasks of those projects.
- A project that still has tasks can never be deleted.
- A task status is always one of not started, in progress or completed.
