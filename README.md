# Project Management System

## Live

- **Production API:** <https://pilot.up.km.ua/health> · **Swagger UI:** <https://pilot.up.km.ua/api-docs/index.html>
- **Dev API:** <https://dev.pilot.up.km.ua/health> · **Swagger UI:** <https://dev.pilot.up.km.ua/api-docs/index.html>
- **Frontend (prod):** <https://app.pilot.up.km.ua> · repo [1_mvp_pilot_fe](https://github.com/OlegShevtsov1/1_mvp_pilot_fe)
- **SDLC tooling:** [1_mvp_sdlc](https://github.com/OlegShevtsov1/1_mvp_sdlc)

A robust RESTful API backend for managing projects and tasks. This application allows users to create, update, and track projects and their associated tasks through a secure API.

# Detailed task description

**GitHub:** [pilot/blob/develop/TASK_DEFINITION.md](pilot/blob/develop/TASK_DEFINITION.md)

## Repository

**GitHub:** [pilot](pilot)

## Project

**GitHub:** [projects/11](projects/5)

## Features

- User authentication with simple token
- Project CRUD operations
- Task management with status tracking
- RESTful API design
- Optimized database queries
- Comprehensive test coverage
- API documentation with Swagger

## Requirements

- Ruby 3.3.6
- Rails 7.2.2+
- PostgreSQL
- Docker (optional)

## Local Setup

1. Install dependencies

   ```
   bundle install
   ```

2. Setup environment variables

   ```
   cp .env.example .env
   # Edit .env file with your database credentials
   ```

3. Setup git hooks (optional)

   ```
   overcommit --sign
   ```
   
4.Setup database

   ```
   rails db:create
   rails db:migrate
   rails db:seed # Optional - adds sample data
   ```

5. Start the server

   ```
   rails s -p 3000
   ```

6. Access the API at http://localhost:3000

## Docker Setup

1. Build and start the containers

   ```
   docker compose build
   docker compose up
   ```

2. Setup the database
   ```
   docker compose run app rails db:create
   docker compose run app rails db:environment:set RAILS_ENV=development
   docker compose run app rake db:schema:load
   docker compose run app rails db:seed # Optional
   ```

## Docker Commands

```
# Migration commands
docker exec -it pilot-app-1 rails g migration description_of_change
docker exec -it pilot-app-1 rails db:migrate
docker exec -it pilot-app-1 rails db:rollback

# Bundle commands
docker compose run app bundle update
docker compose run app bundle

# Other helpful commands
docker exec -it pilot-app-1 rails c      # Rails console
docker attach pilot-app-1                # Debug mode
docker exec -it pilot-app-1 rspec        # Run tests
docker exec -it pilot-app-1 /bin/bash    # Terminal access
```

## Dev deploy

Every commit pushed to `develop` or a `hotfix/*` branch that both `Rails Tests` and `Rails CI`
passed is deployed to the dev environment by the `Dev Deploy` workflow
(`.github/workflows/dev-deploy.yml`). A commit on `main` is deployed only by dispatching the workflow
on `main` (`gh workflow run dev-deploy.yml --ref main`), which `bin/wait-dev-deploy` does once for a
factory merge into `main` that the automatic trigger did not deploy. A deploy is skipped when its
branch has a newer head or no longer exists by the time the VPN lock is taken.

1. **Gate** – deploys once per commit, from whichever of the two workflows finished last
   (`deploy/dev_deploy_gate.sh`).
2. **Preflight** – fails fast, naming every missing secret (names only, never values).
3. **Probe** – checks that the shared `vpn-up`/`vpn-down` actions can be used.
4. **Build once** – builds the image `sha-<git sha>` (with `APP_RELEASE` baked in) and pushes it
   to ECR; an image that already exists is not rebuilt. The summary records its digest.
5. **Deploy** – `vpn-up` → `deploy/deploy.sh dev sha-<sha>` (Kamal 2, `config/deploy.dev.yml`) →
   `/health` must report the new release and `bin/swagger_smoke` must pass, both through the VPN
   → `vpn-down`.
6. **Report / Notify** – the job summary explains the first failure; Telegram gets ✅ or ❌.

The app answers on `dev.<PROJECT_ZONE>` (`config/project.env` holds the project name and zone).
Migrations run on boot (`bin/docker-entrypoint` → `db:prepare`): a failing migration keeps the new
container unhealthy, Kamal aborts and the previous version keeps serving.

Manual runs:

```
gh workflow run "Dev Deploy" -f action=deploy                       # deploy the dispatched ref
gh workflow run "Dev Deploy" -f action=rollback                     # back to the previous version
gh workflow run "Dev Deploy" -f action=rollback -f version=sha-<40 hex>
```

Waiting for a merge to reach dev (the factory's deploy command):

```
bin/wait-dev-deploy [<40 hex sha>]   # default: HEAD
bin/wait-dev-deploy --rollback       # dispatches action=rollback and waits for that run
```

It waits for the Dev Deploy run that deploys the commit and exits 0 when its `Deploy or roll back`
step succeeded, 1 when that run failed, was superseded by a newer `main` commit, Rails Tests or
Rails CI failed, or it timed out, and 2 on a malformed sha. GitHub does not always create the
second `workflow_run` run, so when both CI runs are green and no run for the commit is deploying,
it dispatches Dev Deploy for `main` once (only while `main` is still that commit), prints a
`warning:` line and waits for that run instead. `WAIT_DEV_DEPLOY_TIMEOUT` (seconds, default 1200),
`WAIT_DEV_DEPLOY_INTERVAL` (15) and `WAIT_DEV_DEPLOY_GRACE` (120, how long to wait for the automatic
trigger) tune it.

From a console on the VPN, with the secrets below exported, AWS credentials that can pull from
ECR and an SSH key accepted by the dev host:

```
DEV_HOST=<dev host VPN address> deploy/deploy.sh dev sha-<sha>   # SKIP_SMOKE=1 skips the smoke
DEV_HOST=<dev host VPN address> deploy/rollback.sh dev [sha-<sha>]
```

**Never run `kamal remove` or `kamal proxy reboot|remove` with `config/deploy.dev.yml`:** the
kamal-proxy on the dev host is shared with another deployment. Always pass the config with `-c`.

Secrets (names only):

- repository: `AWS_ROLE_ARN`, `VPN_CI_OVPN`, `SRV_DEPLOY_SSH_KEY`
- environment `dev`: `SECRET_KEY_BASE`, `POSTGRES_PASSWORD` (URL-safe, never changed after the
  first deploy), `SENTRY_DSN`, `SENTRY_ALLOWED_FE_DSN`, `SMOKE_TOKEN`,
  `TELEGRAM_PILOT_DEV_ALERTS_BOT_TOKEN`, `TELEGRAM_PILOT_DEV_ALERTS_CHAT_ID`,
  `TELEGRAM_PILOT_DEV_ALERTS_THREAD_ID`

Shared mechanism (kamal-proxy, vpn-up/vpn-down, CI SSH key):
[docs/uk/16-dev-kamal.md](https://github.com/OlegShevtsov1/1_mvp_infra/blob/env/dev/docs/uk/16-dev-kamal.md)
(private infra repo).

### Error tracking

Errors go to GlitchTip through the Sentry SDK (`SENTRY_DSN`; nothing is sent without it), tagged
with `SENTRY_ENVIRONMENT` and the release; request data is scrubbed with `filter_parameters`.

- `POST /api/errors` – tunnel for the frontend's browser SDK. Only envelopes for
  `SENTRY_ALLOWED_FE_DSN` are relayed (to that DSN's GlitchTip envelope endpoint, authenticated with
  the DSN's public key in `X-Sentry-Auth`, never to a host from the request),
  up to 256 KiB; 404 while `SENTRY_ALLOWED_FE_DSN` is unset. Each client IP gets 30 requests a
  minute, counting every request including refused ones, then 429; the count is also kept in process
  memory, so it holds while Redis is unavailable or comes back mid-minute.
- CORS: browsers may call the API from the origins in `CORS_ALLOWED_ORIGINS` (comma-separated).
- `POST /admin/glitchtip_smoke/<unhandled|manual|db>` with header `X-Smoke-Token: <SMOKE_TOKEN>`
  (and optionally `X-Smoke-Marker: <word>`) raises that kind of error; 404 without the token.
- `bin/rails 'glitchtip:smoke[rake]'` (marker from `GLITCHTIP_SMOKE_MARKER`) reports one from
  outside a request.

`bin/swagger_smoke BASE_URL` smoke-tests any running instance against every operation documented
in `swagger/v1/swagger.json`. With `SMOKE_READ_ONLY=1` it only sends GET requests and creates
nothing (prod uses this):

```
bin/swagger_smoke http://localhost:3000
SMOKE_READ_ONLY=1 bin/swagger_smoke https://<PROJECT_ZONE>
```

## Prod deploy

Prod runs with Kamal 2 from `config/deploy.yml` (always passed with `-c`; there are no
destination files): the service `<PROJECT_NAME>` answers on `https://<PROJECT_ZONE>`, with TLS
terminated by kamal-proxy and a Let's Encrypt certificate. The app forces SSL
(`RAILS_FORCE_SSL=true`) and sends HSTS. SSH reaches the prod host only through the mvp VPN, at
the address in the secret `PROD_VPN_IP`, which is never committed.

**Build once.** Prod never builds. `deploy/deploy.sh prod` (or `deploy/promote.sh`) re-tags the
image `sha-<sha>` that Dev Deploy built as `prod-sha-<sha>`, changing only its `service` label
(Kamal only runs an image labelled for its service). The layers stay byte-identical, and the
promotion fails if the layers or the config differ in any other way. After `/health` reports the
new release and the read-only smoke passes, the ECR tag `prod-current` points at the live image and
the one it replaced becomes `prod-previous`. A rollback moves the tags the same way, so
`prod-current` is always what is running.

Deploy a release: an annotated tag `vX.Y.Z` on `main` whose commit Dev Deploy has already
deployed and smoke-tested (see "Релізи й hotfix"); a bare sha is refused:

```
gh workflow run "Kamal Deploy" --ref main -f environment=prod -f version=vX.Y.Z -f confirm=prod
```

Operate prod:

```
gh workflow run "Kamal Manage" --ref main -f action=status
gh workflow run "Kamal Manage" --ref main -f action=logs
gh workflow run "Kamal Manage" --ref main -f action=restart -f confirm=prod
gh workflow run "Kamal Manage" --ref main -f action=rollback -f confirm=ROLLBACK-prod        # the previous version
gh workflow run "Kamal Manage" --ref main -f action=rollback -f confirm=ROLLBACK-prod -f version=<sha>
gh workflow run "Kamal Manage" --ref main -f action=remove -f confirm=remove-prod            # disabled, see Pending
```

Guards (`deploy/prod_guard.sh`), checked before anything touches prod: the workflow runs only from
`main`; deploys need `environment=prod`, `confirm=prod` and a version `vX.Y.Z`; restart needs
`confirm=prod`, rollback the typed `confirm=ROLLBACK-prod`, remove `confirm=remove-prod`. A deploy's
tag must also be annotated, published on origin and on `main` (`deploy/release_tag_check.sh`, and
`deploy/deploy.sh prod` checks it again), and its commit's image `sha-<sha>` must already be in ECR.
A rollback has no such pre-check: it can only boot a version whose container is still on the host,
and it fails unless `/health` then reports that release. The deploy job of `Kamal Deploy` and the
whole of `Kamal Manage` share one concurrency group, so two prod operations never overlap and a
rollback never waits for `release-watch`. Telegram gets ✅ or ❌ in the prod alerts topic.

The post-deploy smoke on prod is read-only (`SMOKE_READ_ONLY=1`): it checks `/health`, the
unauthenticated API answers and the API docs, and it creates no users.

From a console on the VPN, with the secrets below exported, AWS credentials that can read and push
ECR, `crane` and `jq` installed, and the prod SSH key in an agent:

```
PROD_VPN_IP=<prod VPN address> deploy/deploy.sh prod vX.Y.Z         # SKIP_SMOKE=1 skips the smoke
PROD_VPN_IP=<prod VPN address> deploy/rollback.sh prod [sha-<sha>]   # type ROLLBACK-prod at the prompt
CONFIRM=ROLLBACK-prod PROD_VPN_IP=<prod VPN address> deploy/rollback.sh prod [sha-<sha>]
PROD_VPN_IP=<prod VPN address> deploy/promote.sh sha-<sha>            # promotion only
PROD_VPN_IP=<prod VPN address> deploy/manage.sh status|logs|restart
```

Secrets (names only):

- repository: `AWS_ROLE_ARN`, `VPN_CI_OVPN`
- environment `prod`: `PROD_VPN_IP`, `PROD_SSH_KEY`, `SECRET_KEY_BASE`, `POSTGRES_PASSWORD`
  (URL-safe, never changed after the first deploy), `SENTRY_DSN`, `SENTRY_ALLOWED_FE_DSN`,
  `SMOKE_TOKEN`, `TELEGRAM_PILOT_PROD_ALERTS_BOT_TOKEN`, `TELEGRAM_PILOT_PROD_ALERTS_CHAT_ID`,
  `TELEGRAM_PILOT_PROD_ALERTS_THREAD_ID`, `GLITCHTIP_API_TOKEN` (read-only GlitchTip API token for
  `release-watch`; without it every watch ends ❌ "GlitchTip check failed", the deploy itself is not
  affected)

Pending:

- `remove` is disabled: its backup gate always fails until the prod DB backup (I5) exists.
- The Beszel agent (`beszel-agent-prod` accessory) waits for the Beszel hub key from I6.
- The prod security group must allow public 80/443 (managed in `1_mvp_infra`).
- `vpn-up` checks the dev host while connecting, so prod deploys also fail while the dev host is
  down.
- `Kamal Manage` `logs` prints prod app logs into the Actions log; restrict it before the
  repository goes public.

Prod project infrastructure:
[docs/uk/14-prod-proektu.md](https://github.com/OlegShevtsov1/1_mvp_infra/blob/env/dev/docs/uk/14-prod-proektu.md)
(private infra repo).

## Релізи й hotfix

**Versions.** Releases are annotated git tags `vX.Y.Z` ([Semantic Versioning](https://semver.org)).
The number is not chosen by hand: `scripts/next-version.sh [<ref>]` reads the single `Type:` line of
every squash commit since the previous release tag (the PR body becomes the squash body, decision 25)
and bumps:

| since the previous tag | bump |
| --- | --- |
| a `BREAKING CHANGE: <what>` footer line in any body | MAJOR |
| any `Type: feat` | MINOR |
| only `Type: fix` (besides chore, docs, ci, refactor, test) | PATCH |
| nothing but chore, docs, ci, refactor, test | none (exit 3) |

The first release is `0.1.0`. A commit without a `Type:` line, with several, or with an invalid value
stops the script with the list of those commits; it never guesses. Merge commits (the release PR,
back-merges) are skipped. `scripts/next-version.sh --previous [<ref>]` prints the previous tag.

**CHANGELOG.** `CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). A PR
whose `Type:` is `feat` or `fix` adds an entry under `## [Unreleased]` in the matching category;
`changelog-check` fails it otherwise. The label `skip-changelog` is for trivia only; chore, docs, ci,
refactor and test need no entry. `scripts/release-notes.sh vX.Y.Z` prints a version's section.

**Release flow.**

1. Release-prep PR into `develop` (`Type: docs`): move the `[Unreleased]` entries into
   `## [X.Y.Z] - YYYY-MM-DD` (X.Y.Z from `scripts/next-version.sh origin/develop`) and keep
   `[Unreleased]` with its six empty categories. Its squash commit `<D>` is deployed to dev by Dev
   Deploy.
2. Release PR `develop` → `main` (`Type: chore`), merged by the operator by hand with a merge commit
   (decision 27); `TDD check` skips it, `changelog-check` passes it.
3. The operator tags `<D>`, the commit dev tested, not the merge commit (which Dev Deploy never
   built):
   ```
   git fetch origin && git rev-parse origin/main^2             # == <D>
   git diff --quiet origin/main <D> && git tag -a vX.Y.Z -m vX.Y.Z <D> && git push origin vX.Y.Z
   ```
4. The `Release` workflow checks that the tag is annotated and on `main` and that its number is what
   `scripts/next-version.sh` computes for `<D>`, then creates a **draft** GitHub Release whose notes
   are exactly the CHANGELOG section (no LLM), and prints the metrics line (below). ✅ or ❌ goes to the
   prod alerts topic.
5. Prod deploy from the tag (`Kamal Deploy`, `version=vX.Y.Z`); after `release-watch` is ✅ the
   operator publishes the draft (`gh release edit vX.Y.Z --draft=false`).

**Tag-only prod (R-C9).** `Kamal Deploy` and `deploy/deploy.sh prod` take only `vX.Y.Z`: annotated,
as published on origin (a local tag of the same name is replaced by the published one), on a commit
in `main`'s history whose image Dev Deploy built. A bare sha, a lightweight tag or a tag off `main`
is refused before anything touches prod. A rollback target stays a sha: it is a version still on
the host.

**release-watch.** After every successful prod deploy, the `release-watch` job of `Kamal Deploy`
polls `https://<PROJECT_ZONE>/health` every 30 seconds for 10 minutes (each check must report the
deployed release) without the VPN, then takes the VPN once to count the GlitchTip issues of
`<PROJECT_NAME>-be-prod` first seen since the watch started (`deploy/glitchtip_issues.sh`, which
first checks the shape of the API answer). ✅ when every check passed and there is no new issue;
otherwise ❌ naming the failed checks and up to three issues. It **never rolls back**: a person
decides, with one of the paths below. The token is the secret `GLITCHTIP_API_TOKEN` in environment
`prod`: a GlitchTip API token with read-only scopes (`project:read`, `event:read`), never printed;
the API address is derived from `SENTRY_DSN` (or `GLITCHTIP_API_URL` in a console).

**Rollback, two ways**, both with the typed confirm `ROLLBACK-prod`, both moving the ECR tags
`prod-current`/`prod-previous`:

```
gh workflow run "Kamal Manage" --ref main -f action=rollback -f confirm=ROLLBACK-prod [-f version=<sha>]
PROD_VPN_IP=<prod VPN address> deploy/rollback.sh prod [sha-<sha>]      # console; type ROLLBACK-prod
```

**Hotfix** (decisions 27, 28):

1. Branch `hotfix/PILOT-<n>-<slug>` from `origin/main`; Dev Deploy deploys every push to it.
2. The PR into `main` (`Type: fix`) also adds `## [X.Y.(Z+1)] - YYYY-MM-DD` with `### Fixed` directly
   to `CHANGELOG.md` (between `[Unreleased]` and the previous version); `changelog-check` accepts a new
   version section.
3. The operator merges it by hand (squash) into `main`, dispatches Dev Deploy on `main` to build the
   squash commit `<H>` (`gh workflow run dev-deploy.yml --ref main -f action=deploy`,
   `bin/wait-dev-deploy <H>`), and tags it: `scripts/next-version.sh <H>` → the PATCH version,
   `git tag -a vX.Y.(Z+1) -m vX.Y.(Z+1) <H> && git push origin vX.Y.(Z+1)`; then prod from that tag.
4. Back-merge: branch `hotfix/PILOT-<n>-<slug>-back-merge` from `origin/develop`,
   `git merge --no-ff origin/main` (resolve `CHANGELOG.md`), PR into `develop` (`Type: chore`) merged
   by the operator **with a merge commit** (a squash would drop `<H>` from `develop`'s history, and
   the next version would not see the hotfix tag). `TDD check` skips the commits already on `main`.

**Published tags are never moved or deleted.** `.githooks/pre-push` refuses a push that deletes or
moves a `v*` tag on the remote (`git push --force` of a moved tag, `git push --delete origin v*`,
pushing the deletion after `git tag -d`). Install it in every clone:
`git config core.hooksPath .githooks` (`bin/setup` does it). In Claude Code the same commands are
refused by `permissions.deny` in `.claude/settings.json`. A test tag that must go (only one without a
Release that prod never ran) is deleted through the GitHub API by the operator.

**Metrics (R-C7).** `bin/sdlc-metrics <tag> [--runs <factory runs dir>]` prints one line of team
metrics for the release (pull requests, lead time, median PR lead time, prod rollbacks through
`Kamal Manage`, the share of factory runs not delivered, their review findings P0/P1/P2, Draft
documents unchanged for 30 days); `Release` runs it without `--runs`. Seven days after a tag,
`bin/sdlc-metrics --escaped <tag>` (with `GLITCHTIP_API_TOKEN` and `GLITCHTIP_API_URL`) prints the
escaped defects: GlitchTip issues first seen in those 7 days. Rollbacks from a console are not
visible to it.

## CI

Three GitHub Actions workflows run the checks: `Rails Tests` on pull requests into `main` and
`develop`, `Rails CI` on every pull request, both on pushes to `main`, `develop` and `hotfix/*`,
and `Manual Rails CI` on demand. RSpec, RuboCop, Brakeman, bundler-audit,
gitleaks and actionlint (workflow files) are all blocking.

`TDD check` runs on every pull request: the first commit must be `test(<scope>)` (condition 1), it
must fail `bundle exec rspec` with at least one failing example (a file that does not load is not
RED), recorded as the `tdd-check/red` commit status on that commit (condition 2), and a `feat(` or
`fix(` commit must follow it with `spec/` unchanged in between (condition 3). A pull request whose
single `Type:` line is `ci`, `chore` or `docs` and whose changed files are all under `.github/`,
`.archon/`, `docs/` or Markdown is exempt; every other one keeps conditions 1–3. `main-guard` checks
on every push to `main` that the commit came from a merged pull request and alerts the
`PILOT_DEV_ALERTS` Telegram topic otherwise; `develop-guard` does the same for `develop`.

`pr-conventions-check` runs on every pull request into `main` or `develop`
(`bin/pr-conventions-check`): the head branch is `feature/PILOT-<n>-<slug>`,
`hotfix/PILOT-<n>-<slug>`, the factory's `archon/task-factory-*`, or `develop` into `main`
(condition 1); the title is `PILOT-<n>: <card title>` (condition 2); the body has exactly one line
starting with `Type:`, with one of `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `ci`
(condition 3). The title and body become the squash commit.

`TDD check` does not check commits that are already on `main` (so a back-merge of `main` into
`develop` passes), and skips the release PR `develop` → `main`.

`changelog-check` runs on every pull request into `main` or `develop` (`bin/changelog-check`): a
`Type: feat` or `Type: fix` PR must change `[Unreleased]` in `CHANGELOG.md` or add a version section;
the label `skip-changelog` passes it. `Release` runs on every pushed `v*` tag (see "Релізи й hotfix").

## API Documentation

The API is documented using Swagger/OpenAPI. After starting the server, you can access the documentation at:

```
http://localhost:3000/api-docs/index.html
```

To regenerate the Swagger documentation:

```
RAILS_ENV=test bundle exec rspec spec/requests/api/v1 --format Rswag::Specs::SwaggerFormatter
```

## API Endpoints

- **Authentication**

  - POST /api/v1/auth/login - Sign in
  - POST /api/v1/users - Register a new user

- **Projects**

  - GET /api/v1/projects - List all projects
  - GET /api/v1/projects/:id - Get project details
  - POST /api/v1/projects - Create a new project
  - PUT /api/v1/projects/:id - Update a project
  - DELETE /api/v1/projects/:id - Delete a project

- **Tasks**
  - GET /api/v1/projects/:project_id/tasks - List tasks for a project with filter
  - GET /api/v1/tasks/:id - Get task details
  - POST /api/v1/projects/:project_id/tasks - Create a new task
  - PUT /api/v1/tasks/:id - Update a task
  - DELETE /api/v1/tasks/:id - Delete a task

## CURL example

``` Register a new user
curl -X 'POST' \
  'http://localhost:3000/api/v1/users' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
  "user": {
    "email": "user@example.com",
    "password": "password",
    "password_confirmation": "password"
  }
}'
```

```Sign in
curl -X 'POST' \
  'http://localhost:3000/api/v1/sign_in' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
  "email": "user@example.com",
  "password": "password"
}'
```

```Project list

curl -X 'GET' \
  'http://localhost:3000/api/v1/projects' \
  -H 'accept: application/json' \
  -H 'X-User-Token: <X_USER_TOKEN>' \
  -H 'X-User-Email: <X_USER_EMAIL>'
```

## Running Tests

```
bundle exec rspec
```

## Troubleshooting

If you get an error "A server is already running", try:

```
rm tmp/pids/server.pid
```

Then start the server again.

```

```
