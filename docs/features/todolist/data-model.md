---
status: Draft
feature: "todolist"
schema_source: "db/schema.rb"
migration_version: "7.2"
---

# Data model — todolist

Design for PRD `todolist` and SAD §4–§5 (ADR-0003 tokens, ADR-0004 Google identity, ADR-0005 legacy cutoff,
ADR-0006 refresh rotation). Projects and tasks are unchanged: their columns, limits and statuses already match the PRD
(`db/schema.rb:17-35`, `app/models/project.rb:2-5`, `app/models/task.rb:4`).

## Conventions found

| Convention | Value | Evidence |
|---|---|---|
| Migration version | `ActiveRecord::Migration[7.2]` | `db/migrate/20250313163641_create_tasks.rb:1`; schema `ActiveRecord::Schema[7.2]` at `db/schema.rb:13` |
| Primary keys | `bigint` id, Rails default (no `id:` option) | `db/schema.rb:17`, `db/schema.rb:27`, `db/schema.rb:37` |
| Timestamps | `t.timestamps`, both columns `null: false` | `db/schema.rb:20-21`, `db/migrate/20250313163629_create_projects.rb:7` |
| Soft delete | None. No `discarded_at` or `deleted_at` column and no `Discard` or `acts_as_paranoid` in any model | `db/schema.rb:17-50`, `app/models/user.rb:1-10`, `app/models/project.rb:1-12` |
| Foreign keys | `t.references ... null: false, foreign_key: true` in `create_table`; plain `add_foreign_key`, no cascade | `db/migrate/20250313163641_create_tasks.rb:8`, `db/schema.rb:52-53` |
| Index naming | `index_<table>_on_<columns>` (Rails default) | `db/schema.rb:24`, `db/schema.rb:47-49` |
| Counter caches | integer `*_count`, `default: 0, null: false` | `db/schema.rb:23`, `db/schema.rb:46` |
| Dependent deletes | model level: `has_many :projects, dependent: :destroy`; `has_many :tasks, dependent: :restrict_with_error` | `app/models/user.rb:9`, `app/models/project.rb:8` |

## Entities

### oauth_applications (new, migration 01)

The registered client that may ask for tokens: one row for the web SPA, created by a seed or task, `confidential:
false` because a browser cannot keep a secret.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | bigint | no | | primary key |
| name | string | no | | e.g. `todolist web` |
| uid | string | no | | public client id |
| secret | string | no | | stored hashed by Doorkeeper |
| redirect_uri | text | yes | | unused: no redirect flow (ADR-0004) |
| scopes | string | no | `''` | |
| confidential | boolean | no | `true` | the SPA row sets `false` |
| created_at, updated_at | datetime | no | | `t.timestamps` |

- Associations: `has_many :access_tokens` (Doorkeeper model).
- Indexes: `index_oauth_applications_on_uid` (unique).
- Foreign keys: none.

### oauth_access_tokens (new, migration 02)

One row per access token; the refresh token lives in the same row, so one sign-in is one row (ADR-0003, ADR-0006).
Sign-out sets `revoked_at` on the device's row; Google linking revokes every row of the user (AC-06, AC-11). A refresh
sets `revoked_at` and writes a new row.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | bigint | no | | primary key |
| resource_owner_id | bigint | no | | the user |
| application_id | bigint | no | | |
| token | string | no | | hashed (`hash_token_secrets`), 64 hex characters |
| refresh_token | string | yes | | hashed |
| previous_refresh_token | string | no | `''` | Doorkeeper's rotation check |
| expires_in | integer | yes | | 3600 seconds (ADR-0006) |
| scopes | string | yes | | |
| revoked_at | datetime | yes | | set by sign-out, linking and refresh |
| created_at | datetime | no | | the 30-idle-day rule is measured from the newest row of the chain |

- Associations: belongs to a user (owner) and an application. `User` gets `has_many :access_tokens, foreign_key:
  :resource_owner_id, dependent: :delete_all` so a user can still be deleted (answer below).
- Indexes: `index_oauth_access_tokens_on_resource_owner_id`, `..._on_application_id`, `..._on_token` (unique),
  `..._on_refresh_token` (unique).
- Foreign keys: `resource_owner_id → users`, `application_id → oauth_applications` (no cascade).
- No `updated_at`: Doorkeeper does not write one on this table.
- Purge (SAD §7): rows revoked or expired more than 30 days ago are deleted daily; a scan of the table at about
  240 000 rows is acceptable once a day, so no purge index is added now.

### identities (new, migration 03)

The Google account linked to a user (AC-05, AC-06). Only provider `google` exists in v1; `provider` keeps the
table from needing a rename if another provider is added (out of scope per PRD §3).

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | bigint | no | | primary key |
| user_id | bigint | no | | |
| provider | string | no | | `google` |
| uid | string | no | | Google's stable account identifier, never the email |
| created_at, updated_at | datetime | no | | `t.timestamps` |

- Associations: `User has_many :identities, dependent: :destroy`; `Identity belongs_to :user`.
- Indexes: `index_identities_on_user_id`; `index_identities_on_provider_and_uid` (unique, one Google account → one
  user); `index_identities_on_user_id_and_provider` (unique, one Google link per user).
- Foreign keys: `user_id → users`.
- Personal data: `uid` is a personal identifier of moderate sensitivity (PRD §6.1).

### legacy_token_uses (new, migration 04)

One row per user per day on which the legacy access token was used (AC-12, PRD §6 "counted daily, history kept ≥ 30
days"). The cutoff reads this table; the legacy smoke pass is not counted (SAD §10).

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | bigint | no | | primary key |
| user_id | bigint | no | | |
| used_on | date | no | | |
| uses_count | integer | no | `0` | incremented on each legacy request that day |
| created_at, updated_at | datetime | no | | `t.timestamps` |

- Associations: `User has_many :legacy_token_uses, dependent: :delete_all`.
- Indexes: `index_legacy_token_uses_on_user_id`; `index_legacy_token_uses_on_user_id_and_used_on` (unique, makes the
  daily increment an upsert); `index_legacy_token_uses_on_used_on` (cutoff query and the 60-day purge).
- Foreign keys: `user_id → users`.

### users (existing)

No column is added. Google-created users keep `encrypted_password` as the empty string its default allows
(`db/schema.rb:39`); Google linking sets it back to empty, which cancels the password (AC-06). The Devise
`password_required?` rule must accept this (model task). `authentication_token` stays until the contract release
below.

## Changes to existing tables

| Step | Migration | What it does | Safe while old code runs because |
|---|---|---|---|
| Expand | none | New tables only (01–04); `users` and `projects`/`tasks` are untouched | Old code ignores tables it does not know |
| Backfill | none | Nothing to copy: existing users keep their `authentication_token` and sign in again for new tokens; the new tables start empty | — |
| Contract 1 | `05_remove_authentication_token_index_from_users.rb` | Drops `index_users_on_authentication_token` concurrently (`db/schema.rb:47`) | Runs only at the cutoff, after the code stopped reading the column |
| Contract 2 | `06_remove_authentication_token_from_users.rb` | Drops `users.authentication_token` | Same release as 05; reversible by re-adding a nullable column (the old values are not recoverable) |

Migrations 05 and 06 are staged now but must be promoted only in the cutoff release (ADR-0005): no real legacy use for
7 days, the smoke script and contract on access tokens, and the `simple_token_authentication` code removed.

## Staged migrations

| File | Purpose |
|---|---|
| `migrations/01_create_oauth_applications.rb` | Registered clients for the token endpoint; promoted to `db/migrate/20261022142938_create_oauth_applications.rb` (T1) |
| `migrations/02_create_oauth_access_tokens.rb` | Access and refresh token rows with revocation; promoted to `db/migrate/20261022142939_create_oauth_access_tokens.rb` (T1) |
| `migrations/03_create_identities.rb` | Linked Google account per user; promoted to `db/migrate/20261022174859_create_identities.rb` (T2) |
| `migrations/04_create_legacy_token_uses.rb` | Daily legacy access token use count; promoted to `db/migrate/20261022174900_create_legacy_token_uses.rb` (T2) |
| `migrations/05_remove_authentication_token_index_from_users.rb` | Contract step 1, cutoff release only |
| `migrations/06_remove_authentication_token_from_users.rb` | Contract step 2, cutoff release only |

Staged under `docs/features/todolist/migrations/`; an implementing task promotes each to `db/migrate/` with a fresh
timestamp. `ruby -c` passes on all six. Doorkeeper is not installed before T3, so 01 and 02 were compared with the
generator template (`migration.rb.erb`) of the doorkeeper 5.9.9 gem fetched with `gem fetch`, not with the output of
an installed gem; they differ only where intended: `redirect_uri` is nullable, `resource_owner_id` is `null: false`
with a foreign key to `users`, and there is no `oauth_access_grants` table. T3 diffs the installed gem's
`doorkeeper:migration` output against them and adds a new migration for any other difference, since the
promoted files are append-only.

## Decisions and answers

- Doorkeeper tables: `oauth_applications` and `oauth_access_tokens` only. No `oauth_access_grants`, because no
  authorization-code flow exists (ADR-0004). Answer: applications + access tokens.
- Owner relation of `oauth_access_tokens`: plain foreign key to `users` in the repo's style, with `dependent:
  :delete_all` on the `User` model. Answer: plain foreign key + model cleanup.
- Contract migrations 05 and 06 staged now, marked for the cutoff release. Answer: stage it.
- Not asked, derived from the PRD and recorded here: one Google link per user and one user per Google account
  (unique indexes on `identities`); no soft delete, matching the repository.
