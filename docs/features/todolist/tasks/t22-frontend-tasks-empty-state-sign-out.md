---
id: T22
title: "Add task create and status change, the guided empty state and sign-out"
layer: "ui"
deps: ["T21"]
acs: ["AC-11", "AC-18", "AC-19", "AC-21"]
files_hint: ["src/routes/Dashboard.tsx", "src/components/", "src/**/*.test.tsx"]
owner: "OlegShevtsov1"
estimate: "L"
status: "todo"
repo: "1_mvp_pilot_fe"
---

# T22 — Add task create and status change, the guided empty state and sign-out

**Repository:** `1_mvp_pilot_fe`

## Why

The path to a first completed task ([PRD AC-11, AC-18, AC-19, AC-21](../PRD.md)).

## What

Add a task to a project (it starts not started), change its status in one action, show validation errors; a user with no projects is guided to create a first project and then a first task; a sign-out control calls `/api/v1/sign_out`, clears the stored tokens and opens sign-in.

## Definition of Done

- [ ] A new task appears as not started and each status change takes one action (AC-18)
- [ ] Empty name or description shows what is allowed (AC-19)
- [ ] A user with no projects is guided to a first project and then a first task (AC-21)
- [ ] Sign-out clears the tokens and shows sign-in (AC-11)
- [ ] Lint, typecheck and build clean

## Notes

Frontend repository. Shares `Dashboard.tsx` with T21, so it runs after it.
