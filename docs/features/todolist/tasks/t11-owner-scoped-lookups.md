---
id: T11
title: "Scope project and task lookups to the owner so other users' items are not found"
layer: "ports"
deps: ["T5"]
acs: ["AC-17", "AC-22"]
files_hint: ["app/controllers/api/v1/projects_controller.rb", "app/controllers/api/v1/tasks_controller.rb", "app/controllers/concerns/", "spec/controllers/", "spec/services/"]
owner: "OlegShevtsov1"
estimate: "M"
status: "todo"
repo: "1_mvp_pilot_be"
---

# T11 — Scope project and task lookups to the owner so other users' items are not found

**Repository:** `1_mvp_pilot_be`

## Why

Another user's item must look like a missing one ([ADR-0007](../adr/0007-scope-project-and-task-lookups-to-the-owner.md), PRD AC-17).

## What

Load projects only from the signed-in user's projects and tasks only from those projects; a miss is answered as not found with the existing error shape. `Ability` stays as a second line. A signed-out request still gets Not Authorized.

## Definition of Done

- [ ] Showing, updating or deleting another user's project or task gives the same answer as a missing one, for projects and tasks alike (AC-17)
- [ ] A request without valid access gets Not Authorized and reveals nothing (AC-22)
- [ ] The owner's own operations are unchanged
- [ ] Lint and Brakeman clean

## Notes

Public contract change (403 → 404): rswag specs and `swagger.json` follow in T15.
