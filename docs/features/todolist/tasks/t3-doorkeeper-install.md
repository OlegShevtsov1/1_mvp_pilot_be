---
id: T3
title: "Install Doorkeeper with the password grant, one-hour tokens and refresh rotation"
layer: "infra"
deps: ["T1"]
acs: ["AC-08"]
files_hint: ["Gemfile", "Gemfile.lock", "config/initializers/doorkeeper.rb", "config/routes.rb", "db/seeds.rb", "spec/requests/oauth/"]
owner: "OlegShevtsov1"
estimate: "L"
status: "done"
repo: "1_mvp_pilot_be"
---

# T3 — Install Doorkeeper with the password grant, one-hour tokens and refresh rotation

**Repository:** `1_mvp_pilot_be`

## Why

Every sign-in issues its own revocable token pair ([ADR-0003](../adr/0003-issue-revocable-opaque-tokens-with-doorkeeper.md), [ADR-0006](../adr/0006-short-access-token-with-rotating-30-day-idle-refresh-token.md), [PRD AC-08](../PRD.md)).

## What

Add the Doorkeeper gem (reason in the PR description), configure it on top of Devise: password grant checked with Devise, 3600-second access tokens, rotating refresh tokens refused after 30 days, `hash_token_secrets`, no authorization-code flow. Mount `/oauth/token` and `/oauth/revoke`. Seed the public web application (`confidential: false`) from environment values.

## Definition of Done

- [x] A correct email and password at `/oauth/token` returns an access and a refresh token and leaves other devices' tokens valid (AC-08)
- [x] A refresh replaces the pair and revokes the old one; a refresh token 30 days old or revoked is refused
- [x] Stored token and refresh token values are hashes, not the plain secrets
- [x] Doorkeeper's own `doorkeeper:migration` output for the installed version differs from `oauth_applications` and `oauth_access_tokens` only where data-model.md 'Staged migrations' allows; any other difference gets a new migration
- [x] Lint and Brakeman clean

## Notes

New gem: the PR description gives the reason (security rules). Wrong-password behaviour and the failed-attempt counter belong to T7; here a wrong password only has to be refused.
