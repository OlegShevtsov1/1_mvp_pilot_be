---
id: T5
title: "Authenticate with a bearer token first, fall back to the legacy headers and count their use"
layer: "app"
deps: ["T3", "T4"]
acs: ["AC-12", "AC-13"]
files_hint: ["app/controllers/api/v1/base_controller.rb", "app/services/base_application/", "app/services/auth/legacy_usage.rb", "spec/services/", "spec/controllers/"]
owner: "OlegShevtsov1"
estimate: "L"
status: "todo"
repo: "1_mvp_pilot_be"
---

# T5 — Authenticate with a bearer token first, fall back to the legacy headers and count their use

**Repository:** `1_mvp_pilot_be`

## Why

No lockout during the switch, and evidence for the cutoff ([ADR-0005](../adr/0005-accept-legacy-headers-alongside-bearer-until-evidence-cutoff.md), PRD AC-12, AC-13).

## What

In `Api::V1::BaseController` authenticate the bearer access token first, else the legacy `X-User-Email` / `X-User-Token` pair; each legacy use increments today's `legacy_token_uses` row for the user (upsert). A `LEGACY_AUTH_ENABLED` setting (default on) turns the legacy path off for AC-13. A request marked as a pipeline call (the smoke script) is not counted. This is the authentication regression test the repo requires.

## Definition of Done

- [ ] A valid bearer token and a valid legacy pair both give the same access to the user's own data (AC-12)
- [ ] Each legacy request adds one to today's count for that user; bearer requests add nothing; a pipeline-marked request adds nothing
- [ ] With `LEGACY_AUTH_ENABLED` off a legacy request is refused with the existing Not Authorized answer and the user's data is unchanged (AC-13)
- [ ] A revoked or expired bearer token is refused and does not fall back to a stale legacy pair for another user
- [ ] Lint and Brakeman clean

## Notes

Authentication change: needs ADR-0003/0005 (done) and the regression test above. Shares `base_controller.rb` with T10 and T11, so they run after it.
