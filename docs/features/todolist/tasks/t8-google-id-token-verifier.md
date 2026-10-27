---
id: T8
title: "Verify a Google ID token: signature, audience, issuer, expiry and verified email"
layer: "app"
deps: []
acs: ["AC-07"]
files_hint: ["app/services/auth/google_id_token_verifier.rb", "spec/services/auth/"]
owner: "OlegShevtsov1"
estimate: "M"
status: "todo"
repo: "1_mvp_pilot_be"
---

# T8 — Verify a Google ID token: signature, audience, issuer, expiry and verified email

**Repository:** `1_mvp_pilot_be`

## Why

Linking is safe only when Google vouches for the email ([ADR-0004](../adr/0004-exchange-verified-google-id-token-for-access-token.md), PRD AC-07).

## What

A service that fetches and caches Google's published signing keys and returns the verified email and account identifier, or a refusal. Dependency choice (a small JWT library or a Google verifier gem) is justified in the PR. No Google network call in tests: use fixture keys.

## Definition of Done

- [ ] A token with a valid signature, our audience, Google's issuer, a future expiry and a verified email returns the email and account id
- [ ] Wrong signature, wrong audience, wrong issuer, expired, or unverified email each return a refusal (AC-07)
- [ ] Keys are cached and refreshed when a key id is unknown; tests use fixture keys, no real network
- [ ] Lint and Brakeman clean

## Notes

Reads the client id from `GOOGLE_CLIENT_ID`; T12 adds the configuration.
