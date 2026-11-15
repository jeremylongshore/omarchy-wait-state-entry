# Changelog

Notable changes to Wait State.

The format follows Keep a Changelog and the project uses Semantic Versioning.

## [Unreleased]

Nothing yet.

## [1.1.1] - 2026-11-15

### Fixed

- Qualify Omarchy's palette as `Commons.Color`, as the shell contract requires
  now that Qt 6.12 has its own `Color` type. A contract test fails on any bare
  `Color.` in the shipped QML.

### Changed

- Seed the rig render's isolated home with the current-theme state a real
  Omarchy install has, so first-party shell plugins on current Omarchy do not
  log warnings the render would read as plugin warnings.
- Bump `actions/setup-node` to 7.1.0 and the MiniMax review action to the
  fork's current main (`cfb2c72`), with the audit harness re-pinned.

## [1.0.0] - 2026-08-23

### Added

- CPU, memory, and I/O pressure stall sampling from fixed procfs sources.
- Worst-resource and pinned-resource bar modes.
- Partial and whole-machine stall visibility with plain-language diagnostics.
- Bounded persistent history with 15-minute, 1-hour, and 6-hour views.
- Configurable polling and display thresholds.
- Keyboard and pointer navigation, truthful unavailable states, and IPC refresh.
- Offline parser, classification, history, bounds, and failure-path tests.
- Production Buzz receipts for static validation, interpreter-shadowed real-shell
  rendering, and exact public-URL installation.
- SVG banner, installed-copy screenshot, support policy, code ownership, and
  repository-specific agent guidance.
