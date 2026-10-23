---
id: T14
title: "Document the sign-up, token, sign-in, sign-out and profile operations in the rswag specs and regenerate swagger.json"
layer: "tests"
deps: ["T6", "T7", "T9", "T10"]
acs: ["AC-02", "AC-05", "AC-08", "AC-11"]
files_hint: ["spec/requests/api/v1/", "spec/requests/oauth/", "spec/schemas/", "spec/swagger_helper.rb", "swagger/v1/swagger.json"]
owner: "OlegShevtsov1"
estimate: "L"
status: "todo"
repo: "1_mvp_pilot_be"
---

# T14 — Document the sign-up, token, sign-in, sign-out and profile operations in the rswag specs and regenerate swagger.json

**Repository:** `1_mvp_pilot_be`

## Why

The generated contract must match [openapi.yaml](../contracts/openapi.yaml) (`.claude/rules/api.md`).

## What

rswag request specs and response schemas for `/oauth/token`, `/oauth/revoke`, `POST /api/v1/users`, deprecated `POST /api/v1/sign_in`, `POST /api/v1/sign_out` and `GET /api/v1/me`, with the bearer scheme added to `spec/swagger_helper.rb`; regenerate `swagger/v1/swagger.json`.

## Definition of Done

- [ ] Each operation has specs for every response listed in openapi.yaml (200/201/204, 400, 401, 422, 429)
- [ ] `swagger/v1/swagger.json` is regenerated and lists the bearer scheme and the deprecated legacy sign-in
- [ ] A spec fails if a response drifts from the schema
- [ ] Lint and Brakeman clean

## Notes

Generated file: regenerate, never hand-edit.
