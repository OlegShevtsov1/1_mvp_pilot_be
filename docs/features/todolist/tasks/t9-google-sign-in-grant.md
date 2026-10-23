---
id: T9
title: "Add the google_id_token grant that creates a user or links Google and cancels all existing access"
layer: "app"
deps: ["T3", "T4", "T8"]
acs: ["AC-05", "AC-06", "AC-07"]
files_hint: ["config/initializers/doorkeeper.rb", "app/services/auth/google_sign_in.rb", "app/services/auth/link_identity.rb", "spec/services/auth/", "spec/requests/oauth/"]
owner: "OlegShevtsov1"
estimate: "L"
status: "todo"
repo: "1_mvp_pilot_be"
---

# T9 — Add the google_id_token grant that creates a user or links Google and cancels all existing access

**Repository:** `1_mvp_pilot_be`

## Why

Google sign-in with safe linking ([ADR-0004](../adr/0004-exchange-verified-google-id-token-for-access-token.md), PRD AC-05 to AC-07).

## What

A custom Doorkeeper grant `google_id_token`: verify with T8; email unknown → create the user and the identity; email known (compared ignoring capital letters) → link, set the password empty, revoke every access token of the user and rotate the legacy token; then issue a token pair. Failure → `invalid_grant`, nothing created or linked.

## Definition of Done

- [ ] An unknown verified email creates a user with an identity and returns a token pair (AC-05)
- [ ] A verified email of a password user links Google; afterwards the old password sign-in, every earlier access and refresh token and the legacy token are refused, and the existing projects are visible with the new token (AC-06)
- [ ] A capital-letter variant of the email links the same user, never a second one (AC-06)
- [ ] Unverified email or a cancelled/invalid token creates and links nothing (AC-07)
- [ ] Lint and Brakeman clean

## Notes

Authentication change with a regression test (above). Shares `config/initializers/doorkeeper.rb` with T3 and T7, so it runs after them.
