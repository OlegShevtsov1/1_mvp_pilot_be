# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). A pull request whose `Type:` is `feat` or `fix` adds
its entry under `[Unreleased]` (checked by `changelog-check`); a release moves those entries into a new
`## [X.Y.Z] - YYYY-MM-DD` section and keeps the six empty categories below as the template. See README
"Releases and hotfixes".

## [Unreleased]

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.3.0] - 2026-10-23

### Added

- A Google ID token verifier for the coming Google sign-in: it accepts only a token Google signed for our
  client, unexpired, with a verified email, and caches Google's signing keys, refetching them for an unknown key
  id (PILOT-222, T8).
- Database tables `oauth_applications` and `oauth_access_tokens` for per-device access and refresh tokens
  (todolist, PILOT-222).
- Email and password sign-in at `POST /oauth/token` (Doorkeeper password grant): one access token per device,
  valid one hour, and a rotating refresh token refused after 30 days; `POST /oauth/revoke`; the container creates
  the public web client from `OAUTH_CLIENT_ID` (todolist, PILOT-230).
- Database tables `identities` (the Google account linked to a user) and `legacy_token_uses` (daily count of
  legacy access token use per user) (todolist, PILOT-229, T2). Nothing reads them until the models and
  authentication changes ship.
- Sign-up also signs the device in: `POST /api/v1/users` returns its own `access_token`, `refresh_token` and
  `expires_in` next to the legacy `authentication_token`; more than 5 sign-ups an hour from one address are refused
  with 429 and `Retry-After`; a taken email says to sign in instead (todolist, PILOT-233).
- Models for the Google account linked to a user and the daily legacy access token count; a user who signed in
  with Google may have no password, and deleting a user also deletes their access tokens, Google link and
  legacy-use rows (todolist, PILOT-231, T4).
- API requests accept a per-device bearer access token (`Authorization: Bearer …`); the legacy email and token
  headers keep working until the cutoff, each use is counted per user and day, and `LEGACY_AUTH_ENABLED=false`
  refuses them (todolist, PILOT-232, T5).
- Google sign-in at `POST /oauth/token` (`grant_type=google_id_token`): a Google-verified email with no user
  creates one; the email of an existing user (ignoring capital letters) links Google to them and cancels their
  password, every access and refresh token and the legacy access token; anything Google does not vouch for creates
  and links nothing (todolist, PILOT-236, T9).
- Sign-out at `POST /api/v1/sign_out`: with an access token it ends this device's access and refresh token while
  other devices keep working; with the legacy headers it rotates the legacy access token, which then stops working
  on every device that used it (todolist, PILOT-237, T10).
- Sign-in is capped per address: after 10 failed sign-ins in a minute, `POST /oauth/token` (password) and
  `POST /api/v1/sign_in` answer 429 with `Retry-After: 60` without checking the password; failures at both count
  together, successful sign-ins are not counted, and the address comes from kamal-proxy's forwarded header only
  when the request comes from the proxy (todolist, PILOT-234, T7).

### Changed

- Another user's project or task now answers 404 `{ "error": "Not Found" }`, exactly like a missing one, instead
  of 403 on show, change, delete and the task routes under it; a missing project or task answers the same JSON body
  (todolist, PILOT-238, T11, ADR-0007).

### Fixed

- `bin/wait-dev-deploy` reads the Gate log of a Dev Deploy run titled just `Dev Deploy` only after the run
  completed and keeps polling it until then, instead of exiting 1 with "run <id> is still in progress"
  (PILOT-166).
- The `bin/wait-dev-deploy` spec no longer depends on wall time: the script reads the clock through `date +%s`,
  which the spec fakes, so its poll count is deterministic (PILOT-200).

## [0.2.0] - 2026-10-20

### Added

- Prod deploy from the public mirror (decision 43): `Kamal Deploy` takes `source_sha` when `MIRROR=true`, checks
  the pair against `MIRROR_SOURCE.json` and the mirror tag (fail closed) and promotes the primary's image
  `sha-<source_sha>` without building; `develop-guard` is skipped on the mirror (PILOT-154).

### Fixed

- `bin/wait-dev-deploy` finds the Dev Deploy run by the sha it deploys (run title or Gate log) instead of the
  `main` branch GitHub reports for `workflow_run` runs, so a deployed `develop` merge no longer fails as
  "superseded by a newer main commit" (PILOT-116).

## [0.1.1] - 2026-10-20

### Fixed

- Swagger UI "Servers" shows the origin the docs were opened on (behind kamal-proxy: the forwarded https
  origin) instead of always `http://localhost:3000` (PILOT-110, backported by PILOT-121).

## [0.1.0] - 2026-10-16

### Added

- Releases: semantic version tags `vX.Y.Z` computed from the squash commits' `Type:` lines
  (`scripts/next-version.sh`), this changelog and `changelog-check`, a draft GitHub Release from the
  changelog section on every release tag (`Release` workflow), prod deploys only from an annotated release
  tag on `main`, a 10-minute `release-watch` after every prod deploy, protection of published tags
  (`.githooks/pre-push`) and per-release delivery metrics (`bin/sdlc-metrics`).

### Changed

- `Kamal Deploy` and `deploy/deploy.sh prod` take a release tag `vX.Y.Z` instead of a commit sha; a bare sha
  is refused.
- A prod rollback needs the typed confirm `ROLLBACK-prod`, in `Kamal Manage` (`confirm=ROLLBACK-prod`) and in
  `deploy/rollback.sh prod` (env `CONFIRM` or the prompt).
