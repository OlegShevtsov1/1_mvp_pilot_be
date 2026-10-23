---
id: T10
title: "Add POST /api/v1/sign_out for both authentication schemes"
layer: "ports"
deps: ["T5"]
acs: ["AC-11", "AC-11b"]
files_hint: ["app/controllers/api/v1/sign_out_controller.rb", "app/services/auth/revoke_device.rb", "config/routes.rb", "spec/"]
owner: "OlegShevtsov1"
estimate: "M"
status: "todo"
repo: "1_mvp_pilot_be"
---

# T10 — Add POST /api/v1/sign_out for both authentication schemes

**Repository:** `1_mvp_pilot_be`

## Why

Sign-out ends this device's access ([PRD AC-11, AC-11b](../PRD.md), [openapi.yaml](../contracts/openapi.yaml) `signOut`).

## What

With a bearer token: revoke that token and its refresh token. With the legacy headers: rotate the user's legacy token so it stops working for every device that uses it. Answer 204.

## Definition of Done

- [ ] After sign-out on device A its tokens are refused while device B still works (AC-11)
- [ ] Sign-out with the legacy headers makes the old legacy token useless for every device using it (AC-11b)
- [ ] An unauthenticated call gets the existing Not Authorized answer
- [ ] Lint and Brakeman clean

## Notes

Shares `config/routes.rb` and the base controller lane with T5.
