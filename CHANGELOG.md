# Changelog

All notable changes to Codex94 are documented here.

## 0.1.3 - 2026-08-13

### Fixed

- Refresh account information when switching from quota-only mode, including
  when another refresh is already running.
- Apply system, dark, and light appearances immediately across Dashboard,
  popover, and menu-bar content.
- Shorten Simplified Chinese theme labels to `深色` and `浅色`.

### Security and release readiness

- Ignore relative `PATH` entries and bound Codex version-probe output and time.
- Terminate complete Codex subprocess groups, including spawned descendants.
- Redact executable version diagnostics and expand static secret checks.
- Reject debugger attachment entitlements in Release builds.
- Check both working-tree and committed release content for whitespace errors.
- Add privacy, contribution, release, CI, and changelog documentation.

## 0.1.2 - 2026-08-13

- Made the menu-bar item more compact and added deterministic click-away closing.
- Moved refresh frequency to Connection settings.
- Added Dashboard size presets and the About page.

## 0.1.1 - 2026-08-13

- Fixed popover percentage titles, Weekly labels, Dashboard title layout, and the
  fixed sidebar toggle position.

## 0.1.0 - 2026-08-12

- Initial local development baseline.
