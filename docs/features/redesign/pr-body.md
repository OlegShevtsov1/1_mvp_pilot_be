## Summary

The redesign gives the landing page, sign-up, sign-in, the cabinet and the crash screen the owner-approved look:
- the landing page in the DarkSaaS style, always dark, with a violet accent;
- the other screens in the Mantis style, following the device theme;
- one brand mark and one token file across all of them, and Public Sans for body text.

No behaviour changes. The code is in `1_mvp_pilot_fe` (15 task pull requests, develop `929dc43`). This repository
holds the documents. See the [PRD](docs/features/redesign/PRD.md) and the
[design spec](docs/features/redesign/design-spec.md).

## Acceptance criteria

- AC-01: the landing page shows the hero, what the product offers and both ways to start, and no projects or tasks ✓
- AC-02: without a Google client the landing page mentions Google nowhere ✓
- AC-03: sign-up with a new email lands in the cabinet ✓
- AC-04: faulty sign-up fields each show their readable message ✓
- AC-05: sign-in with correct credentials lands in the cabinet ✓
- AC-06: wrong credentials show "Wrong email or password." and stay on sign-in ✓
- AC-07: every cabinet action keeps its result ✓
- AC-08: a project that still has tasks is kept, with an explanation ✓
- AC-09: a visitor opening the cabinet is sent to sign-in ✓
- AC-10: the failure, loading, empty and first-task states and the crash screen have the new look ✓
- AC-11: no sideways scroll at 360 and 768 px, and every action stays reachable ✓
- AC-12: theme rules (landing always dark, the others follow the device) and contrast in every palette ✓
- AC-13: a visible focus ring on every link, button and field ✓
- AC-14: no animation or transition under reduced motion ✓
- AC-15: one brand mark, and no raw design values outside the tokens ✓
- AC-16: at 1440 px the content column is centred and at most 1200 px ✓

## Design

- PRD: `docs/features/redesign/PRD.md`
- Architecture: `docs/features/redesign/sad.md`
- Decisions: `docs/features/redesign/adr/` (ADR-0002 to ADR-0006; ADR-0001 superseded by ADR-0005)
- Design spec and approved mockups: `docs/features/redesign/design-spec.md`
- Data model and API: none; no backend, schema or contract change
- Review: `docs/features/redesign/_review/review-2026-10-30.md` (PASS)

## Tasks (SDLC-Task trailers)

All in `1_mvp_pilot_fe`, squash-merged into develop:

| Task | PR | Commit | Card |
|---|---|---|---|
| T1 stylesheet guard | #74 | `b7399a4` | PILOT-377 |
| T4 visual-check helpers | #75 | `81cb89f` | PILOT-380 |
| T2 token values | #76 | `ba39261` | PILOT-378 |
| T3 base.css and BrandMark | #77 | `d1f24e1` | PILOT-379 |
| T12 Public Sans | #80 | `42015f3` | PILOT-439 |
| T20 crash screen | #81 | `1365234` | PILOT-447 |
| T13 landing palette tokens | #82 | `675fa93` | PILOT-440 |
| T16 sign-up | #83 | `521bd52` | PILOT-443 |
| T17 sign-in | #84 | `38e004b` | PILOT-444 |
| T18 cabinet shell | #85 | `88cbf5e` | PILOT-445 |
| T14 landing hero | #86 | `94ae19d` | PILOT-441 |
| T15 landing sections | #87 | `673c174` | PILOT-442 |
| T19 cabinet cards and states | #88 | `5930a28` | PILOT-446 |
| T10 guard all stylesheets and sweep | #89 | `0a54eb8` | PILOT-386 |
| T11 architecture map and approvals | #90 | `929dc43` | PILOT-387 |

## Verification

Run on 2026-10-30 against fe `929dc43`. The code was exported from git; the frontend checkout was not touched.

- **Unit:** `vitest run` passed: 57 files; 859 passed, 1 skipped, out of 860.
- **Lint and typecheck:** `eslint .` and `tsc -b` are clean.
- **Deploy:** dev serves `sha-929dc43…` (`/config.js`). fe Front CI and Dev Deploy for `929dc43` succeeded.
- **End to end against dev** (`playwright test --project=chromium`, `E2E_ENV_NAME=dev`): 112 of 113 pass. The flows
  exercised were:
  - landing, with Google on and forced off;
  - sign-up and its field errors;
  - sign-in and wrong credentials;
  - every cabinet state (stubbed API answers) and the phone drawer;
  - the crash screen;
  - the redesign sweep: the brand mark on every screen, 360/768/1440 px, the theme rules, focus, reduced motion,
    and no font or image request from another origin.
- **One failure, on dev only:** `e2e/dashboard.spec.ts:132` "the desktop sidebar background runs the full page
  height". It fails on every run on dev.
  - Cause: the debug footer (`App.tsx:39`, rendered only when `ENV_NAME` is `dev`) adds 127 px below `.dashboard`,
    so the sidebar strip ends 127 px above the page bottom.
  - Prod renders no debug footer, so prod is not affected.
  - The test predates the redesign (PILOT-273). The pull request checks run it against a local preview, where it
    passes.
- **Deferred:**
  - The real-backend `journey` project. It signs up a real account on dev, and its workflow `dev-journey.yml` is not
    on the frontend's default branch yet, so it is not triggered after Dev Deploy.
  - A manual pass in a browser on prod, which comes after the release deploy.

## Operational notes

- **Migration:** none.
- **Feature flag / config:** none. The new dependency `@fontsource-variable/public-sans` (SIL OFL 1.1) is bundled
  and self-hosted.
- **Rollback:** redeploy the previous frontend release.
- **Release:** the frontend's `[Unreleased]` holds the redesign entries. Tagging and the prod deploy are done by the
  operator.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
