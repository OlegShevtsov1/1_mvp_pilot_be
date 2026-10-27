---
id: T12
title: "Allow the Authorization header in CORS and read GOOGLE_CLIENT_ID from the environment"
layer: "wiring"
deps: []
acs: ["AC-08"]
files_hint: ["config/initializers/cors.rb", "config/project.env", "README.md", "spec/config/"]
owner: "OlegShevtsov1"
estimate: "S"
status: "done"
repo: "1_mvp_pilot_be"
type: "chore"
---

# T12 — Allow the Authorization header in CORS and read GOOGLE_CLIENT_ID from the environment

**Repository:** `1_mvp_pilot_be`

## Why

The browser app must send a bearer token cross-origin ([SAD §7](../sad.md)).

## What

Add `Authorization` to the allowed request headers and `Retry-After` to the exposed ones; document `GOOGLE_CLIENT_ID` (public value, from the environment, never committed) next to the other variables.

## Definition of Done

- [x] A CORS preflight with `Authorization` is allowed for the configured origins
- [x] No client id or secret value is committed
- [x] Lint and Brakeman clean

## Notes

Public repository: placeholder values only.
