# Tracker — todolist

> Status of every task in the epic. `implement-tasks` updates `done` as it commits each task.
> States: `todo` · `in_progress` · `blocked` · `review` · `done`. Estimates: S = 2 h, M = half a day, L = one day.

| # | Task | Layer | Repo | Owner | Estimate | Blocked by | Status |
|---|---|---|---|---|---|---|---|
| T1 | Promote the staged oauth_applications and oauth_access_tokens migrations | migration | 1_mvp_pilot_be | OlegShevtsov1 | S | — | done |
| T2 | Promote the staged identities and legacy_token_uses migrations | migration | 1_mvp_pilot_be | OlegShevtsov1 | S | T1 | done |
| T3 | Install Doorkeeper with the password grant, one-hour tokens and refresh rotation | infra | 1_mvp_pilot_be | OlegShevtsov1 | L | T1 | done |
| T4 | Add the user associations, Identity and LegacyTokenUse models and the Google-user password rule | domain | 1_mvp_pilot_be | OlegShevtsov1 | M | T1, T2 | done |
| T5 | Authenticate with a bearer token first, fall back to the legacy headers and count their use | app | 1_mvp_pilot_be | OlegShevtsov1 | L | T3, T4 | done |
| T6 | Sign-up issues a token pair and enforces the sign-up limit | app | 1_mvp_pilot_be | OlegShevtsov1 | M | T3 | done |
| T7 | Count failed sign-ins per source and refuse above ten a minute before the password is checked | app | 1_mvp_pilot_be | OlegShevtsov1 | L | T3 | done |
| T8 | Verify a Google ID token: signature, audience, issuer, expiry and verified email | app | 1_mvp_pilot_be | OlegShevtsov1 | M | — | done |
| T9 | Add the google_id_token grant that creates a user or links Google and cancels all existing access | app | 1_mvp_pilot_be | OlegShevtsov1 | L | T3, T4, T8 | done |
| T10 | Add POST /api/v1/sign_out for both authentication schemes | ports | 1_mvp_pilot_be | OlegShevtsov1 | M | T5 | done |
| T11 | Scope project and task lookups to the owner so other users' items are not found | ports | 1_mvp_pilot_be | OlegShevtsov1 | M | T5 | done |
| T12 | Allow the Authorization header in CORS and read GOOGLE_CLIENT_ID from the environment | wiring | 1_mvp_pilot_be | OlegShevtsov1 | S | — | done |
| T13 | Add the daily token and legacy-use purge and its Kamal cron role | infra | 1_mvp_pilot_be | OlegShevtsov1 | M | T1, T2 | todo |
| T14 | Document the sign-up, token, sign-in, sign-out and profile operations in the rswag specs and regenerate swagger.json | tests | 1_mvp_pilot_be | OlegShevtsov1 | L | T6, T7, T9, T10 | todo |
| T15 | Run the project and task rswag specs under bearer auth and document the 404 answers | tests | 1_mvp_pilot_be | OlegShevtsov1 | M | T11 | todo |
| T16 | Make bin/swagger_smoke check the contract with a bearer token and keep a marked legacy pass | tests | 1_mvp_pilot_be | OlegShevtsov1 | M | T5, T14, T15 | todo |
| T17 | Add client-side routing, the first shared CSS tokens and the landing page | ui | 1_mvp_pilot_fe | OlegShevtsov1 | M | — | done |
| T18 | Add the API client, the token store with refresh, the Content-Security-Policy and GOOGLE_CLIENT_ID config | ui | 1_mvp_pilot_fe | OlegShevtsov1 | L | T17 | done |
| T19 | Build the sign-up and sign-in screens | ui | 1_mvp_pilot_fe | OlegShevtsov1 | L | T18 | done |
| T20 | Add the Google sign-in button and exchange the ID token | ui | 1_mvp_pilot_fe | OlegShevtsov1 | M | T18 | done |
| T21 | Build the dashboard with the project list, status filter and project create, rename and delete | ui | 1_mvp_pilot_fe | OlegShevtsov1 | L | T18 | done |
| T22 | Add task create and status change, the guided empty state and sign-out | ui | 1_mvp_pilot_fe | OlegShevtsov1 | L | T21 | done |
| T23 | Give the landing page a stylish visual design (design tokens, theme, hero) | ui | 1_mvp_pilot_fe | OlegShevtsov1 | M | T17 | done |
| T24 | Give the dashboard a stylish visual design on the T23 tokens | ui | 1_mvp_pilot_fe | OlegShevtsov1 | M | T22, T23 | todo |

**Total:** 22 tasks — backend 16 tasks, about 9.75 person-days; frontend 6 tasks, about 5 person-days.
