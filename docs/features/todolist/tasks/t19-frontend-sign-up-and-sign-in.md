---
id: T19
title: "Build the sign-up and sign-in screens"
layer: "ui"
deps: ["T18"]
acs: ["AC-02", "AC-03", "AC-04", "AC-08", "AC-09", "AC-10"]
files_hint: ["src/routes/SignUp.tsx", "src/routes/SignIn.tsx", "src/**/*.test.tsx"]
owner: "OlegShevtsov1"
estimate: "L"
status: "todo"
repo: "1_mvp_pilot_fe"
---

# T19 — Build the sign-up and sign-in screens

**Repository:** `1_mvp_pilot_fe`

## Why

Email and password journeys ([PRD AC-02 to AC-04, AC-08 to AC-10](../PRD.md)).

## What

Two screens using the shared tokens: sign-up shows which field is wrong, says when an account exists, and lands on the dashboard; sign-in shows one message for wrong email or password and a wait message with the Retry-After time when limited.

## Definition of Done

- [ ] Valid sign-up and sign-in store the token pair and open the dashboard (AC-02, AC-08)
- [ ] Field errors are shown per field (AC-03); a taken email says to sign in (AC-04)
- [ ] Wrong email and wrong password show the same message (AC-09)
- [ ] A rate-limit answer shows a wait message (AC-10)
- [ ] Lint, typecheck and build clean

## Notes

Frontend repository; fetch stubbed as in `src/App.test.tsx`.
