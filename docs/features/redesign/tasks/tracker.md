# Tracker — redesign

> Status of every task in the epic. `implement-tasks` updates `done` as it commits each task.
> States: `todo` · `in_progress` · `blocked` · `review` · `done`. Estimates: S = 2 h, M = half a day, L = one day.

| # | Task | Layer | Repo | Owner | Estimate | Blocked by | Status |
|---|---|---|---|---|---|---|---|
| T1 | Add the stylesheet guard for design values and motion, starting with App.css | tests | 1_mvp_pilot_fe | OlegShevtsov1 | S | — | done |
| T2 | Rewrite the design token values in place from the Mantis palette and type scale, both themes | ui | 1_mvp_pilot_fe | OlegShevtsov1 | M | T1 | done |
| T3 | Add base.css (page shell, header, controls, focus ring, alerts) and the shared BrandMark | ui | 1_mvp_pilot_fe | OlegShevtsov1 | M | T2 | done |
| T4 | Add the end-to-end visual-check helpers: width, theme, focus, reduced motion, third-party requests and cabinet stubs | tests | 1_mvp_pilot_fe | OlegShevtsov1 | M | — | done |
| T12 | Self-host Public Sans as the body face | ui | 1_mvp_pilot_fe | OlegShevtsov1 | S | T3 | done |
| T13 | Add the landing palette block, the gradient tokens and the new role tokens with their contrast pairs | ui | 1_mvp_pilot_fe | OlegShevtsov1 | M | T12 | done |
| T14 | Landing page, part 1: always-dark palette hook, header and the hero with the decorative preview | ui | 1_mvp_pilot_fe | OlegShevtsov1 | L | T4, T13 | done |
| T15 | Landing page, part 2: feature cards, "How it works" steps, the final call-to-action card and the footer | ui | 1_mvp_pilot_fe | OlegShevtsov1 | M | T14 | done |
| T16 | Sign-up in the Mantis auth layout: brand, centred card with the switch link in its head, divider and fields | ui | 1_mvp_pilot_fe | OlegShevtsov1 | M | T4, T12 | done |
| T17 | Sign-in in the Mantis auth layout with the wrong-credentials alert | ui | 1_mvp_pilot_fe | OlegShevtsov1 | S | T16 | done |
| T18 | Cabinet, part 1: Mantis shell with the 280 px sidebar, the top bar with the search and the phone drawer | ui | 1_mvp_pilot_fe | OlegShevtsov1 | L | T4, T13 | done |
| T19 | Cabinet, part 2: filter card, project cards with status chips, and every state (loading, empty, first task, no match, failure, delete refused) | ui | 1_mvp_pilot_fe | OlegShevtsov1 | L | T17, T18 | done |
| T20 | Crash screen with the brand, a drawn illustration and the message in the display face | ui | 1_mvp_pilot_fe | OlegShevtsov1 | S | T4, T12 | done |
| T10 | Guard every stylesheet and check the brand mark and widths across all screens | tests | 1_mvp_pilot_fe | OlegShevtsov1 | S | T15, T17, T19, T20 | done |
| T11 | Refresh the frontend architecture map and record the screen approvals | docs | 1_mvp_pilot_fe | OlegShevtsov1 | S | T10 | done |

**Total:** 15 tasks, ~60 hours (about 7.5 person-days), of which ~46 hours remain after the four done tasks.

**Breakdown of 2026-10-29:** T5 to T9 were built against the narrow "layout rhythm only" scope, rejected and never
merged; they are replaced by T12 to T20, written against the approved [design spec](../design-spec.md) and its mockups.
T1 to T4 are done and unchanged; T10 and T11 keep their ids with deps re-pointed. See [_epic.md](./_epic.md).

## Screen approvals (owner)

The owner approved every screen from screenshots (PRD §6 Visual approval, 4 of 4 plus the crash screen); the full record
with the operator's words is in [the feature review](../_review/review-2026-10-30.md) §7.

| Screen | Approved mockup | Built screen approved | Implementation screenshots |
|---|---|---|---|
| Landing page | https://claude.ai/artifact/SNDwTEv9yhb4gDXXyjwb5c | "26 A" (T14, T15) | https://claude.ai/artifact/3y1tMn1YbpeoHiAnTMHjVj |
| Sign-up | https://claude.ai/artifact/BmXtx1DYHHAsXQzuGrXCzF | "28 A" (2026-10-30, T16) | fe #83 |
| Sign-in | https://claude.ai/artifact/G2wAWMmPM5XxKpVHKatG8L | "28 A" (2026-10-30, T17) | https://claude.ai/artifact/2ANs4bsJEwNEMGmS7A8Z1Y |
| Cabinet | https://claude.ai/artifact/V5R2DLcMwn3d1JWz89hD5Q | "25 A" (T18, T19; size exception for fe #88 "27 A") | https://claude.ai/artifact/Q3xjQV1EzQYKfXQQbrHhaY, https://claude.ai/artifact/StjTv9k8sTJGMDtMfGAgtg |
| Crash screen | https://claude.ai/artifact/6fyLUrhEyvPTevnZieePBH | "28 A" (2026-10-30, T20) | https://claude.ai/artifact/KuBznucpsLUJgFuHL4vSDJ |

Mockups approved: "21 подобається"; violet landing accent "22 A"; wording "23 A"; landing always dark, decision 19 "А".
