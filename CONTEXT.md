---
status: Living
updated_at: "2026-10-22"
---

# Domain Context — 1_mvp_pilot_be

## Glossary

- access token — the secret a user's device receives at sign-in and presents on every request to prove who they
  are; it can be revoked on its own. NOT the legacy access token: one access token belongs to one sign-in, not to
  the account.
- error report — an error that happened in the frontend and is forwarded through this system to error tracking.
  NOT an error of this system itself: those are reported directly, without the forwarding step.
- Google sign-in — signing in by proving ownership of a Google account whose email becomes the user's email; if a
  user with that email already exists, the Google account is linked to them and their password and all existing
  access are cancelled. NOT sign-in: no password is exchanged.
- health check — the public answer that the running system is up and which release it runs. NOT a measure of
  correctness: it says nothing about whether the features work.
- legacy access token — the single, never-expiring secret each user has from before Google sign-in existed, sent
  together with the email; accepted only until the frontend has switched and none was seen for 7 days. NOT an
  access token: it belongs to the account, not to one sign-in, and cannot be revoked per device.
- project — a named piece of work with a description that a user creates to group their tasks. NOT shared: a
  project has exactly one owner and nobody else can see it.
- project owner — the user who created a project and the only one who can see, change or delete it and its tasks.
  NOT a role that can be granted: ownership comes only from creating the project.
- release — the exact code version that is running, identified by its commit. NOT a published version number or
  tag: every deployed commit is a release.
- sign-in — exchanging email and password for the user's access token. NOT a server-side session: nothing is
  remembered between requests.
- sign-out — ending the access of the current device by revoking its access token. NOT signing out everywhere:
  other devices keep their access.
- smoke event — a deliberate error triggered by the operator to prove that a deployment's errors reach error
  tracking. NOT a real fault: it carries a marker so it can be found and ignored.
- task — one unit of work inside a project, with a name, a description and a status. NOT independent: a task
  cannot exist outside its project.
- task status — where a task stands: not started, in progress or completed. NOT free text: only these three values
  exist.
- user — a person identified by a unique email who owns projects. NOT an operator or administrator: every user has
  the same rights over their own data only.
- visitor — a person using the app who is not signed in, typically on the landing page or the sign-up and sign-in
  screens. NOT a user: a visitor has no access to any projects or tasks until they sign up or sign in.

## Invariants

- A task always belongs to exactly one project.
- A user can only ever see and change their own projects and the tasks of those projects.
- A project that still has tasks can never be deleted.
- A task status is always one of not started, in progress or completed.
