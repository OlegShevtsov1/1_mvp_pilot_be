---
id: T2
title: "Promote the staged identities and legacy_token_uses migrations"
layer: "migration"
deps: ["T1"]
acs: ["AC-06", "AC-12"]
files_hint: ["docs/features/todolist/migrations/03_create_identities.rb", "docs/features/todolist/migrations/04_create_legacy_token_uses.rb"]
owner: "OlegShevtsov1"
estimate: "S"
status: "todo"
repo: "1_mvp_pilot_be"
---

# T2 — Promote the staged identities and legacy_token_uses migrations

**Repository:** `1_mvp_pilot_be`

## Why

Google linking and the cutoff evidence need their tables ([ADR-0004](../adr/0004-exchange-verified-google-id-token-for-access-token.md), [ADR-0005](../adr/0005-accept-legacy-headers-alongside-bearer-until-evidence-cutoff.md)).

## What

Promote staged migrations 03 and 04 into `db/migrate/` with fresh timestamps; `db/schema.rb` follows. Do NOT promote 05 and 06: they are the contract step, shipped only in the cutoff release.

## Definition of Done

- [ ] A migration spec shows `identities` has unique `(provider, uid)` and unique `(user_id, provider)`, and `legacy_token_uses` has unique `(user_id, used_on)`
- [ ] The migrations apply and revert cleanly
- [ ] Migrations 05 and 06 are still only under `docs/features/todolist/migrations/`
- [ ] Lint and Brakeman clean

## Notes

Same migration lane as T1.
