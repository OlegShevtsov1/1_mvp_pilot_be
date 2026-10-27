---
id: T21
title: "Build the dashboard with the project list, status filter and project create, rename and delete"
layer: "ui"
deps: ["T18"]
acs: ["AC-14", "AC-15", "AC-16", "AC-20", "AC-22"]
files_hint: ["src/routes/Dashboard.tsx", "src/components/", "src/**/*.test.tsx"]
owner: "OlegShevtsov1"
estimate: "L"
status: "todo"
repo: "1_mvp_pilot_fe"
---

# T21 — Build the dashboard with the project list, status filter and project create, rename and delete

**Repository:** `1_mvp_pilot_fe`

## Why

The user's overview ([PRD AC-14 to AC-16, AC-20, AC-22](../PRD.md)).

## What

A guarded route: a visitor or a signed-out device is sent to sign-in. The dashboard lists the user's projects with their tasks, filterable by task status, and lets the owner create, rename and delete a project, showing length errors and the 'still has tasks' explanation. User text is always rendered as text.

## Definition of Done

- [ ] A signed-out visitor opening the dashboard is sent to sign-in and sees no data (AC-22)
- [ ] The list shows only the user's data; the status filter shows only matching projects (AC-20)
- [ ] Create and rename show the new name; wrong lengths show the allowed length (AC-14, AC-15)
- [ ] Deleting a project with tasks shows why it is kept (AC-16)
- [ ] Lint, typecheck and build clean

## Notes

Frontend repository. No project or task text is rendered as markup.
