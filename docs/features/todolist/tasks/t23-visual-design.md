---
id: T23
title: "Give the landing page and the dashboard a stylish visual design"
layer: ui
repo: 1_mvp_pilot_fe
estimate: L
deps: [T21, T22]
acs: [AC-01]
---

# T23 — Give the landing page and the dashboard a stylish visual design

Added by operator decision 81 (2026-10-22): the PRD asks for a stylish design; T17–T22 ship the structure with
first shared CSS tokens only. This task gives the landing page and the dashboard their final visual design.

## Definition of Done

- Design tokens (colour, type scale, spacing, radius, shadow) in one place; light and dark theme follow the system
  setting.
- Landing hero with a visual and a clear call to action; dashboard layout with polished cards, filters and
  empty, loading and error states.
- Responsive from 360 px; WCAG AA contrast; visible focus states; animations respect `prefers-reduced-motion`.
- No new heavy UI library without an ADR; lint, typecheck, tests and build green; e2e screenshots of the landing
  page and the dashboard.
