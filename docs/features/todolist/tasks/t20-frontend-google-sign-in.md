---
id: T20
title: "Add the Google sign-in button and exchange the ID token"
layer: "ui"
deps: ["T18"]
acs: ["AC-05", "AC-06", "AC-07"]
files_hint: ["src/auth/google.ts", "src/routes/SignIn.tsx", "src/routes/SignUp.tsx", "src/**/*.test.tsx"]
owner: "OlegShevtsov1"
estimate: "M"
status: "todo"
repo: "1_mvp_pilot_fe"
---

# T20 — Add the Google sign-in button and exchange the ID token

**Repository:** `1_mvp_pilot_fe`

## Why

Sign-up without inventing a password ([ADR-0004](../adr/0004-exchange-verified-google-id-token-for-access-token.md), PRD AC-05 to AC-07).

## What

Load Google's sign-in script only on the sign-in and sign-up routes, send the ID token to `/oauth/token` with grant `google_id_token`, store the pair and open the dashboard; a refusal or cancelled step shows 'Google sign-in did not complete' with retry and email as options.

## Definition of Done

- [ ] A successful exchange stores the pair and opens the dashboard with the user's existing projects (AC-05, AC-06)
- [ ] A refusal or a cancelled step shows the message and changes nothing (AC-07)
- [ ] The Google script is not loaded on other routes
- [ ] Lint, typecheck and build clean

## Notes

Frontend repository; Google script stubbed in tests.
