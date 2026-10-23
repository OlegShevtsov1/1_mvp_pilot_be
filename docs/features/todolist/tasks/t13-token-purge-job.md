---
id: T13
title: "Add the daily token and legacy-use purge and its Kamal cron role"
layer: "infra"
deps: ["T1", "T2"]
acs: ["AC-08"]
files_hint: ["lib/tasks/", "config/deploy.yml", "config/deploy.dev.yml", "spec/lib/tasks/"]
owner: "OlegShevtsov1"
estimate: "M"
status: "todo"
repo: "1_mvp_pilot_be"
---

# T13 — Add the daily token and legacy-use purge and its Kamal cron role

**Repository:** `1_mvp_pilot_be`

## Why

Token rows grow with every refresh ([SAD §7](../sad.md), [data-model.md](../data-model.md)).

## What

A rake task deletes revoked or expired token rows older than 30 days and legacy-use rows older than 60 days, then a second Kamal role `cron` runs it daily from the same image. Failure or a missed run reports to GlitchTip.

## Definition of Done

- [ ] A task spec shows old revoked and expired rows are deleted and recent or active rows are kept
- [ ] Legacy-use rows older than 60 days are deleted, newer ones kept
- [ ] The deploy files define the `cron` role without changing the `web` role; a failed run raises an error that reaches GlitchTip
- [ ] Lint and Brakeman clean

## Notes

Never run `kamal remove` or `kamal proxy *` with `config/deploy.dev.yml` (shared proxy). The first dev run is checked by hand after Dev Deploy.
