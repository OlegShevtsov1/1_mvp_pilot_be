---
id: T16
title: "Make bin/swagger_smoke check the contract with a bearer token and keep a marked legacy pass"
layer: "tests"
deps: ["T5", "T14", "T15"]
acs: ["AC-12"]
files_hint: ["bin/swagger_smoke", "spec/bin/", "bin/wait-dev-deploy"]
owner: "OlegShevtsov1"
estimate: "M"
status: "todo"
repo: "1_mvp_pilot_be"
type: "chore"
---

# T16 — Make bin/swagger_smoke check the contract with a bearer token and keep a marked legacy pass

**Repository:** `1_mvp_pilot_be`

## Why

The smoke check runs on every dev and prod deploy and must not lock out or inflate the cutoff count ([SAD §10 QG-2](../sad.md)).

## What

Sign up, take the bearer token and run the authenticated checks with it; keep one legacy pass (using the legacy token returned at sign-up) marked as a pipeline call so T5 does not count it; remove the legacy pass when `LEGACY_AUTH_ENABLED` is off. Another user's project is expected to answer 404.

## Definition of Done

- [ ] The bearer pass checks sign-up, `me`, project and task create, read, update and delete, and sign-out
- [ ] The legacy pass runs only while the legacy path is enabled and adds nothing to the legacy-use count
- [ ] Another user's project answers 404 in the smoke check
- [ ] Lint clean; the existing spec for the script is updated and green

## Notes

Runs against dev after every deploy: coordinate the first run with Dev Deploy.
