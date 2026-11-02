---
feature: redesign
status: Approved
owner: OlegShevtsov1
updated_at: 2026-10-29
---

# Design spec: redesign (PILOT-368)

## 1. Raw request

> redesign: Новий дизайн лендінгу та кабінету. Функціональність не змінюється.
> (Trello card 368: "redesign: New design of the landing page and the cabinet. Functionality does not change.")

Owner's scope change, 2026-10-29 (PRD §1): the first implementation of T5–T9 was rejected because it did not
resemble the references. The landing page takes the full DarkSaaS look; sign-in and sign-up take the Mantis auth
pages; the cabinet takes the Mantis dashboard (sidebar, header, cards). This spec gives the owner HTML mockups to
approve before `/sdlc:break-tasks` replaces T5–T9 and before any code.

## 2. Why now

- **Problem:** the four screens and the crash screen have no common visual language, and the earlier "layout rhythm
  only" restyle did not resemble DarkSaaS or Mantis (PRD §1).
- **User:** visitors and users of the demo MVP, and the reviewers and demo audiences who meet the product as them.
- **Trigger:** the MVP is feature-complete for its pilot scope; visual polish is the remaining gap before showing it.
- **Success outcome:** the owner approves each screen from screenshots (PRD §6, 4 of 4 by 2026-11-30), with 0
  behaviour regressions.

## 3. Evidence sources

| Status | Source | What it proves |
|---|---|---|
| Confirmed | `docs/features/redesign/PRD.md` (Approved, #130) | Scope, AC-01..AC-16, NFRs, the landing page always dark, the phone sidebar toggle, free wording |
| Confirmed | `docs/features/redesign/sad.md` (Approved, #131) | §5 building blocks, §6 flows, §8 theming / design values / responsive rules (breakpoints `48rem`, `64rem`, 1200 px column) |
| Confirmed | ADR-0002 … ADR-0006 | Stylesheet guard; value-first rollout; shared `base.css`; landing palette as `.palette-landing` override of the same role names; Public Sans body, Space Grotesk display |
| Observed | fe `src/styles/tokens.css` (T2, merged) | Mantis light and dark role values used in the mockups unchanged |
| Observed | fe `src/styles/base.css`, `src/routes/BrandMark.tsx` (branch `feature/PILOT-379-base-stylesheet-brand-mark`, fe #77) | Page shell, `.brand`, shared button, link, input, focus and alert rules; the brand mark SVG |
| Observed | fe `src/routes/Landing.tsx`, `SiteChrome.tsx` | Landing sections, the Google and email-only call-to-action labels, feature texts, the decorative preview, legal links |
| Observed | fe `src/routes/SignIn.tsx`, `SignUp.tsx`, `TextField.tsx`, `src/auth/credentials.ts` | Fields, links, alerts, field messages, disabled-while-pending submit |
| Observed | fe `src/routes/Dashboard.tsx`, `ProjectForm.tsx`, `src/api/projects.ts` | Sidebar, top bar and its `Projects menu` toggle, search with `/`, chips and select filters, project and task actions, every state text |
| Observed | fe `src/ErrorFallback.tsx`, `src/main.tsx` | Crash screen text; it renders in `Sentry.ErrorBoundary` outside the router |
| Proposed | Mockups (§13) | The look of each screen, the landing palette values, new landing wording |

## 4. Current user flow

1. **Start:** a visitor opens `/` (landing) or any unknown address (also the landing page).
2. **Action:** the visitor starts through sign-up (`/sign-up`) or sign-in (`/sign-in`), by email or, when a Google
   client is configured, with Google's button.
3. **System response:** sign-up validates email, password length and confirmation on the client, then the server;
   sign-in shows "Wrong email or password." on refusal; the submit button is disabled while the request runs.
4. **Success:** the user lands in the cabinet (`/dashboard`), which loads the projects (loading → list, empty-list
   guidance or first-task guidance) and offers create, rename, delete, add task, change status, filter (chips,
   select, search, sidebar choice) and sign out.
5. **Recovery:** load failure shows an alert and Retry; delete of a project with tasks shows a refusal under the
   project; a visitor without tokens is sent to sign-in; a render error shows the crash screen.

## 5. Target user flow

1. **Start:** same routes; the landing page is always dark in the DarkSaaS look; the other screens follow the device
   theme in the Mantis look.
2. **Action:** same actions, same targets, same order of fields; the auth switch link moves into the card head.
3. **System response:** same messages and states, restyled; loading shows static placeholders when motion is reduced.
4. **Success:** same outcome; one brand mark on every screen.
5. **Recovery:** same recovery paths; every alert keeps its `alert` role and exact text.

## 6. Requirements

| ID | Status | Requirement | Source |
|---|---|---|---|
| BR-01 | Confirmed | The landing page shows, always dark, a header with the brand and Sign in, a hero (badge, gradient headline, lead, two starts, the decorative cabinet preview over a glowing orb), the four feature cards, a three-step "How it works" section, a final call-to-action card and a footer with the legal links. | PRD §1, AC-01; ADR-0005; mockup Landing |
| BR-02 | Confirmed | Without a Google client the landing page shows the email-only labels (Sign up, Sign in, "Sign in with email" card) and mentions Google nowhere. | PRD AC-02; `Landing.tsx` |
| BR-03 | Confirmed | Every landing call to action leads only to `/sign-up` or `/sign-in`; no new section adds a link, form or tracking. | PRD §3 |
| BR-04 | Confirmed | Sign-up and sign-in show the brand at the top left and one centred auth card (max 475 px) with the title and the switch link in its head, Google's slot and an "or with email" divider when configured, labelled fields, the alert and a full-width primary button; "Back to the start" and the legal links stay below. | PRD §1 (Mantis auth); mockups Sign-up, Sign-in |
| BR-05 | Observed | Field messages stay word for word ("Enter an email address like name@example.com.", "Password must be at least 6 characters.", "The passwords do not match."), sit under their field, keep `aria-describedby`, and turn the field border to the error colour. | `credentials.ts`, `TextField.tsx`; AC-04 |
| BR-06 | Observed | Sign-in shows "Wrong email or password." as an alert above the button and stays on sign-in; sign-up keeps the taken-email (Google-aware) and account-created alerts; the submit button stays disabled while pending. | `SignIn.tsx`, `SignUp.tsx`; AC-06 |
| BR-07 | Confirmed | The cabinet at ≥ 768 px shows a 280 px sidebar (brand, New project, "Projects" caption over All projects and each project with its task count, the shortcuts hint, Sign out), a 64 px top bar holding the search, and content cards: a filter card (status chips and the Task status select) and one card per project. | PRD §1 (Mantis dashboard); SAD §5; mockup Cabinet |
| BR-08 | Confirmed | Below 768 px the sidebar sits behind the one "Projects menu" toggle in the top bar; it opens as a drawer under the top bar so the toggle stays reachable; the search sits above the filter card. | PRD §1 Clarified, AC-11; SAD §8 |
| BR-09 | Observed | Each project card keeps Rename, Delete, Add task and, per task, its status icon, name, status label (now a chip) and the two "Mark …" buttons with their accessible names. | `Dashboard.tsx`; AC-07 |
| BR-10 | Observed | Cabinet states keep their texts: loading "Loading your projects…", empty "You have no projects yet. Start by creating your first project." + "Create your first project", first task "Next, add a first task to your project." + "Add a task", failure "Could not load your projects. Try again later." + Retry, no match "No project matches these filters." + "Clear filters", delete refused "A project that still has tasks cannot be deleted, so it was kept.", and the new-project form. | `Dashboard.tsx`, `ProjectForm.tsx`; AC-08, AC-10 |
| BR-11 | Confirmed | The crash screen shows the brand (not a link), a drawn illustration and "Something went wrong." in the display face, with "The error was reported." as a second line when it applies; its `alert` role stays and no action is added. | PRD AC-10; `ErrorFallback.tsx`; mockup Crash |
| BR-12 | Confirmed | Sign-up, sign-in, the cabinet and the crash screen follow the device theme (light when no preference) with the T2 Mantis values; the landing page uses one `.palette-landing` block of the same role names and is dark under both emulations. | PRD AC-12; ADR-0005 |
| BR-13 | Confirmed | Body text is Public Sans; headings, the brand and the landing headline are Space Grotesk; both self-hosted from `@fontsource-variable/*`. | ADR-0006 |
| BR-14 | Confirmed | All colours, gradients, sizes, spacing, radii and shadows come from design values; the new roles the mockups need are added as tokens (§9), never as literals. | PRD AC-15, §6; ADR-0002 |
| BR-15 | Confirmed | At 360, 390 and 768 px no screen scrolls sideways and every action stays visible or behind the one sidebar toggle; at 1440 px the content column is centred and at most 1200 px. | PRD AC-11, AC-16 |
| BR-16 | Confirmed | Every link, button and field shows the 3 px focus ring in `--color-focus`; under reduced motion no animation or transition runs (the orb glow, preview fade-in and hover changes only under `prefers-reduced-motion: no-preference`; loading is static). | PRD AC-13, AC-14 |
| BR-17 | Confirmed | Every text and non-text pair the mockups introduce passes contrast (≥ 4.5:1 text, ≥ 3:1 non-text) in each palette; gradient text is checked at its worst stop. | PRD §6; ADR-0005 |
| BR-18 | Confirmed | The same brand mark appears on the landing, sign-up, sign-in, cabinet and crash screens. | PRD AC-15 |
| BR-19 | Confirmed | The changed and new wording listed in §11 is approved by the owner with the mockups. | PRD §1 (wording may change); owner approval 2026-10-29 |

## 7. Routes and frames

| Surface | Route / frame | Required content and layout |
|---|---|---|
| Current | `/`, `/sign-up`, `/sign-in`, `/dashboard`, crash (any route) | As described in §3–§4 |
| Desktop | 1440 × content height | Landing: centred 1200 px column, hero centred, features 4 across. Auth: card centred under the brand. Cabinet: sidebar 280 px + top bar 64 px + content max 1200 px. Crash: centred illustration and message |
| Tablet | 768 × content height | Landing: features 2 across, steps 3 across; cabinet sidebar visible (breakpoint `48rem`) |
| Mobile | 390 × 844 (and 360) | Landing: one column, starts stacked full width, preview without its sidebar. Auth: card full width. Cabinet: top bar with toggle and brand, drawer sidebar, task actions under each task |

## 8. State inventory

| State | Trigger | Visible result | Recovery / next action |
|---|---|---|---|
| Empty | Cabinet list loaded with 0 projects | Guidance card with folder illustration and "Create your first project" | Opens the new-project form |
| Empty (first task) | Projects exist, none has a task | Guidance card + "Add a task" above the project cards | Opens the first shown project's task form |
| Empty (no match) | Filters hide every project | Card with "No project matches these filters." + "Clear filters" | Clears status, search and sidebar choice |
| Loading | Cabinet list request in flight | "Loading your projects…" with a static ring and three placeholder cards, `role="status"` | — |
| Ready | Data loaded / screen opened | Filled list; auth cards with focus on the email field | — |
| Success | Sign-up or sign-in succeeds; a cabinet action saves | Navigates to the cabinet; the card updates in place | — |
| Error | Wrong credentials; field errors; email taken; list load fails; delete refused; status change fails; render fails | The exact messages of §6 in the error alert or under the field; crash screen | Retry, Sign in link, edit the field, crash screen has none |
| Disabled / focus / hover | Pending submit; keyboard focus; pointer hover | Submit at reduced opacity and `not-allowed`; 3 px focus ring; hover changes colour only, instant under reduced motion | — |
| Phone menu | Toggle pressed below 768 px | Drawer under the top bar with a scrim; toggle shows a close icon and `aria-expanded="true"` | Toggle again or Escape |

## 9. Reuse and handoff contract

| Design responsibility | Current code owner / token | Decision |
|---|---|---|
| Role colours, light and dark | `src/styles/tokens.css` `:root` (T2) | reuse unchanged |
| Landing palette and gradients | `tokens.css` `.palette-landing` (ADR-0005) | new block: `--color-*` overrides as in the landing mockup, plus `--gradient-hero`, `--gradient-accent`, `--gradient-title`, `--gradient-orb`, `--gradient-grid`, `--shadow-glow` |
| Status chip fills, scrim, sidebar active marker | `tokens.css` | new role tokens: `--color-status-progress-soft`, `--color-status-done-soft`, `--color-scrim` (both themes) |
| Fonts | `--font-family-base`, `--font-family-display`; `src/main.tsx` imports | extend per ADR-0006 |
| Brand mark | `src/routes/BrandMark.tsx`, `.brand` in `base.css` | reuse on every screen; on the crash screen as a non-link |
| Buttons, inputs, focus ring, alerts | `base.css` (T3, fe #77) | extend: primary, outline, text and small sizes; an info variant of the alert for "Your account was created." |
| Fields and field errors | `src/routes/TextField.tsx`, `AuthForm.css` | reuse markup; restyle, add the icon inside the error paragraph |
| Landing sections and preview | `Landing.tsx`, `Landing.css`, `SiteChrome.tsx` | extend: new badge, eyebrows, "How it works", sub-lines; preview chips |
| Auth card layout | `SignIn.tsx`, `SignUp.tsx`, `AuthForm.css` | extend: card wrapper, head with the switch link, divider, back link |
| Cabinet sidebar, top bar, cards, states | `Dashboard.tsx`, `Dashboard.css`, `ProjectForm.tsx` | extend: search moves into the top bar on desktop; toggle becomes an icon button named "Projects menu" |
| Crash screen | `src/ErrorFallback.tsx` (no stylesheet; SAD §5) | extend: brand, illustration, two-line message through base classes |
| Icons and illustrations | inline SVG in our own code | new component candidate only if reused on 2+ screens; drawn by us, no template asset |

## 10. Responsive and accessibility contract

- **Responsive:** mobile first; breakpoints `48rem` and `64rem`; no horizontal scroll at 360, 390, 768 and 1440 px;
  landing call-to-action buttons stack full width on a phone; cabinet task buttons wrap under the task on a phone.
- **Keyboard:** tab order follows the visual order; on desktop the cabinet search sits in the top bar before the
  content, and `/` still focuses it, `n` still opens the new task; Escape closes the phone drawer and the forms.
- **Semantics:** headings keep their levels (one `h1` per screen); the landing preview stays `aria-hidden`; the
  legal links stay a `nav` labelled "Legal"; the "Projects" caption sits inside the `nav` labelled "Project
  navigation"; icon-only controls carry their current accessible names.
- **Contrast and motion:** pairs per BR-17; landing button text is white on the accent gradient (worst stop
  `#7c3aed`, about 5.7:1), landing links use `--color-accent-strong`; motion only under
  `prefers-reduced-motion: no-preference`.

## 11. Content and realistic data

Wording kept word for word: every label, button, field message, alert and state text of §6 BR-05, BR-06, BR-09 and
BR-10, the landing headline, lead, feature titles and texts, call-to-action labels and the final heading.

Changed or new wording (marked with a dashed outline in the mockups; BR-19; approved by the owner on 2026-10-29):

| Screen | Today | Proposed |
|---|---|---|
| Landing | — | Badge: "Personal projects and tasks" |
| Landing | — | Eyebrows: "Features", "How it works" |
| Landing | — | Under "Everything a personal plan needs": "Projects, tasks and three statuses. Nothing you have to set up first." |
| Landing | — | New section heading "From a first idea to done in three steps"; steps "Create a project" / "Give it a name and, if you like, a short description.", "Add its tasks" / "Every new task starts as not started.", "Move them to done" / "Mark a task in progress, then completed, and filter to see what is left." |
| Landing | — | Under the final heading: "Your projects and tasks are visible only to you." |
| Landing | — | Preview status chips "Completed", "In progress", "Not started" (decorative, hidden from screen readers) |
| Sign-up / sign-in | — | Divider "or with email" (only when Google is configured) |
| Sign-up / sign-in | "I already have an account" / "Create an account" below the form | Same text, in the card head |
| Cabinet | — | Sidebar caption "Projects" |

Representative data: projects "Website launch" (4 tasks), "Home move" (2 tasks, delete refused), "Reading list"
(1 task); email `olena@example.com`.

## 12. Non-goals and forbidden changes

- No behaviour change: routes, API calls, validation, navigation targets, keyboard shortcuts, focus return and
  every existing accessible name stay (PRD §3).
- No new control: no "remember me", "forgot password", profile or avatar, theme switch, crash-screen button, or
  in-page landing navigation.
- No template code, fonts, images or icons copied from DarkSaaS or Mantis; no paid asset; no component library;
  no third-party font or image request (PRD §3, §6).
- No backend, API, schema or analytics change.
- The legal pages (fe PILOT-419) are not among the screens here; they inherit `.palette-landing` (ADR-0005).

## 13. Design references

- Visual references (look only, nothing copied): DarkSaaS landing page (landing); Mantis free admin dashboard and its
  auth pages (sign-up, sign-in, cabinet, crash). The public demos were not opened in this stage; the mockups follow
  the PRD's description of each reference (assumption A-1).
- Approved frame URLs (approved by the owner as they are, 2026-10-29; private Artifacts; each has light and dark, desktop 1440 px and phone 390 px, state tabs and
  the changed-wording table):
  - Landing page: https://claude.ai/artifact/SNDwTEv9yhb4gDXXyjwb5c
  - Sign-up: https://claude.ai/artifact/BmXtx1DYHHAsXQzuGrXCzF
  - Sign-in: https://claude.ai/artifact/G2wAWMmPM5XxKpVHKatG8L
  - Cabinet: https://claude.ai/artifact/V5R2DLcMwn3d1JWz89hD5Q
  - Crash screen: https://claude.ai/artifact/6fyLUrhEyvPTevnZieePBH
- Repo-local design file: none; the mockups are the static HTML above, built from the T2 token values.

### Assumptions (routine decisions taken in this stage)

- A-1: The reference demo pages were not opened; the look follows PRD §1 and the general shape of the two
  references. If a detail of a reference matters to the owner, it is named in the approval.
- A-2: The landing accent is violet (DarkSaaS) while the other screens keep the T2 blue; ADR-0005 allows the two
  palettes to differ, and the shared brand mark picks up each palette's accent. Confirmed by the owner on
  2026-10-29 (§14).
- A-3: Mockup widths are 1440 px (the PRD's screenshot width) and 390 px; 360 and 768 px are covered by the same
  breakpoints and checked by T4's helpers at implementation.
- A-4: The cabinet search moves into the top bar on desktop, as in the Mantis header; it is the same field with the
  same id, name and shortcut.
- A-5: The phone drawer opens under the top bar instead of covering it, so the one toggle also closes it and no
  second control is added.
- A-6: Status labels become chips beside the status icon; the label text is unchanged.
- A-7: The crash screen gets no "back" action because it renders outside the router and behaviour is unchanged.
- A-8: Landing motion (orb glow, preview fade-in) is specified in words only; the mockups are static.

## 14. Open decisions

| Decision | Why it matters | Owner | Due | Status |
|---|---|---|---|---|
| Approve the five mockups (look per screen) | Gate for `/sdlc:break-tasks` to replace T5–T9 | OlegShevtsov1 | before break-tasks | Approved (owner, 2026-10-29): all five as they are |
| Approve the changed and new wording of §11 | Wording may change, but the owner signs it off | OlegShevtsov1 | with the mockups | Approved (owner, 2026-10-29) |
| Landing accent: violet (as drawn) or the T2 blue | Brand continuity versus faithfulness to DarkSaaS | OlegShevtsov1 | with the mockups | Approved (owner, 2026-10-29): violet, as in DarkSaaS |

## 15. Spec-ready gate

- [x] Current product behavior is backed by repository evidence.
- [x] Product decisions are confirmed or visibly marked Proposed.
- [x] Requirements have stable IDs.
- [x] Desktop/mobile, states, reuse, accessibility, and non-goals are covered.
- [x] No route, dependency, component, token, or API has been invented as fact.
- [x] Every requirement maps to a DOD row in section 16 below.

---

# Definition of Done

Completion means every applicable row is checked with evidence. An agent report, generated image,
or visual impression is not evidence by itself.

## 16. Done checks

| ID | Covers | Layer | Pass condition | Evidence | Done |
|---|---|---|---|---|---|
| DOD-01 | BR-19 | Specification | The owner approved the five mockups and the §11 wording, and §14 rows are closed. | Approval recorded in §14 of this spec (owner, 2026-10-29) | [x] |
| DOD-02 | BR-01, BR-07, BR-04, BR-11 | Design structure | Each screen's DOM has the regions of its mockup (landing: header, hero, features, steps, final, footer; auth: brand, card head, form, back link, legal nav; cabinet: sidebar, top bar, filter card, project cards; crash: brand, illustration, alert). | Component tests per screen + before/after screenshots in each screen PR | [ ] |
| DOD-03 | BR-12, BR-13, BR-14 | Tokens and reuse | `tokens.css` holds the `:root` light/dark blocks and one `.palette-landing` block with the §9 names; the stylesheet guard passes over every stylesheet; fonts come from `@fontsource-variable/*`. | `npm test -- tests/stylesheet-guard` and `tests/design-tokens.test.ts`; `package.json` diff | [ ] |
| DOD-04 | BR-05, BR-06, BR-10 | States | Every state of §8 renders with its exact text: field errors, wrong credentials, taken, created, loading, empty, first task, no match, load failure, delete refused, new-project form, crash (both variants). | Component tests + e2e with stubbed API answers (T4 helpers) + screenshots | [ ] |
| DOD-05 | BR-02, BR-03, BR-06, BR-09 | Behavior | Existing unit and e2e suites pass with only the listed visual-value assertions changed; landing starts lead only to sign-up and sign-in, with and without Google. | `npm test`, `npx playwright test`; PR description list of changed assertions | [ ] |
| DOD-06 | BR-08, BR-15 | Responsive | 0 px horizontal overflow at 360, 768 and 1440 px on all screens; content column ≤ 1200 px and centred at 1440; the phone sidebar opens from the toggle, which stays reachable. | T4 width helper in each screen's e2e spec + phone screenshots | [ ] |
| DOD-07 | BR-16, BR-17 | Accessibility | Focus ring visible on every link, button and field; no animation or transition under reduced motion; every new pair passes contrast in its palette; accessible names unchanged. | e2e focus and reduced-motion checks; contrast pairs in `tests/design-tokens.test.ts` | [ ] |
| DOD-08 | BR-14, BR-17 | Deterministic gates | Lint, typecheck, unit and e2e suites pass in fe CI. | CI run of each screen PR | [ ] |
| DOD-09 | BR-03, BR-13 | Scope | No new dependency other than `@fontsource-variable/public-sans` (ADR-0006), no API, route or backend change, no copied template asset. | `git diff --stat`, `package.json` diff, file list with licences in the PR | [ ] |
| DOD-10 | BR-18, BR-01, BR-04, BR-07, BR-11 | Live evidence | On dev, each screen matches its approved mockup in light and dark (landing dark only) at 360 and 1440 px, and the same brand mark shows on all of them. | `verify-ui` report + screenshots attached to each screen PR | [ ] |

## 17. Requirement coverage

| Requirement | Covered by DoD IDs | Gap |
|---|---|---|
| BR-01 | DOD-02, DOD-10 | none |
| BR-02 | DOD-05 | none |
| BR-03 | DOD-05, DOD-09 | none |
| BR-04 | DOD-02, DOD-10 | none |
| BR-05 | DOD-04 | none |
| BR-06 | DOD-04, DOD-05 | none |
| BR-07 | DOD-02, DOD-10 | none |
| BR-08 | DOD-06 | none |
| BR-09 | DOD-05 | none |
| BR-10 | DOD-04 | none |
| BR-11 | DOD-02, DOD-10 | none |
| BR-12 | DOD-03 | none |
| BR-13 | DOD-03, DOD-09 | none |
| BR-14 | DOD-03, DOD-08 | none |
| BR-15 | DOD-06 | none |
| BR-16 | DOD-07 | none |
| BR-17 | DOD-07, DOD-08 | none |
| BR-18 | DOD-10 | none |
| BR-19 | DOD-01 | none |

## 18. Final gate

- [x] Every requirement is covered by at least one DoD row.
- [ ] Every applicable DoD row is checked and links to evidence.
- [x] Every `Proposed` decision (section 14) was approved or removed before implementation.
- [ ] Deterministic checks and live browser verification both passed.
- [ ] The final repository diff matches the approved scope.
