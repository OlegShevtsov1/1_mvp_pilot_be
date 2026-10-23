---
id: T7
title: "Count failed sign-ins per source and refuse above ten a minute before the password is checked"
layer: "app"
deps: ["T3"]
acs: ["AC-09", "AC-10"]
files_hint: ["app/controllers/api/v1/sessions_controller.rb", "app/services/auth/failed_sign_in_limit.rb", "config/initializers/doorkeeper.rb", "config/environments/production.rb", "spec/services/auth/", "spec/requests/"]
owner: "OlegShevtsov1"
estimate: "L"
status: "todo"
repo: "1_mvp_pilot_be"
---

# T7 — Count failed sign-ins per source and refuse above ten a minute before the password is checked

**Repository:** `1_mvp_pilot_be`

## Why

Password guessing must be capped ([PRD AC-09, AC-10](../PRD.md), [SAD §8](../sad.md)).

## What

A small counter in the existing rate-limit store, incremented only on a failed password sign-in, checked before verifying the password, for `/oauth/token` (password grant) and the legacy `sign_in`. Wrong email and wrong password give the same answer. Read the real client address from kamal-proxy's forwarded header and trust only that proxy.

## Definition of Done

- [ ] The 11th failed sign-in within a minute from one source is refused without checking the password and with a Retry-After header (AC-10)
- [ ] Successful sign-ins are not counted
- [ ] An unknown email and a wrong password give identical answers (AC-09)
- [ ] A request spec pins that the client address comes from the proxy header only when it comes from the proxy
- [ ] Lint and Brakeman clean

## Notes

Precedent: `app/controllers/errors_controller.rb` rate limit and its store.
