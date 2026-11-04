# Project Management System

A RESTful API backend for managing projects and tasks: users sign in with a token, create projects and track
their tasks through a documented JSON API. The specification is [TASK_DEFINITION.md](TASK_DEFINITION.md), the
domain glossary and invariants are in [CONTEXT.md](CONTEXT.md), and the architecture as built is in
[docs/architecture-map.md](docs/architecture-map.md). The frontend lives in
[1_mvp_pilot_fe](https://github.com/OlegShevtsov1/1_mvp_pilot_fe); the delivery process (Claude Code plugins and the
Archon factory) in [1_mvp_sdlc](https://github.com/OlegShevtsov1/1_mvp_sdlc).

## Live

- **Production API:** <https://pilot.up.km.ua/health> · **Swagger UI:** <https://pilot.up.km.ua/api-docs/index.html>
- **Dev API:** <https://dev.pilot.up.km.ua/health> · **Swagger UI:** <https://dev.pilot.up.km.ua/api-docs/index.html>
- **Frontend (prod):** <https://app.pilot.up.km.ua>

## Architecture

Rails 8.0 API-only on Puma, PostgreSQL 16 for users, projects and tasks, Redis 7 as the Rails cache for list
endpoints, and GlitchTip (Sentry protocol) for error tracking; the frontend is a separate SPA that calls the API
over HTTPS with a bearer access token, falling back until the cutoff to the legacy `X-User-Email`/`X-User-Token`
headers (ADR-0005), and relays its own browser errors through the API's
`/api/errors` tunnel. The C4 container diagram, the module inventory, the conventions a new feature must follow,
the datastores and the known technical debt are in [docs/architecture-map.md](docs/architecture-map.md); the
schema is [db/schema.rb](db/schema.rb) and the OpenAPI document [swagger/v1/swagger.json](swagger/v1/swagger.json).

## Deployment

One Docker image per commit, built once by CI and promoted, never rebuilt, to production. Kamal 2 runs it on two
environments: **dev** (every merge into `develop` is deployed automatically after CI, see [Dev deploy](#dev-deploy))
and **prod** (deployed only from an annotated release tag `vX.Y.Z` on `main`, with a typed confirmation, see
[Prod deploy](#prod-deploy) and [Releases and hotfixes](#releases-and-hotfixes)). Each deploy waits for `/health`
to report the new release and runs a smoke test against the Swagger document; production is then watched for ten
minutes (`release-watch`) and can be rolled back from the console or from GitHub Actions. Errors from both
environments go to GlitchTip through the Sentry SDK ([Error tracking](#error-tracking)).

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
- Rails 8.0.5 (see `Gemfile`)
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
(`.github/workflows/dev-deploy.yml`). A commit that the automatic trigger did not deploy is deployed
by dispatching the workflow on the commit's own branch (`gh workflow run dev-deploy.yml --ref <branch>`),
which `bin/wait-dev-deploy` does once; for a factory merge into `main` that branch is `main`. A deploy is skipped when its
branch has a newer head or no longer exists by the time the VPN lock is taken.

1. **Gate** – deploys once per commit, from whichever of the two workflows finished last
   (`deploy/dev_deploy_gate.sh`).
2. **Preflight** – fails fast, naming every missing secret (names only, never values).
3. **Probe** – checks out the shared `vpn-up`/`vpn-down`/`notify-telegram` actions from the owner's
   `1_mvp_infra` with `INFRA_READ_TOKEN` and checks that all three are there.
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
step succeeded, or a later Dev Deploy run deployed a commit that contains it; it does not wait for
Report and Notify. It exits 1 when a run of the commit failed, Rails Tests or Rails CI failed, or it
timed out, and 2 on a malformed sha. GitHub
reports every `workflow_run` run on `main`, so the script finds the run by its title
`Dev Deploy sha-<sha>` (or, for older runs titled just `Dev Deploy`, by the `HEAD_SHA` in their Gate
log once the run completed); a run of the commit that did not deploy it is not the one it waits for.
GitHub does not always create the second `workflow_run` run, so when both CI runs are green and no
run for the commit is deploying, it dispatches Dev Deploy once on the commit's own branch (`develop`, `hotfix/*` or
`main`, only while that branch is still the commit), prints a `warning:` line and waits for that
run instead. `WAIT_DEV_DEPLOY_TIMEOUT` (seconds, default 1440, under the factory's 1500 s limit on its
deploy command),
`WAIT_DEV_DEPLOY_INTERVAL` (15), `WAIT_DEV_DEPLOY_GRACE` (120, how long to wait for the automatic
trigger) and `WAIT_DEV_DEPLOY_RETRY_SECONDS` (5, backoff base of the 3 tries of a read after a GitHub 5xx or
network error; the dispatch is never retried) tune it.

Factory runs pause twice for the operator (`.archon/factory-profile.yaml`, sdlc v0.10.0): `merge_approval:
operator` stops at `pr-approve` after a green merge gate and merges only the head the operator approved
(Telegram, or the label `operator-approved`); `qa_dev` stops at `qa-dev` after the dev deploy with the deployed
commit and the dev URL. be has no e2e workflow (`e2e_workflow: ""`) and no pages to shoot.

From a console on the VPN, with the secrets below exported, AWS credentials that can pull from
ECR and an SSH key accepted by the dev host:

```
DEV_HOST=<dev host VPN address> deploy/deploy.sh dev sha-<sha>   # SKIP_SMOKE=1 skips the smoke
DEV_HOST=<dev host VPN address> deploy/rollback.sh dev [sha-<sha>]
```

A rollback to a version from before the `cron` role (T13) boots only the `web` role, because that version has no
cron container and Kamal refuses a rollback otherwise; the newer cron container keeps running until the next deploy.

**Never run `kamal remove` or `kamal proxy reboot|remove` with `config/deploy.dev.yml` or
`config/deploy.prod-srv.yml`:** the kamal-proxy on the dev host is shared with another deployment. Always pass the
config with `-c`.

Secrets (names only):

- repository: `AWS_ROLE_ARN`, `VPN_CI_OVPN`, `SRV_DEPLOY_SSH_KEY`, `INFRA_READ_TOKEN`
- environment `dev`: `SECRET_KEY_BASE`, `POSTGRES_PASSWORD` (URL-safe, never changed after the
  first deploy), `SENTRY_DSN`, `SENTRY_ALLOWED_FE_DSN`, `SMOKE_TOKEN`,
  `TELEGRAM_PILOT_DEV_ALERTS_BOT_TOKEN`, `TELEGRAM_PILOT_DEV_ALERTS_CHAT_ID`,
  `TELEGRAM_PILOT_DEV_ALERTS_THREAD_ID`

Variables (names only): environment `dev`: `GOOGLE_CLIENT_ID` (public Google OAuth client id, passed to the
container as plain env; never committed; empty when unset), `OAUTH_CLIENT_ID` (public client id of the web app's
Doorkeeper application, passed as plain env; the container creates the application on start, a changed value adds a
second one; never committed; empty when unset).

`INFRA_READ_TOKEN` (repository secret) is a token that can only read the owner's `1_mvp_infra`. Every job
that needs `vpn-up`, `vpn-down` or `notify-telegram` first checks out `1_mvp_infra` at `env/dev` (only
`.github/actions`, `scripts`, `host`, `projects` and the top-level files) into `infra-helpers/` and runs the
actions from there, because a public copy of this repository cannot use actions from a private repository.
Without it, the preflight and the Probe of Dev Deploy, Kamal Deploy and Kamal Manage fail and name it; the
Notify jobs and the guards then send their Telegram message straight to the Bot API and fail naming it.

The shared mechanism (kamal-proxy, the `vpn-up`/`vpn-down` actions, the CI SSH key) is documented in the
private infrastructure repository.

### Error tracking

Errors go to GlitchTip through the Sentry SDK (`SENTRY_DSN`; nothing is sent without it), tagged
with `SENTRY_ENVIRONMENT` and the release; request data is scrubbed with `filter_parameters`.

- `POST /api/errors` – tunnel for the frontend's browser SDK. An envelope is relayed when its DSN has
  the public key and project id of `SENTRY_ALLOWED_FE_DSN`, whatever its host, so the frontend may
  publish the DSN with its public host instead of the internal one; the full DSN still works. It is
  always relayed to that DSN's GlitchTip envelope endpoint, authenticated with the DSN's public key in
  `X-Sentry-Auth`, never to a host from the request,
  up to 256 KiB; 404 while `SENTRY_ALLOWED_FE_DSN` is unset. Each client IP gets 30 requests a
  minute, counting every request including refused ones, then 429; the count is also kept in process
  memory, so it holds while Redis is unavailable or comes back mid-minute.
- CORS: browsers may call the API from the origins in `CORS_ALLOWED_ORIGINS` (comma-separated),
  with any request header (including `Authorization`); answers expose `Retry-After`.
- `POST /admin/glitchtip_smoke/<unhandled|manual|db>` with header `X-Smoke-Token: <SMOKE_TOKEN>`
  (and optionally `X-Smoke-Marker: <word>`) raises that kind of error; 404 without the token.
- `bin/rails 'glitchtip:smoke[rake]'` (marker from `GLITCHTIP_SMOKE_MARKER`) reports one from
  outside a request.

`bin/swagger_smoke BASE_URL` smoke-tests any running instance against every operation documented
in `swagger/v1/swagger.json`. With `SMOKE_READ_ONLY=1` it only sends GET requests and creates
nothing (prod uses this). The token, sign-out and revoke checks need `OAUTH_CLIENT_ID` and are skipped
without it; with it, the authenticated checks use the sign-up access token as a bearer token, otherwise the
legacy headers, which `X-Smoke-Token` marks only when `SMOKE_TOKEN` is set (unmarked, the server counts them as
legacy uses). A separate legacy pass, every request marked so the server never counts it, runs while
`LEGACY_AUTH_ENABLED` is not off and `SMOKE_TOKEN` is set. The documented 429 answers and the legacy sign-in's 401,
which would count as a failed sign-in, are never provoked:

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
`prod-current` is always what is running on the live prod host (the AWS host until a Prod Switch
moves prod to the srv host; see "Prod Switch (aws <-> srv)").

Deploy a release: an annotated tag `vX.Y.Z` on `main` whose commit Dev Deploy has already
deployed and smoke-tested (see "Releases and hotfixes"); a bare sha is refused:

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

- repository: `AWS_ROLE_ARN`, `VPN_CI_OVPN`, `INFRA_READ_TOKEN`
- environment `prod`: `PROD_VPN_IP`, `PROD_SSH_KEY`, `SECRET_KEY_BASE`, `POSTGRES_PASSWORD`
  (URL-safe, never changed after the first deploy), `SENTRY_DSN`, `SENTRY_ALLOWED_FE_DSN`,
  `SMOKE_TOKEN`, `TELEGRAM_PILOT_PROD_ALERTS_BOT_TOKEN`, `TELEGRAM_PILOT_PROD_ALERTS_CHAT_ID`,
  `TELEGRAM_PILOT_PROD_ALERTS_THREAD_ID`, `GLITCHTIP_API_TOKEN` (read-only GlitchTip API token for
  `release-watch`; without it every watch ends ❌ "GlitchTip check failed", the deploy itself is not
  affected)

Variables (names only): environment `prod` (here and on the public mirror): `GOOGLE_CLIENT_ID` (public Google
OAuth client id, passed to the container as plain env; never committed; empty when unset), `OAUTH_CLIENT_ID` (public
client id of the web app's Doorkeeper application, passed as plain env; the container creates the application on
start, a changed value adds a second one; never committed; empty when unset).

Pending:

- `remove` is disabled: its backup gate always fails until the prod DB backup (I5) exists.
- The Beszel agent (`beszel-agent-prod` accessory) waits for the Beszel hub key from I6.
- The prod security group must allow public 80/443 (managed in `1_mvp_infra`).
- `vpn-up` checks the dev host while connecting, so prod deploys also fail while the dev host is
  down.
- `Kamal Manage` `logs` prints prod app logs into the Actions log; restrict it before the
  repository goes public.

The prod host, VPN and DNS are managed in the private infrastructure repository.

### Prod on the on-prem srv host (`target=srv`)

To save cost, `Kamal Deploy` and `Kamal Manage` can send prod to the on-prem server that already
runs dev (the srv host) instead of the AWS instance. The input `target` is `aws` by default, which
behaves exactly as described above; `target=srv` deploys and operates the same release under the
same dual control (`main` only, environment `prod`, `confirm=prod`, an annotated release tag).

- Config: `config/deploy.prod-srv.yml`, a self-contained copy of `config/deploy.yml` that differs
  only in the host (`PROD_SRV_VPN_IP`), the SSH user (`<PROJECT_NAME>-prod`) and the proxy. The
  service stays `<PROJECT_NAME>`, so it runs the same promoted `prod-sha-<sha>` image, and its
  containers, accessories and volumes (`<PROJECT_NAME>-web`, `-cron`, `-db`, `-redis`, `-pg-data`,
  `-redis-data`) sit beside dev (`<PROJECT_NAME>-dev-*`) and the other deployment on the host's
  shared kamal-proxy. That proxy routes only the host `<PROJECT_ZONE>` to it; TLS is terminated by
  the public TLS terminator in front of the proxy, as for dev (`forward_headers: true`).
- Data: srv gets fresh `db` and `redis` accessories and starts empty. Prod Switch moves the data
  (dump and restore) at the cut-over.
- ECR tags: srv moves its own `prod-srv-current` / `prod-srv-previous`; `prod-current` /
  `prod-previous` always name the live prod host, so a srv deploy or rollback also moves them while
  srv is live, and an aws one moves `prod-aws-current` / `prod-aws-previous` instead while it is not.
  The live host is read from public DNS (`deploy/prod_active_target.sh`, env `PROD_ACTIVE_TARGET`).
- An aws deploy while srv is live checks `/health` inside the web container (its kamal-proxy cannot
  renew the certificate while DNS points elsewhere), skips the smoke and `release-watch`.
- Checks: the health check, the read-only smoke and `release-watch` go over the VPN straight to the
  srv host's proxy with the prod Host header, never through public DNS, wherever it points.
  So a srv `release-watch` holds the shared VPN lock for its whole watch, which is therefore 3
  minutes (6 checks) instead of 10: every other job's `vpn-up` waits for the lock only 300 s and
  then fails, so a Dev Deploy or Kamal Manage run must not wait behind a longer watch.
- `remove` is refused on srv (`deploy/prod_guard.sh` and `deploy/manage.sh`): `kamal remove` would
  also remove the kamal-proxy shared with dev and the other deployment.
- `restart` on srv boots the running version by name (`kamal app boot --version`), never `latest`: the image tag
  `latest` on the srv host is shared with dev, whose deploys move it to develop code.

```
gh workflow run "Kamal Deploy" --ref main -f environment=prod -f target=srv -f version=vX.Y.Z -f confirm=prod
gh workflow run "Kamal Manage" --ref main -f action=status -f target=srv
gh workflow run "Kamal Manage" --ref main -f action=rollback -f target=srv -f confirm=ROLLBACK-prod
```

From a console on the VPN, as above but with the srv address and the srv SSH key:

```
PROD_SRV_VPN_IP=<srv VPN address> deploy/deploy.sh prod-srv vX.Y.Z
CONFIRM=ROLLBACK-prod PROD_SRV_VPN_IP=<srv VPN address> deploy/rollback.sh prod-srv [sha-<sha>]
PROD_SRV_VPN_IP=<srv VPN address> deploy/manage.sh status|logs|restart prod-srv
```

Secrets (names only): environment `prod` (here and on the public mirror) gains `PROD_SRV_VPN_IP`
and `PROD_SRV_SSH_KEY`, needed only for `target=srv`; every app secret is shared with aws.

Pending before the first srv deploy (operator):

- The srv user `<PROJECT_NAME>-prod` with its own key and Docker access (infra card), and the two
  secrets above.
- The public TLS terminator's route and certificate for `<PROJECT_ZONE>` to the srv proxy (infra
  card); it must set `X-Forwarded-For`, which the sign-in limits rely on.
- A check that no `<PROJECT_NAME>-web|cron|db|redis` container or `<PROJECT_NAME>-pg-data` /
  `-redis-data` volume already exists on the srv host.
- DNS for `<PROJECT_ZONE>` stays on AWS until the cut-over, which Prod Switch moves only with the
  operator's explicit OK (below).

### Prod Switch (aws <-> srv)

`Prod Switch` (`.github/workflows/prod-switch.yml`, every step a subcommand of
`deploy/prod_switch.sh`) moves prod between the AWS instance and the srv host, in either direction
and as often as needed: `to=srv` and back with `to=aws`. It runs only from `main`, in environment
`prod`, with `confirm=prod` and the release tag the live prod runs; it refuses a switch to the host
that is already live. The live host is whatever public DNS for `<PROJECT_ZONE>` points at: srv when
`<PROJECT_ZONE>` and `app.<PROJECT_ZONE>` resolve to the address of `dev.<PROJECT_ZONE>` (the public
TLS terminator in front of the srv host), aws when both resolve elsewhere. Only the infra prod stack
writes those records; nothing in this repository stores the live host.

```
gh workflow run "Prod Switch" --ref main -f to=srv -f version=vX.Y.Z -f confirm=prod                  # dry run
gh workflow run "Prod Switch" --ref main -f to=srv -f version=vX.Y.Z -f confirm=prod -f dry_run=false
gh workflow run "Prod Switch" --ref main -f to=aws -f version=vX.Y.Z -f confirm=prod -f dry_run=false # back
```

On the mirror add `-f source_sha=<primary sha>`, as for Kamal Deploy. `dry_run` is `true` by default:
the guards run, every other command that would touch a host, ECR, DNS or infra is printed as
`[dry-run] ...` and none runs.

1. `prepare`, `standby`, `target`, nothing touched: `prepare` checks the target over the VPN and
   resumes a service an earlier switch paused there. It refuses when the srv host is not reachable,
   when fe's containers do not run on the target, or when the live prod runs another version. For
   `to=aws` while the AWS instance does not answer (stopped, or deleted by a separate decision), it
   asks for the standby: Telegram asks for the `prod-dns` approval, and `standby`, in environment
   `prod-dns`, dispatches `Project Terraform Prod` with `prod_target=aws-standby` (the AWS instance
   running, re-created if absent; the records stay on srv, DNS does not move), the same way and with
   the same fallback as the DNS step (3.). `target` then waits up to 20 minutes for SSH on the AWS
   instance and checks it again (fe must run there too). That wait holds the shared VPN lock, so Dev
   Deploys started meanwhile fail fast. When the instance does not come up in time, nothing touched
   prod: run Prod Switch again once it answers, and the standby is skipped. Expect about an hour for a
   deleted instance (infra apply, bootstrap, fe and be deploys) and minutes for a stopped one. When
   the target does not run the release, `target` dispatches Kamal Deploy `target=<to>` with the
   release and `prod_switch_run=<this run>` and watches the whole run, off the VPN (that run needs
   the VPN lock itself); a fresh host gets its accessories through `kamal setup` there. Prod Switch
   holds `kamal-prod`, so that deploy runs in `kamal-prod-switch` instead, and its guard refuses
   unless the run is this in-progress Prod Switch on `main` (its title `Prod Switch to <to>`, so not
   a dry run) and `<to>` is not the live host.
2. `data`: the target must run the release. The live prod goes into Kamal maintenance (kamal-proxy answers 503 for `<PROJECT_NAME>` only,
   nothing else on a shared proxy) and its app containers stop (`docker stop`, not `kamal app stop`,
   which would also remove the service from kamal-proxy and end the 503). A final `pg_dump` of
   `<PROJECT_NAME>_prod` goes over SSH through the runner (its copy there is an owner-only temp file,
   deleted at exit) into the target's recreated database (`dropdb --force`, `createdb`, `pg_restore`),
   and the exact row counts of every table in `public` must match on both sides. That same dump is
   then kept on the target host as `~/backups/<PROJECT_NAME>-prod-<YYYYmmddTHHMMSSZ>-from-<aws|srv>.dump`
   of the SSH user (`<PROJECT_NAME>-prod` on srv, `ubuntu` on AWS), directory 700, file 600, never
   deleted or rotated by any workflow; the log prints its path, size, owner, mode and sha256, never its
   content. It is the backup of the old prod, for example once the AWS instance is deleted; check it on
   the host with `sha256sum <path>` and `docker exec -i <PROJECT_NAME>-db pg_restore --list < <path>`
   (read-only). When it cannot be kept, or its sha256 differs, the step fails before the boot and the
   abort runs; a dry run prints it as `[dry-run]` and keeps nothing. Then the target's app boots on the
   release. Telegram asks for the `prod-dns` approval (GitHub notifies the reviewers
   too, and a failed message does not fail the job); prod stays in maintenance until DNS moves, so
   approve promptly.
3. `prod-dns`: in the GitHub environment `prod-dns`, whose required reviewer is the operator. With
   `INFRA_PROD_DISPATCH_TOKEN` it dispatches `Project Terraform Prod` in
   `${INFRA_PROD_REPO:-<owner>/1_mvp_infra}@env/prod` with `project=<PROJECT_NAME>`, `action=apply`,
   `confirm=APPLY-PROD-<PROJECT_NAME>` and `prod_target=<to>`, and watches it. Without the token, or
   when the dispatch or the run fails, it prints that command and the record changes
   (`<PROJECT_ZONE>` and `app.<PROJECT_ZONE>` A records), to be applied through infra, never in the
   Route53 console. Either way it waits for public DNS to show the target (20 minutes after a
   successful apply, 60 for the operator).
4. `finalize`: `/health` must report the release on `https://<PROJECT_ZONE>`, the read-only smoke must
   pass and `https://app.<PROJECT_ZONE>/config.js` must set `API_URL` to `https://<PROJECT_ZONE>` and
   `ENV_NAME` to `prod`, each pinned to the address DNS now gives. Then `prod-previous` takes the old
   `prod-current` and `prod-current` the release (a no-op when it already is that image).
5. `finalize`: the old host's app containers stop, as in the freeze. Containers, accessories and
   volumes stay, and its service stays registered and in maintenance, so a switch back resumes it.
   The AWS instance itself is stopped or deleted only through infra, never by this workflow: after
   `to=srv`, infra's `prod_target=srv` has already stopped it, so an AWS host that no longer answers
   needs nothing stopped (the freeze stopped its app). An srv host that does not answer fails the job.

Rollback: a failure or cancellation in `data` after the freeze has started, or a refused or missing
`prod-dns` approval, runs abort: the live prod's app starts on the release (`kamal app start
--version`), maintenance ends and `/health` must answer. DNS was not touched. Before that, the abort
job checks the facts (`deploy/prod_switch.sh abort-check`): public DNS must still show the source,
and this run's `Switch DNS (operator approval)` job must never have begun (no runner, no step, in
the jobs API; a job cancelled while waiting for its approval has `started_at` set but neither). When
that check refuses, or the jobs API cannot be read, nothing is brought back and prod stays in
maintenance: go on as after DNS (below). When the abort itself fails, the report and the Telegram
message say prod may still be in maintenance: run
`PROD_ACTIVE_TARGET=<from> deploy/prod_switch.sh abort <from destination> sha-<sha>` from a
console. Once `prod-dns` has started (its output `touched=true`) nothing is undone automatically,
because DNS may have moved.
After DNS, from a console on the VPN with the deploy environment and both SSH keys:

- finish: once public DNS shows the target (re-run the infra apply if needed),
  `PROD_ACTIVE_TARGET=<to> deploy/prod_switch.sh finalize-public <to destination> sha-<sha>` and
  `deploy/prod_switch.sh stop-old <from destination>`;
- or go back: switch DNS back through infra (`prod_target=<from>`), then
  `PROD_ACTIVE_TARGET=<from> deploy/prod_switch.sh abort <from destination> sha-<sha>`.

Destinations are `prod` (aws) and `prod-srv` (srv). What is not moved: Redis (cache, rate-limit
counters, sessions; tokens live in Postgres), so a few counters start fresh. The downtime is the
data move, the approval wait, the infra apply and the DNS TTL (300 s).

Prerequisites (operator): fe deployed to the target first with fe's Kamal Deploy `target=<to>` (same
version and confirm; fe's own switch stops the old fe containers); the secrets of both hosts in
environment `prod` (`PROD_SSH_KEY`, `PROD_VPN_IP`, `PROD_SRV_SSH_KEY`, `PROD_SRV_VPN_IP`); the
environment `prod-dns` with the operator as required reviewer and the secret
`INFRA_PROD_DISPATCH_TOKEN` (fine-grained on the infra repository: actions read and write, and
contents read so the job can check the `prod_target` options; optional, without it the operator
applies by hand); the variable `INFRA_PROD_REPO` when the infra repository is not
`<owner>/1_mvp_infra`; the `prod_target` input of `Project Terraform Prod`, which must persist the
target so a later apply does not revert DNS.

Before each dispatch the job reads `Project Terraform Prod` from `env/prod` (`gh workflow view
--yaml`) and dispatches only a `prod_target` value it offers. A missing value (`aws-standby` until
the infra card that adds it lands on `env/prod`) gets a warning naming it and the print-and-wait
fallback, with nothing dispatched; an unreadable workflow is dispatched unchecked, and GitHub's
refusal of an unknown input falls back the same way. Until infra offers `aws-standby`, the operator
applies the printed standby by hand within the 20-minute wait, or applies it first and runs Prod
Switch again.

SSH host keys: Prod Switch connects with `StrictHostKeyChecking=accept-new`, the same trust Kamal's
own SSH gives these hosts on a fresh runner, and only over the authenticated mvp VPN. A pinned key
would refuse an AWS instance infra re-created with a new one.

Operator checks before the first real switch: `prod-dns` has the operator as required reviewer;
`INFRA_PROD_DISPATCH_TOKEN` and `INFRA_PROD_REPO` as above; infra `prod_target=aws-standby` on
`env/prod` for the standby path; then a `dry_run=true` run in each direction.

The whole run holds the `kamal-prod` concurrency group, so no deploy, rollback or restart starts
while prod is frozen. `prepare`, `target` (after a standby), `data`, `abort` and `finalize` hold the
shared VPN lock, so a Dev Deploy started meanwhile may need a re-run.

## Releases and hotfixes

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
2. Release PR `develop` → `main`, titled `PILOT-<n>: Release vX.Y.Z` (the release's own card, never
   `PILOT-0`; `pr-conventions-check` condition 5 fails a `PILOT-0: Release …` title, also on the
   release-prep PR) (`Type: chore`), merged by the operator by hand with a merge commit (decision 27);
   `TDD check` skips it, `changelog-check` passes it. Its body carries the version's changelog (decision 64): a `## Changelog` heading followed by
   exactly the output of `scripts/release-notes.sh vX.Y.Z`, which is also the text of the GitHub
   Release. `pr-conventions-check` (condition 4) fails it otherwise and runs again when the body is
   edited. Build the body from the changelog instead of typing it:
   ```
   { printf 'Release vX.Y.Z: develop into main.\n\n## Changelog\n\n'
     scripts/release-notes.sh vX.Y.Z
     printf '\nType: chore\n'; } > "${TMPDIR:-/tmp}/release-pr.md"
   gh pr create --base main --head develop --title "PILOT-<n>: Release vX.Y.Z" --body-file "${TMPDIR:-/tmp}/release-pr.md"
   ```
   More `## ` sections may follow the changelog; it ends at the next `## ` heading or the `Type:` line.
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
the host. On the mirror `Kamal Deploy` also needs `source_sha` (below).

**release-watch.** After every successful prod deploy, the `release-watch` job of `Kamal Deploy`
polls `https://<PROJECT_ZONE>/health` every 30 seconds for 10 minutes (each check must report the
deployed release) without the VPN, then takes the VPN once to count the GlitchTip issues of
`<PROJECT_NAME>-be-prod` first seen since the watch started (`deploy/glitchtip_issues.sh`, which
first checks the shape of the API answer). ✅ when every check passed and there is no new issue;
otherwise ❌ naming the failed checks and up to three issues. It **never rolls back**: a person
decides, with one of the paths below. The token is the secret `GLITCHTIP_API_TOKEN` in environment
`prod`: a GlitchTip API token with read-only scopes (`project:read`, `event:read`), never printed;
the API address is derived from `SENTRY_DSN` (or `GLITCHTIP_API_URL` in a console).
With `target=srv` the watch instead runs 3 minutes over the VPN against the srv host's proxy; see
"Prod on the on-prem srv host" above.

**Rollback, two ways**, both with the typed confirm `ROLLBACK-prod`. Both move the ECR tags
`prod-current`/`prod-previous` while the AWS host is the live prod; while srv is live, they move
`prod-aws-current`/`prod-aws-previous` instead (see "Prod on the on-prem srv host" above):

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

**Prod from the mirror (decision 43).** From v0.2.0 prod deploys only from the public mirror; this
repository still builds (Dev Deploy, build once) and tags the release. Runbook:

1. Release on the primary as in **Release flow** steps 1–4 (tag `vX.Y.Z` on `<D>`).
2. `publish-mirror.sh` (in `1_mvp_sdlc`) syncs the primary `main` to the mirror through its `develop`
   → PR → `main` (decision 51), puts the same tag on the mirror `main` and records
   `{tag, primary_sha, mirror_sha}` in `MIRROR_SOURCE.json` at the mirror's root.
3. On the mirror:
   `gh workflow run "Kamal Deploy" --ref main -f environment=prod -f version=vX.Y.Z -f source_sha=<D> -f confirm=prod`.
   The guard refuses unless `MIRROR_SOURCE.json` records `<D>` for that tag and the tag is annotated
   and on the mirror `main`; the image `sha-<D>` is promoted, never built.
4. `release-watch` runs on the mirror (✅/❌ to the prod alerts topic); roll back with `Kamal Manage` on
   the mirror (`prod-previous` or a sha), as above.

The mode is the repository variable `MIRROR`: on the primary (unset) `source_sha` is refused; on the
mirror (`MIRROR=true`) `develop-guard` is skipped and `main-guard` still runs. A hotfix takes steps
2–4 for its PATCH tag.

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
`Rails CI` also runs `scripts/check-public-repo.sh` (blocking, and run by the mirror publish
before publishing): tracked files must not contain internal IPs or hostnames, AWS account or
Route53 zone IDs, Trello, Notion or Telegram links and IDs, or local home paths; it prints only
`file:line`, and its documented exceptions are in the script.

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
(condition 3); a release PR titled `PILOT-<n>: Release vX.Y.Z` has a `## Changelog` section that is
the CHANGELOG.md section `[X.Y.Z]` verbatim (condition 4, decision 64); a release or release-prep PR
is titled with the release's own card, never `PILOT-0` (condition 5, decision 91). The title and body become the
squash commit.

`TDD check` does not check commits that are already on `main` (so a back-merge of `main` into
`develop` passes), and skips the release PR `develop` → `main`. It compares against the live base
branch (`origin/<base ref>`), not the base sha recorded for the event, so commits that come in by
merging `develop` never count as the pull request's own.

`changelog-check` runs on every pull request into `main` or `develop` (`bin/changelog-check`): a
`Type: feat` or `Type: fix` PR must change `[Unreleased]` in `CHANGELOG.md` or add a version section;
the label `skip-changelog` passes it. `Release` runs on every pushed `v*` tag (see "Releases and hotfixes").

## AI PR review

`.github/workflows/ai-review.yml` (check `AI review`, decision 32) reviews pull requests with
`anthropics/claude-code-action` (Sonnet 5.5, `claude-sonnet-5-5`, read-only tools) and posts the result as a
GitHub pull request review (decision 103 a).

**Switch.** The repository variable `AI_REVIEW`: only the exact value `on` runs a review. Anything
else, including unset, ends the check green in seconds with `AI review disabled (AI_REVIEW=off)` and
no model call. Set it with `gh variable set AI_REVIEW -b on` or `gh variable set AI_REVIEW -b off`;
the default and resting state is `off`.

**Secret.** `CLAUDE_CODE_OAUTH_TOKEN`, a Claude subscription token (decision 33 a; create it with
`claude setup-token`, then `gh secret set CLAUDE_CODE_OAUTH_TOKEN`, value pasted at the prompt),
passed as the action input `claude_code_oauth_token`. The alternative is an Anthropic API key
`ANTHROPIC_API_KEY`: change the input to `anthropic_api_key` with that secret by PR.

**Triggers.** Pull request `opened`, `reopened`, `ready_for_review`, `synchronize` (a push, also after
"changes requested") and `review_requested`. To ask for a re-review without a push, comment
`@claude review` on the PR (only users with write access; the action refuses others). On a head commit
that already has its review, the check runs again but no second review is posted; when its result has no
P0/P1 it still dismisses this workflow's own requests for changes, the head's own included, so a failed
dismissal is retried.

**Skips.** Dependabot, draft PRs and the release PR `develop` → `main`: the job is skipped, or green with
`AI review skipped: <reason>` when triggered by a comment. The factory's `archon/task-factory-*` PRs are
reviewed like any other (decision 103 a).

**What red means.** While `on`, the review found P0 or P1 findings: fix them and push, and it runs
again. It is also red when the review produced no valid summary (fail closed), including findings that
do not match the counts. The job log lists every P0/P1 as `AI review P1 path:line - title` with its
explanation, with the model text kept inert (no workflow commands); `ai-review/result.json` holds the
counts in the job workspace. The factory merge-gate
refuses non-green checks; making `AI review` a required check by branch protection follows with PUB.

**The review.** `bin/ai-review-submit` posts one review per head commit; it appears under "Reviewers" as
`github-actions`. Findings on lines of the diff are inline comments, whatever the file path (also paths
with spaces, quotes or non-ASCII characters); the others are listed in the review body, which ends with
`AI-REVIEW: P0=n P1=n P2=n`. Each finding is listed once: the model's summary at the top of the body does
not repeat them. The body and every inline comment are capped at 60000 characters (GitHub rejects more than
65536) and end with a truncation note when cut; the job log still lists every P0/P1. It requests changes on
P0/P1 and is a comment otherwise; a review without P0/P1, also a re-run on an already reviewed head,
dismisses this workflow's earlier requests for changes, even when the review itself could not be posted.
This workflow's own reviews are the `github-actions` reviews whose body starts with `<!-- ai-review -->`; a
`github-actions` review from another workflow neither stops the review of its head nor is dismissed. The
job log reports `REQUEST_CHANGES|COMMENT, n inline, m in
the body`. When GitHub refuses the inline comments, the review is posted once more with every finding in
the body. A review that cannot
be posted shows a warning and leaves the check as the gate decided. The step holds a write token, so it
runs the script from the workflow's own revision rather than the reviewed PR head checkout: the default
branch for an `@claude review` comment, the PR's merge commit (which also carries the PR's own workflow)
for a `pull_request` event.

**Cost.** One review per triggering event, at most 25 turns and a 15-minute job timeout; a push
cancels a running review. Reviews count against the Claude subscription's usage limits of the
token's account. Keep it `off` unless a review is wanted.

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

## NFR load run

`perf/nfr_load.rb` runs the todolist PRD §6 load scenarios before a release, against dev after a Dev Deploy: the
dashboard list (`GET /api/v1/projects`) for a user with 50 projects and 500 tasks, and a task status change, each
against p95 ≤ 300 ms on server timing (`X-Runtime`). Ruby stdlib only, from the repository root:

```
ruby perf/nfr_load.rb https://dev.pilot.up.km.ua
```

- Defaults: 100 requests per scenario at 10 a second, concurrency 10 (`NFR_REQUESTS`, `NFR_RATE`, `NFR_CONCURRENCY`).
  It prints server and client p50/p95/p99, the error rate and PASS or FAIL. Exit 0 both pass, 1 one fails, 2 refused,
  aborted or `CLEANUP INCOMPLETE`.
- It signs up one throwaway `nfr-load-…@example.com` user (one of the 5 sign-ups an hour per source IP) and never
  signs in. It deletes its projects and tasks and signs out, also on an abort or a Ctrl-C; the user stays.
- It refuses every host but `dev.pilot.up.km.ua`, `localhost` and `127.0.0.1`: never run it against prod. Record a
  run in `docs/features/<slug>/_review/nfr-load-<date>.md`.

## Troubleshooting

If you get an error "A server is already running", try:

```
rm tmp/pids/server.pid
```

Then start the server again.

