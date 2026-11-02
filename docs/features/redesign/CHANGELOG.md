# Changelog — redesign

## redesign — a new look for the landing page, sign-up, sign-in, the cabinet and the crash screen

**What:** the landing page is now always dark in a DarkSaaS-style look with a violet accent: a hero with a gradient
headline and a decorative cabinet preview, four feature cards, a "How it works" section with three steps, a final
call-to-action card and a footer bar. Sign-up and sign-in sit in a centred Mantis-style auth card under the brand.
The cabinet has a Mantis dashboard layout: a 280 px sidebar and a 64 px top bar with the search, a drawer behind the
one "Projects menu" toggle on a phone, project cards with status chips, and every state (loading, empty, first task,
no match, load failure, delete refused) restyled. The crash screen shows the brand, a drawn illustration and the
message in the display face. Body text is set in Public Sans. One brand mark appears on every screen. Every function,
route, message and accessible name works exactly as before.

**Why:** the four screens had no common visual language, and the MVP is shown to reviewers and demo audiences
([PRD](./PRD.md) §1, §2). The look follows the owner-approved mockups of the [design spec](./design-spec.md).
Key decisions:
- [ADR-0005](./adr/0005-scope-the-landing-palette-as-an-override-of-the-same-token-names.md): the landing palette is
  a `.palette-landing` override of the same token names.
- [ADR-0006](./adr/0006-self-host-public-sans-for-body-text-and-keep-space-grotesk-for-display.md): Public Sans is
  self-hosted.
- [ADR-0004](./adr/0004-share-the-page-shell-and-controls-through-one-base-stylesheet.md): one `base.css` holds the
  shell and the controls.
- [ADR-0002](./adr/0002-guard-design-values-and-motion-with-a-vitest-stylesheet-scan.md): a stylesheet guard keeps
  raw values and unguarded motion out of every stylesheet.
- [ADR-0003](./adr/0003-switch-token-values-first-then-restyle-one-screen-per-pr.md): the design values changed
  first, then one screen per pull request.

**How to use:** nothing to configure; open `/`, `/sign-up`, `/sign-in` and `/dashboard` as before.
- Sign-up, sign-in, the cabinet and the crash screen follow the device's light or dark setting, and are light when
  the device states no preference.
- The landing page and the privacy and terms pages are always dark.

**Operational notes:**
- Migration: none. The backend, the API contract and the data model are unchanged; this repository changes only
  documents.
- Feature flag / config: none. Frontend only (`1_mvp_pilot_fe`, develop `929dc43`); its user-facing entries are
  under `[Unreleased]` in the frontend `CHANGELOG.md` (PILOT-378, PILOT-379, PILOT-386, PILOT-439 to PILOT-447).
- New dependency: `@fontsource-variable/public-sans` 5.3.0 (SIL Open Font License 1.1), bundled and served from the
  app's own origin. No Content-Security-Policy change.
- Rollback: redeploy the previous frontend image (`Kamal Deploy` of the previous release tag); there is no data or
  backend state to revert.

**Acceptance criteria delivered:** AC-01 to AC-16 (PRD §5): all four screens and the crash screen have the new look,
and the behaviour of each is unchanged. Each screen fits 360, 768 and 1440 px, follows the theme rules, shows a
visible focus ring and has no motion under reduced motion. One brand mark and one token file serve every screen.
The owner approved 4 of 4 screens plus the crash screen ([review](./_review/review-2026-10-30.md) §7). Eight
non-blocking follow-ups are Backlog cards PILOT-459 to PILOT-466 (review §6).
