# Git

- Work on a feature branch; changes reach `main` only through a reviewed, squash-merged pull request.
- Never force-push, never `git reset --hard`, never delete or move a tag. The `mvp-sdlc` hooks block these; if a hook
  blocks you, change the approach instead of looking for a way around it.
- Commit subjects follow Conventional Commits (`feat`, `fix`, `test`, `refactor`, `docs`, `chore`, `ci`).
- A task from `tasks/tasks.json` is two or three commits: `test(...)` with the failing tests, `feat(...)` or
  `fix(...)` that makes them pass, and `refactor(...)` if there is cleanup to do. Each carries the trailers
  `SDLC-Task: <id>` and `SDLC-AC: <AC ids>`.
- Stage files by name. Never commit `.env*` files, `config/master.key`, `.claude/*.local.md` or build output.
- A PR whose `Type:` is `feat` or `fix` adds an entry under `[Unreleased]` in `CHANGELOG.md` (`changelog-check`;
  label `skip-changelog` only for trivia).
- Release pull request `develop` → `main`: title `PILOT-<n>: Release vX.Y.Z` (the release's own card, never
  `PILOT-0`; decision 91); its body has `## Changelog` followed by the full `## [X.Y.Z]` section of
  `CHANGELOG.md`, pasted verbatim. The release-prep pull request `PILOT-<n>: Release X.Y.Z changelog` writes
  that section first.
- Never move or delete a published `v*` tag; the repository's `.githooks/pre-push` refuses it
  (`git config core.hooksPath .githooks`).
- When a task is done, set its row in `docs/features/<slug>/tasks/tracker.md` and its `status` in `tasks.json` to
  `done` in the same pull request.
