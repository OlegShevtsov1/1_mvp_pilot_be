---
id: T15
title: "Run the project and task rswag specs under bearer auth and document the 404 answers"
layer: "tests"
deps: ["T11"]
acs: ["AC-14", "AC-15", "AC-16", "AC-18", "AC-19", "AC-20"]
files_hint: ["spec/requests/api/v1/", "spec/support/auth_helper.rb", "spec/schemas/", "swagger/v1/swagger.json"]
owner: "OlegShevtsov1"
estimate: "M"
status: "todo"
repo: "1_mvp_pilot_be"
---

# T15 — Run the project and task rswag specs under bearer auth and document the 404 answers

**Repository:** `1_mvp_pilot_be`

## Why

The existing project and task rules (AC-14 to AC-20) are now exercised by bearer tokens and the 404 answer ([PRD §5](../PRD.md)).

## What

Switch the request specs' auth helper to a bearer token (keep a legacy helper for T5's specs), add the 404 responses of ADR-0007, and make sure AC-14 to AC-16 (project create, edit, limits, delete with tasks) and AC-18 to AC-20 (task create, status change, validation, filter) each have a request spec; regenerate `swagger/v1/swagger.json`.

## Definition of Done

- [ ] Project create and rename, length limits and delete-with-tasks behave as AC-14, AC-15 and AC-16 say
- [ ] Task create (starts as not started), status change and validation behave as AC-18 and AC-19 say; the status filter behaves as AC-20
- [ ] Every project and task operation documents 401 and 404 and no longer documents 403
- [ ] Lint and Brakeman clean

## Notes

These behaviours exist today; the RED commit is the switch of the helper and the 404 expectations.
