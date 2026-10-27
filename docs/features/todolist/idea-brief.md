---
status: Confirmed
owner: "OlegShevtsov1"
reviewers: []
updated_at: "2026-10-22"
feature_size: M
stage: "01"
depth: medium
ticket: "Trello #222 (card 6ad9e7a3497aff024e1928c0)"
value_score:
  rice: 125
  state: confirmed
  confirmed_at: "2026-10-22"
feasibility_state: proposed
---

# Idea Brief — todolist

## 1. Raw idea
A TODO list web app for individual users: a stylish landing page, sign-in with Google or with email/password, and after sign-in a stylish dashboard to create, organize and track projects and their tasks. The backend replaces simple_token_authentication with Devise plus Doorkeeper-issued API tokens (Google sign-in included) and reuses and extends the existing Project → Task API.

## 2. Problem
The backend has projects, tasks and sign-in by email and access token, but there is no public way to use it: no landing page, no sign-up for strangers, no Google sign-in and no dashboard. The current access token never expires, is the same on every sign-in and cannot be revoked per device, which is not acceptable once the app is open to the public.

## 3. Users
Public individuals: anyone on the internet who wants a simple place for personal projects and tasks. Each user sees only their own data (a project has exactly one owner). Reach is unknown because there is no traffic data; 500 sign-ups per quarter is a placeholder assumption. A second group is existing clients that sign in with email and access token today; they must keep working for a limited time.

## 4. Why now
The Trello card (#222) opens the todolist work as the first real product feature on top of the pilot platform, whose deploy, error-tracking and release pipeline is now in place (release 0.2.0, 2026-10-20). No external deadline was given.

## 5. Out of scope
- Sharing projects or teams (projects stay single-owner).
- Reminders, notifications and due dates.
- Social sign-in providers other than Google.
- A native mobile app (web only).
- Boards, text quick-add and sample-project seeding (parked, see §14).

## 6. Competitive analysis
| # | Product · URL | Features | Value per feature (1-5) | Gap |
|---|---|---|---|---|
| 1 | Todoist · https://todoist.com | Projects, natural-language task entry, free tier | Projects 4, quick entry 5, simplicity 4 | Paid for the fuller feature set |
| 2 | TickTick · https://ticktick.com | Many productivity tools, voice and email entry | Tools 5, simplicity 3 | More to learn; busy for a first-time user |
| 3 | Microsoft To Do · https://todo.microsoft.com | Subtasks, reminders, due dates, sync | Reminders 4, simplicity 4 | Tied to the Microsoft ecosystem |
| 4 | Google Tasks · https://tasks.google.com | Minimal personal tasks, free, Google-integrated | Simplicity 5, projects 1 | No real project grouping or progress view |
| 5 | Notion / Trello | Flexible databases, kanban boards, free personal tier | Flexibility 5, first-run ease 2 | Setup cost before first value |

Footnotes: all rows from web search on 2026-10-22, queries "Todoist Microsoft To Do TickTick Things comparison features sign in with Google projects tasks" and "Google Tasks Notion Trello free personal task manager landing page sign up features". Sources were comparison blogs and vendor-run pages, so details are secondhand; ratings are my reading of them, not measurements. Sign-in options of each product were not confirmed.

## 7. Strategic approaches

### Approach A — Google Sign-In on Existing Tokens
- **Thesis**: ship the whole journey on the current access-token sign-in, with Google as a second way to get the same token.
- **For whom**: first-time public visitors wanting a plain personal list.
- **Outcome metric**: unaided journey completion; baseline impossible today → 5 of 5 testers in a first moderated session (cohort size proposed).
- **Key trade-off**: keeps never-expiring, non-revocable tokens on a public app; the dashboard is functional, not stylish.
- **Effort signal**: S
- **Recommended?** ◯

### Approach B — Progress Board for Solo Makers
- **Thesis**: make the three task states the headline with a board per project, a cross-project "in progress" view, quick-add and a seeded sample project.
- **For whom**: individuals with several personal projects who outgrow plain checklists.
- **Outcome metric**: week-2 return rate; baseline none → target TBD.
- **Key trade-off**: far beyond the 2-week budget, and more is built before knowing whether the basic journey converts.
- **Effort signal**: L
- **Recommended?** ◯

### Approach C — Standard Tokens, Polished List
- **Thesis**: standard revocable API tokens for Google and email sign-in, old clients supported until a published cutoff, and a styled list dashboard with one-tap status change, per-project completed counts and guided empty states.
- **For whom**: public first-time users, plus existing token clients during the transition.
- **Outcome metric**: median time from landing to first completed task, unaided; baseline not measurable today → target TBD after the first moderated session.
- **Key trade-off**: most effort goes into the token migration and a polished core, not into differentiating features.
- **Effort signal**: M
- **Recommended?** ●

## 8. Multi-perspective feedback

### Engineer
- A touches the least code but leaves long-lived tokens that cannot be revoked per device.
- B adds many failure modes in one window and never says how old clients survive the full move.
- C runs old and new token checks side by side until the cutoff: moderate, known complexity that ends with one scheme.
- Any auth change here needs a decision record and a regression test; budget for both.

### Executive
- A is fastest to launch but undifferentiated, and its metric is a usability check, not a business outcome.
- B is the strongest retention bet, but week-2 return can only be measured after launch.
- C is the only plan that fits budget and retires legacy auth with an explicit cutoff; its metric can be read on day one.

### UX-researcher
- A works but feels like a bare utility and gives users no way to sign out a lost device.
- B has the best first run but is a lot to learn for a personal list; cut features would show as half-finished screens.
- C shortens the path to first value with guided empty states and one-tap progress; plainer than B but lowest friction.

### Synthesis matrix
|         | Engineer | Executive | UX |
|---------|:--------:|:---------:|:--:|
| App. A  | + reuses existing sign-in path | 0 ships fast, carries security debt | 0 works, plain, no session control |
| App. B  | − L effort exceeds two weeks | − overruns budget, unproven retention bet | + richest first run, more to learn |
| App. C  | 0 two token schemes until cutoff | + fits budget, retires legacy auth | + guided start, one-tap progress |

## 9. Trade-offs and edge cases

### Trade-offs per approach
| Approach | Pros | Cons |
|---|---|---|
| A | Smallest effort; no change for old clients | Security debt stays; weak differentiation |
| B | Strongest product vision | Cannot fit budget; unproven bet |
| C | Fits scope, fixes auth, measurable journey | Temporary double token handling; no standout feature |

### Edge cases
- A person signs up with email and later uses Google with the same address (and the reverse).
- Google email differs in case or changes after sign-up.
- A token expires while the user is typing a long task description.
- An old client keeps calling after the cutoff date.
- Deploy moment: old and new code run side by side and must accept each other's tokens.
- Deleting a project that still has tasks is refused by design; the dashboard must explain it.
- Sign-out or password change must also cut off the old access token.

## 10. Risks
- **Top (account takeover via unverified email)**: someone registers another person's email with a password; when the real owner later signs in with Google the identities are merged and the attacker keeps access. Shows up only as support tickets ("projects I didn't create"). Breaks the invariant that a user sees only their own data.
- Old access token keeps working after sign-out or password change, and the compatibility window has no exit signal unless old-header use is counted.
- Mass 401s at deploy or at the cutoff (cutover lockout).
- No rate limit on sign-in and sign-up (only the error endpoint has one): credential stuffing, junk accounts and a skewed funnel metric.
- Google vs password identity conflicts leave returning users locked out or with a second empty account.
- Sign-up error messages reveal which emails are registered.
- A bearer token kept in the browser can be stolen by any script on the page.

## 11. RICE — Claude proposed
- **Reach (R)**: 500 sign-ups/quarter — placeholder assumption for public individuals (§3); no traffic data. Confirmed by the user.
- **Impact (I)**: 2 — without it there is no public product (§2) and the Executive view rates C positive (§8). Confirmed.
- **Confidence (C)**: 0.5 — Reach is a guess, success target is TBD, competitor sources are secondhand (§15). Confirmed.
- **Effort (E)**: 4 person-weeks — Approach C is signal M (§7). Confirmed; conflicts with the 2-week budget (§15).
- **RICE = 500 × 2 × 0.5 / 4 = 125**
- **State**: confirmed

## 12. Feasibility — Claude proposed

- [☑] **Tech**: the base exists in the repo: Devise is installed, Project and Task services and endpoints exist, and the error endpoint already has a rate limit to reuse as a pattern. Doorkeeper and Google sign-in are new here. Confirmed.
- [☐] **Skills**: no earlier token-issuing or Google sign-in feature in the repository history (45 commits, mostly CI and deploy). Confirmed unchecked; mitigate with an ADR first and a small proof of concept.
- [☐] **Time**: 4 person-weeks against a stated ~2-week budget; no earlier product feature to compare. The user gave no preference, so it stays TBD (treated as unchecked).
- **State**: proposed (Time is unresolved)

## 13. Recommendation
**Selected: Approach C — Standard Tokens, Polished List.** RICE is 125 (§11), though with low Confidence. Feasibility is Tech ☑, Skills ☐, Time TBD (§12), so this is a conditional go. In the synthesis matrix (§8), C is positive for Executive ("fits budget, retires legacy auth") and UX ("guided start, one-tap progress") and neutral for Engineer ("two token schemes until cutoff"). The competitive gap (§6) is that Google Tasks has no real project grouping or progress view and Notion/Trello cost setup effort, which leaves room for a guided, polished list. A fixes none of the auth weakness; B does not fit the budget.

**Locked-in pointer**: the PRD commits to standard revocable tokens for Google and email sign-in, a published cutoff for old email+token clients, and a styled project/task dashboard with one-tap status change, completed counts and guided empty states. Scope must be cut or staffed to fit the budget.

## 14. Parked & rejected approaches
| # | Approach | Status | Reason | Revisit trigger |
|---|---|:---:|---|---|
| A | Google Sign-In on Existing Tokens | parked | Leaves non-revocable tokens on a public app | If the auth change cannot fit and a launch must happen first |
| B | Progress Board for Solo Makers | parked | L effort, unproven retention bet | After the first cohort shows the basic journey converts |

## 15. Open questions
- [ ] Budget conflict: 4 person-weeks vs ~2 weeks — add a person or cut scope? — owner: OlegShevtsov1, due: before write-prd
- [ ] Success target for "median time to first completed task" (baseline from first moderated session) — owner: OlegShevtsov1, due: write-prd
- [ ] Real Reach figure (marketing plan or audience) — owner: OlegShevtsov1, due: write-prd
- [ ] Length of the compatibility window and the cutoff date for old email+token clients — owner: OlegShevtsov1, due: architecture
- [ ] Email verification before linking a Google identity to a password account — owner: OlegShevtsov1, due: architecture
- [ ] Auth change and any contract change need an ADR plus a regression test (repo hard rule); the ADR belongs to the architecture stage, not here.
- [ ] Glossary terms to add to CONTEXT.md later: API token, Google sign-in, compatibility window — owner: OlegShevtsov1, due: write-prd
- [ ] Feasibility Time still TBD — owner: OlegShevtsov1, due: write-prd

## Related
- CONTEXT.md (glossary: user, project, task, task status, access token, sign-in)
- Trello card #222 (state.json in this folder)
- docs/architecture-map.md

## DoD self-check
- [x] 15 sections present
- [x] No anti-pattern terms (Postgres/Redis/etc.)
- [x] Length ≤ 5 pages (~2200 words)
- [x] Frontmatter status: Confirmed
- [x] RICE confirmed (state: confirmed)
- [ ] Feasibility confirmed (Time TBD, state: proposed)
- [x] Recommendation present with rationale citing 4 upstream sections (§6, §8, §11, §12)
