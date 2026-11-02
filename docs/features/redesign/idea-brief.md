---
status: Confirmed
owner: "OlegShevtsov1"
reviewers: []
updated_at: "2026-10-28"
feature_size: M     # set by sdlc:classify-size, not here
stage: "01"
depth: easy
ticket: "PILOT-368"
value_score:
  rice: 17.5
  state: confirmed
  confirmed_at: "2026-10-28"
feasibility_state: confirmed
---

<!-- Stage 01 → see SDLC/plugin/skills/interview/SKILL.md -->

# Idea Brief — redesign

## 1. Raw idea
Taken from the Trello card (the owner chose the card text as the baseline): "redesign: New design of the landing page and the cabinet." Functionality does not change. Reference templates: Mantis and SaaSyDark. The card's description section is empty; the notes on it say to check template licences before porting anything and, if our component library differs from the templates', to port only the look (colours, grid, typography, components), not the dependencies.

## 2. Problem
The product is a demo / portfolio MVP and its look must be presentable. The landing page was restyled twice on 2026-10-23, the sign-in, sign-up and dashboard screens have no common visual language yet, and the owner wants one consistent, modern look across all of them. No measured user complaint exists; the driver is the owner's judgement.

## 3. Users
- **Reviewers and demo audiences**: the people who look at the product (estimated ~50 per quarter, no real traffic data exists on the backend).
- **Visitors**: see the landing page, sign-up and sign-in screens.
- **Users**: see the cabinet (project list and tasks) after signing in.

## 4. Why now
The MVP is feature-complete for its pilot scope (landing, sign-in with Google or email, projects and tasks), so the remaining gap before showing it is visual polish. No external deadline is known.

## 5. Out of scope
- Any new feature or behaviour change; all existing screens keep their functions and flows.
- Copying template source code or adding a new component library as a dependency.
- Backend changes, API changes, new analytics or conversion tracking.
- New screens that do not exist today.

## 6. Competitive analysis
| # | Product · URL | Features | Value per feature (1-5) | Gap |
|---|---|---|---|---|
| 1 | Mantis (free edition) · https://mui.com/store/items/mantis-free-react-admin-dashboard-template/ | Dashboard layout, 7 demo pages, light look | Layout 4, components 4, landing 1 | Free edition is MIT but bound to a component library we do not use; no landing page; no dark mode (paid only) |
| 2 | DarkSaaS (closest match to "SaaSyDark") · https://astro.build/themes/details/darksaas/ | Dark landing page template, sold for ~$20 | Landing 4, cabinet 1 | Paid; licence terms unconfirmed; different web framework; no cabinet screens |

Footnotes: row 1 — 2026-10-28, query "Mantis free admin dashboard template licence MIT". Row 2 — 2026-10-28, query "SaaSyDark dark SaaS landing page template license"; no product named exactly "SaaSyDark" was found, DarkSaaS is the nearest match and the identification is unconfirmed. Neither template gives a ready result for our stack, so both serve as visual references only.

## 7. Strategic approaches

### Approach A — Re-skin through design tokens
- **Thesis**: Take only the visual language of the templates and apply it by rewriting the shared design tokens and the styles of the four screens, adding nothing new to the product.
- **For whom**: reviewers, visitors and users alike (§3).
- **Outcome metric**: screens on the new look: 0 of 4 → 4 of 4, approved by the owner/designer.
- **Key trade-off**: cheapest and licence-safe, but looks only as good as our own execution of the references.
- **Effort signal**: S
- **Recommended?** ●

### Approach B — Port Mantis wholesale
- **Thesis**: Adopt the template's component library and rebuild every screen from its ready components.
- **For whom**: users of the cabinet, who get the richest ready-made components.
- **Outcome metric**: screens on the new look: 0 of 4 → 4 of 4, plus a larger component set.
- **Key trade-off**: fastest to a "finished" cabinet look, but adds a heavy dependency and contradicts the "look only" decision.
- **Effort signal**: L
- **Recommended?** ◯

### Approach C — Own small design system
- **Thesis**: Build a small shared set of components (button, field, card) on the tokens, then rebuild the screens from them.
- **For whom**: the team, who gain reuse for future screens.
- **Outcome metric**: screens on the new look: 0 of 4 → 4 of 4, with shared components used on all of them.
- **Key trade-off**: better long-term consistency, but extra work the redesign alone does not need.
- **Effort signal**: M
- **Recommended?** ◯

## 8. Multi-perspective feedback
Easy depth: assessed by me without sub-agents.

### Engineer
- Existing styling is a single small token file plus per-screen styles, so a re-skin touches few files.
- Existing frontend tests may assert on markup; markup-preserving changes keep them green.
- A new component library (B) adds weight and a second styling approach.

### Executive
- A is the cheapest per unit of visible improvement and keeps the licence risk near zero.
- B buys breadth the pilot does not need.

### UX-researcher
- One consistent look across landing and cabinet matters more than any single screen.
- Contrast and focus states must survive the re-skin (dark look risk).

### Synthesis matrix
|         | Engineer | Executive | UX |
|---------|:--------:|:---------:|:--:|
| App. A  | +        | +         | 0  |
| App. B  | -        | 0         | +  |
| App. C  | 0        | 0         | +  |

Cells: A/Eng — few files, no new dependency; A/Exec — cheapest, licence-safe; A/UX — consistency depends on execution; B/Eng — heavy dependency, double styling; B/Exec — breadth the pilot lacks; B/UX — rich ready components; C/Eng — extra work, neutral risk; C/Exec — reuse value is speculative; C/UX — shared parts ensure consistency.

## 9. Trade-offs and edge cases

### Trade-offs per approach
| Approach | Pros | Cons |
|---|---|---|
| A | Smallest change, no new dependency, licence-safe | Quality depends on our own CSS work |
| B | Ready components, fast cabinet | Heavy dependency, breaks "look only" |
| C | Reusable, consistent | More work than a redesign needs |

### Edge cases
- Small phone screens and wide desktops on all four screens.
- Error, empty and loading states of the dashboard must be restyled too.
- Google call-to-action hidden when no Google client is configured (PILOT-319) must keep working.
- Keyboard focus, contrast and reduced-motion preferences.
- Existing frontend tests and end-to-end tests must still pass without weakening.
- Fonts or images taken from a template carry their own licence.

## 10. Risks
- **Top (devil's advocate view)**: a template's licence (DarkSaaS is paid and unconfirmed) is breached by copying styles or assets, which surfaces when the repository becomes public. Mitigation: use only the general visual language, copy no code, fonts or images until a licence is confirmed.
- Scope creep: "while redesigning" small behaviour changes sneak in.
- Visual approval is subjective, so the work can loop without an acceptance bar.
- Redesign breaks existing tests or accessibility.

## 11. RICE — Claude proposed
- **Reach (R)**: 50 — reviewers/demo audience per quarter (§3); no real traffic data.
- **Impact (I)**: 1 — presentability improvement, no functional gain (§2, Executive in §8).
- **Confidence (C)**: 0.7 — metric is only visual approval; licence of the second template unknown (§15).
- **Effort (E)**: 2 person-weeks — Effort signal S for Approach A (§7); four screens plus tokens.
- **RICE = R × I × C / E = 17.5**
- **State**: confirmed

## 12. Feasibility — Claude proposed
- [☑] **Tech**: shared design tokens already exist in the frontend and the landing page was restyled twice in one day (PILOT-269, PILOT-279, 2026-10-23).
- [☑] **Skills**: the same team shipped the previous visual work on the landing page and the dashboard (PILOT-248, PILOT-269).
- [☑] **Time**: comparable visual changes took 1–3 days each; four screens fit in the estimate.
- **State**: confirmed

## 13. Recommendation
**Selected: Approach A** — RICE is 17.5 with Feasibility 3/3 confirmed (§11, §12). In the synthesis matrix (§8) A scores + for Engineer (few files, no new dependency) and + for Executive (cheapest, licence-safe). The competitive gap (§6) is that neither Mantis (bound to a component library we do not use) nor DarkSaaS (paid, different framework, no cabinet) gives a ready result for our stack, so only their look is reusable; this matches the owner's decision to port the look only.

**Locked-in pointer**: the PRD covers a visual re-skin of Landing, SignIn, SignUp and Dashboard through design tokens and screen styles, with no behaviour change, no new dependency and no copied template code.

## 14. Parked & rejected approaches
| # | Approach | Status | Reason | Revisit trigger |
|---|---|:---:|---|---|
| B | Port Mantis wholesale | parked | Heavy dependency, contradicts "look only" | Product needs many rich components (tables, charts) |
| C | Own small design system | parked | Reuse not needed by four screens | A fifth or more screens are planned |

## 15. Open questions
- [ ] Which template pages exactly are the visual reference for each of the four screens? — owner: OlegShevtsov1, due: before write-prd
- [ ] Licence of SaaSyDark (possibly DarkSaaS): is it the intended template, and may its look be reused? — owner: OlegShevtsov1, due: before design work
- [ ] Who gives the visual approval (owner or a separate designer) and on which artifact (screenshots / mockups)? — owner: OlegShevtsov1, due: before write-prd
- [ ] Is a dark theme required, or only the dark landing page? — owner: OlegShevtsov1, due: before write-prd

## Related
- Trello card PILOT-368 (card id in `docs/features/redesign/state.json`)
- `CONTEXT.md` (terms: visitor, user, project, task)
- Earlier visual work in the frontend repository: PILOT-269, PILOT-279, PILOT-248
- Sibling feature: `docs/features/todolist/idea-brief.md`

## DoD self-check
- [x] 15 sections present
- [x] No anti-pattern terms (Postgres/Redis/etc.)
- [x] Length ≤ 5 pages (~2200 words)
- [x] Frontmatter status: Confirmed
- [x] RICE confirmed (state: confirmed)
- [x] Feasibility confirmed (state: confirmed)
- [x] Recommendation present with rationale citing 4 upstream sections (§6, §8, §11, §12)
