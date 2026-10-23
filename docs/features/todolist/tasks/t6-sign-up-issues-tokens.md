---
id: T6
title: "Sign-up issues a token pair and enforces the sign-up limit"
layer: "app"
deps: ["T3"]
acs: ["AC-02", "AC-03", "AC-04", "AC-04b"]
files_hint: ["app/controllers/api/v1/users_controller.rb", "app/services/users/create.rb", "spec/services/users/", "spec/controllers/"]
owner: "OlegShevtsov1"
estimate: "M"
status: "done"
repo: "1_mvp_pilot_be"
---

# T6 — Sign-up issues a token pair and enforces the sign-up limit

**Repository:** `1_mvp_pilot_be`

## Why

A new user lands signed in on this device ([PRD AC-02 to AC-04b](../PRD.md), [openapi.yaml](../contracts/openapi.yaml) `createUser`).

## What

`Users::Create` also issues a token pair for the calling device and returns `access_token`, `refresh_token`, `expires_in` next to the legacy `authentication_token`. More than 5 sign-ups an hour from one source are refused with a Retry-After header (existing rate-limit store).

## Definition of Done

- [x] Valid sign-up returns the three new fields and the legacy token (AC-02)
- [x] Malformed email, short password and mismatched confirmation create no user and name the field (AC-03)
- [x] A taken email creates no second user and says an account exists (AC-04)
- [x] The 6th sign-up in an hour from one source is refused with a wait message (AC-04b)
- [x] Lint and Brakeman clean

## Notes

The client address is read through the proxy-aware helper added in T7; until then use `request.remote_ip`.
