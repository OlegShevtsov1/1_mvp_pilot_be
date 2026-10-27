---
id: T18
title: "Add the API client, the token store with refresh, the Content-Security-Policy and GOOGLE_CLIENT_ID config"
layer: "ui"
deps: ["T17"]
acs: []
files_hint: ["src/api/client.ts", "src/auth/tokenStore.ts", "src/config.ts", "docker/40-config-js.sh", "nginx.conf", "src/**/*.test.ts"]
owner: "OlegShevtsov1"
estimate: "L"
status: "todo"
repo: "1_mvp_pilot_fe"
---

# T18 — Add the API client, the token store with refresh, the Content-Security-Policy and GOOGLE_CLIENT_ID config

**Repository:** `1_mvp_pilot_fe`

## Why

Tokens are kept in localStorage and refreshed once on expiry ([ADR-0006](../adr/0006-short-access-token-with-rotating-30-day-idle-refresh-token.md), [SAD §6 flow 2](../sad.md)).

## What

A `fetch` wrapper that sends the bearer token, on a 401 refreshes once and repeats the request, and on a refused refresh clears the store and sends the user to sign-in keeping typed input; a token store over localStorage guarded by try/catch; `GOOGLE_CLIENT_ID` through `/config.js` with the existing safe-character check; a strict Content-Security-Policy header in nginx (own scripts and Google's sign-in script only).

## Definition of Done

- [ ] An expired access token is refreshed once and the request repeated without losing the caller's input
- [ ] A refused refresh clears the stored tokens and routes to sign-in
- [ ] The nginx policy test shows no inline script is allowed and only the app origin and Google are permitted
- [ ] `/config.js` carries the client id and the bundle check still shows no environment value compiled in
- [ ] Lint, typecheck and build clean

## Notes

Frontend repository. Types follow `swagger/v1/swagger.json` from this repo (sync-spec).
