---
id: T4
title: "Add the user associations, Identity and LegacyTokenUse models and the Google-user password rule"
layer: "domain"
deps: ["T1", "T2"]
acs: ["AC-06", "AC-12"]
files_hint: ["app/models/", "spec/models/", "spec/factories/"]
owner: "OlegShevtsov1"
estimate: "M"
status: "todo"
repo: "1_mvp_pilot_be"
---

# T4 — Add the user associations, Identity and LegacyTokenUse models and the Google-user password rule

**Repository:** `1_mvp_pilot_be`

## Why

The services need models for tokens, the Google link and the daily legacy count ([data-model.md](../data-model.md)).

## What

`User` gets `has_many :access_tokens` (Doorkeeper, `dependent: :delete_all`), `has_many :identities` (`dependent: :destroy`) and `has_many :legacy_token_uses` (`dependent: :delete_all`); new `Identity` and `LegacyTokenUse` models with validations matching the unique indexes; Devise `password_required?` accepts a user with an empty password who has an identity. Factories for all.

## Definition of Done

- [ ] Model specs cover the associations, the uniqueness validations and `dependent` behaviour
- [ ] Destroying a user with tokens, an identity and legacy-use rows succeeds and removes them
- [ ] A user with an identity and no password is valid; a password user without one still needs a password
- [ ] Lint and Brakeman clean

## Notes

Does not touch controllers. No existing column is changed.
