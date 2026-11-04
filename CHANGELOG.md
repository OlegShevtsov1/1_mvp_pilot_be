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

## [0.5.0] - 2026-11-04

### Added

- Prod Switch keeps the final `pg_dump` of the old prod on the target host
  (`~/backups/<project>-prod-<UTC time>-from-<source>.dump`, owner-only, never deleted) and logs its path, size
  and sha256; a dump that cannot be kept fails the `data` step before DNS (PILOT-627).

### Security

- Update nokogiri to 1.19.5 (GHSA-3w22-6jfg-527w, GHSA-4p39-36wj-23h4, GHSA-v995-44v6-5fqm), rails-html-sanitizer
  to 1.7.2 (GHSA-cpgf-5mjf-73p7, GHSA-h7wh-q2qr-458c) and loofah to 2.25.3 (GHSA-345x-3rq2-jfrm, GHSA-h6v6-rg66-fqj4,
  GHSA-jcff-cj73-4w4f, GHSA-m3x9-938q-5767, GHSA-mf2j-8f84-cc9q, GHSA-p9wj-w8xq-vjx6), so bundler-audit passes again
  (PILOT-625).

## [0.4.0] - 2026-11-02

### Added

- The API contract documents the token, revoke and sign-out operations, bearer authentication, the 429 answers of
  sign-up and sign-in and the deprecated legacy sign-in; its examples carry placeholder tokens (PILOT-241).
- A task created without a status starts as not started; the API contract documents bearer authentication and the
  401 and 404 answers of every project and task operation (PILOT-242).
- A daily purge of token rows revoked or expired more than 30 days ago and of legacy-use rows older than 60 days,
  run by a new Kamal role `cron` from the app image; a failed run is reported to GlitchTip (PILOT-240, T13).
- Kamal Deploy and Kamal Manage take a `target` input: `aws` (the default) is unchanged, `srv` deploys, operates
  and watches the same release on the on-prem srv host with its own config, accessories and ECR tags
  `prod-srv-current`/`prod-srv-previous` (PILOT-550).
- A `Prod Switch` workflow moves prod between the AWS instance and the on-prem srv host in either direction: it
  brings the target to the live release, puts the live prod into maintenance, moves the database with a final
  dump and restore whose row counts must match, switches DNS through the infra prod stack only after the
  operator's `prod-dns` approval, checks the public URLs and moves `prod-current`/`prod-previous`; any failure
  before DNS brings the live prod back, once public DNS and the jobs API show that DNS was never touched. For
  `to=aws` while the AWS instance is stopped or deleted, it starts or re-creates it through infra
  `prod_target=aws-standby` after the `prod-dns` approval, without moving DNS. The target gets the release through
  a Kamal Deploy it dispatches. Kamal Deploy and Kamal Manage follow the live prod host from public DNS, and Kamal
  Deploy takes an optional `prod_switch_run`, set only by Prod Switch (PILOT-553).

### Changed

- The AI PR review is posted as a GitHub pull request review by `github-actions` (changes requested on P0/P1,
  otherwise a comment) with inline comments on the changed lines, dismisses its earlier request for changes
  once clean, lists P0/P1 findings in the job log, and also reviews the factory's `archon/task-factory-*` PRs
  (PILOT-369).

### Fixed

- The dashboard list (`GET /api/v1/projects`) of a user with 50 projects and 500 tasks took about a second on the
  server; the project serializer no longer builds a serializer per task and per owner, so the list is several times
  faster and its response is unchanged (PILOT-414).
- Creating a task with a status other than not_started, in_progress or completed answered 500; it now answers 422
  and names the allowed statuses (PILOT-242).
- The post-deploy smoke's token check no longer records a failed sign-in: it provokes the token endpoint's
  invalid_grant with an unknown refresh token instead of a wrong password (PILOT-331).
- The post-deploy smoke no longer records a failed sign-in at the legacy sign-in: it no longer sends a wrong
  password to /api/v1/sign_in, whose 401 the request specs cover (PILOT-333).
- A successful sign-in whose check outlasted its minute, or one around a deploy, could leave the failed sign-in
  count one short, so the 11th failure in a minute was not always refused; each attempt is now given back only to
  the minute it was counted in (PILOT-288).
- `bin/wait-dev-deploy` accepts a Dev Deploy run that deployed a newer commit containing the merge instead of
  failing it as superseded, counts a run as deployed once its Deploy job finished instead of waiting for Report
  and Notify, and waits up to 1440 s by default (under the factory's 1500 s deploy limit), so a deployed merge no
  longer fails or times out (PILOT-268).
- `bin/wait-dev-deploy` takes the sdlc v0.7.0 template waiter: a cancelled run of the commit counts as deployed
  when a newer commit that contains it deployed, read-only GitHub calls are retried on a 5xx or network error (3
  tries, `WAIT_DEV_DEPLOY_RETRY_SECONDS` backoff; the dispatch never is), an unreadable Gate log is read again on
  the next poll instead of failing the wait, and a failed job with spaces in its name is reported whole
  (PILOT-495).
- RuboCop run from a checkout under a hidden directory, such as the factory's worktrees, no longer inspects
  excluded files like `db/schema.rb` and `bin/*`; it is updated to 1.86.2, which fixes the skipped excludes
  (PILOT-360).
- The production image no longer installs or loads development and test gems (bullet, rspec-rails,
  rubocop-rails, shoulda-matchers, listen, factory_bot_rails, rails-controller-testing, rspec_junit_formatter):
  they moved from the default Gemfile group into the development and test groups (PILOT-376).
- The AI PR review matches the 1_mvp_sdlc template: inline comments also anchor on files whose path has spaces,
  quotes or non-ASCII characters, a clean re-run on an already reviewed head still dismisses the review's own
  request for changes and retries a failed dismissal, the job log shows the P0/P1 findings with model text kept
  inert and how many findings went inline, each finding is listed once, the review body and every inline
  comment are capped at 60000 characters, only reviews whose body starts with `<!-- ai-review -->` count as its
  own, and the review keeps the subscription token and Sonnet 5.5 (PILOT-369).

### Security

- The error tunnel `POST /api/errors` also accepts envelopes whose DSN carries the frontend's public host instead
  of the internal GlitchTip host, with or without a secret key, matching on public key and project id only; it
  still forwards only to the GlitchTip of `SENTRY_ALLOWED_FE_DSN`, so the frontend no longer needs to publish the
  internal host (PILOT-408).
- Update rack to 3.1.23 (GHSA-5v64-555j-wjxm, GHSA-2j8w-xcrc-x985, GHSA-wvg4-6p58-3gh3 and GHSA-p8x9-v4hv-2w4g),
  so bundler-audit passes again (PILOT-556).
- Update addressable to 2.9.1 (GHSA-qq38-m9mg-xjj5, GHSA-8gmh-2hhj-2hv9, GHSA-9crm-g4mf-wc5j,
  GHSA-539f-xcgw-2gjg, GHSA-4w5q-wg7v-w6gp, GHSA-9f42-57jx-vpp3 and GHSA-j82w-28jv-3pmj), so bundler-audit
  passes again (PILOT-589).

## [0.3.2] - 2026-10-28

### Security

- Devise's default `/users/*` routes are no longer mounted: `POST /users/sign_in` checked passwords without the
  failed sign-in limit and told a right password from a wrong one, and `POST /users` created users without the
  sign-up limit; both now answer 404 (PILOT-362).

## [0.3.1] - 2026-10-27

### Fixed

- A refresh token exactly 30 days old is refused even when its sign-in time has a fraction of a second; the
  30-day limit is counted in whole seconds (PILOT-297).

### Security

- Update net-ssh to 7.3.8 (GHSA-vxj5-fg65-x765, GHSA-rpq3-v334-f5pm and five more net-ssh advisories) and crass
  to 1.0.8 (GHSA-pq4g-8rxf-4g29), so bundler-audit passes again (PILOT-299).

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
