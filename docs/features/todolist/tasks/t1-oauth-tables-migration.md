---
id: T1
title: "Promote the staged oauth_applications and oauth_access_tokens migrations"
layer: "migration"
deps: []
acs: ["AC-08"]
files_hint: ["docs/features/todolist/migrations/01_create_oauth_applications.rb", "docs/features/todolist/migrations/02_create_oauth_access_tokens.rb"]
owner: "OlegShevtsov1"
estimate: "S"
status: "todo"
repo: "1_mvp_pilot_be"
---

# T1 — Promote the staged oauth_applications and oauth_access_tokens migrations

**Repository:** `1_mvp_pilot_be`

## Why

The token model needs its tables first ([ADR-0003](../adr/0003-issue-revocable-opaque-tokens-with-doorkeeper.md), [data-model.md](../data-model.md)).

## What

Promote staged migrations 01 and 02 into `db/migrate/` with fresh timestamps and let Rails regenerate `db/schema.rb`. Compare the column set with the installed Doorkeeper generator's output first (data-model.md, 'Staged migrations') and fix the staged files before promoting if they differ.

## Definition of Done

- [ ] A migration spec shows both tables exist with the unique indexes on `uid`, `token` and `refresh_token` and the two foreign keys
- [ ] The migrations apply and revert cleanly on a database that already holds users, projects and tasks
- [ ] `db/schema.rb` changes only as the output of running the migrations
- [ ] Lint and Brakeman clean

## Notes

First migration of the ordered sequence; T2 follows in the same lane. Never edit an existing file under `db/migrate/`.
