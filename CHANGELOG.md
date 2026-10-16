# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). A pull request whose `Type:` is `feat` or `fix` adds
its entry under `[Unreleased]` (checked by `changelog-check`); a release moves those entries into a new
`## [X.Y.Z] - YYYY-MM-DD` section and keeps the six empty categories below as the template. See README
"Релізи й hotfix".

## [Unreleased]

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.1.0] - 2026-10-16

### Added

- Releases: semantic version tags `vX.Y.Z` computed from the squash commits' `Type:` lines
  (`scripts/next-version.sh`), this changelog and `changelog-check`, a draft GitHub Release from the
  changelog section on every release tag (`Release` workflow), prod deploys only from an annotated release
  tag on `main`, a 10-minute `release-watch` after every prod deploy, protection of published tags
  (`.githooks/pre-push`) and per-release delivery metrics (`bin/sdlc-metrics`).

### Changed

- `Kamal Deploy` and `deploy/deploy.sh prod` take a release tag `vX.Y.Z` instead of a commit sha; a bare sha
  is refused.
- A prod rollback needs the typed confirm `ROLLBACK-prod`, in `Kamal Manage` (`confirm=ROLLBACK-prod`) and in
  `deploy/rollback.sh prod` (env `CONFIRM` or the prompt).
