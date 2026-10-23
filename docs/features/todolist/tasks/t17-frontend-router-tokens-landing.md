---
id: T17
title: "Add client-side routing, the first shared CSS tokens and the landing page"
layer: "ui"
deps: []
acs: ["AC-01"]
files_hint: ["src/main.tsx", "src/App.tsx", "src/routes/", "src/styles/tokens.css", "package.json"]
owner: "OlegShevtsov1"
estimate: "M"
status: "todo"
repo: "1_mvp_pilot_fe"
---

# T17 — Add client-side routing, the first shared CSS tokens and the landing page

**Repository:** `1_mvp_pilot_fe`

## Why

A visitor must see what the app does and both ways to start ([PRD AC-01](../PRD.md), [ADR-0002](../adr/0002-client-side-spa-in-existing-react-app.md)).

## What

Add a router dependency (reason in the PR), routes for landing, sign-up, sign-in and dashboard, and a first shared `tokens.css` (colours, spacing, type) in plain CSS like the existing code. The landing page explains the app and offers Google and email sign-up; it shows no projects or tasks. Compose the existing `App` / `ErrorFallback` conventions, no second styling system.

## Definition of Done

- [ ] The landing route renders the explanation and both start options and no project data (AC-01)
- [ ] Unknown paths still fall back to the app; the existing config, Sentry and error-boundary tests stay green
- [ ] No colour or size is hard-coded outside `tokens.css` in the new files
- [ ] Lint, typecheck and build clean

## Notes

Runs in the frontend repository. Existing precedent: `src/App.tsx` with its test.
