# Changelog

All notable changes to Codex94 are documented here.

## Unreleased

### Fixed

- Restore compatibility with Codex CLI 0.149 by replacing the removed
  `-a untrusted` app-server argument with `-a never`, while retaining the
  read-only sandbox.

### Added

- Parse the default Codex quota bucket and additional named model buckets from
  `rateLimitsByLimitId` without merging independent quotas.
- Add independent model-bucket browsing in the popover and dynamic menu-bar
  selections. `Auto` now chooses the lowest remaining percentage across every
  displayable bucket and window.
- Add a versioned quota cache with backward migration for legacy snapshots and
  display-mode preferences.

### Security and privacy

- Keep authentication inside the Codex app-server boundary: Codex94 does not
  add OAuth handling, direct quota HTTP requests, or authentication-store
  access.
- Keep cache v2 limited to quota-bucket identifiers and names, plan and window
  metadata, percentages, reset times, and fetch time with owner-only
  permissions.

## 0.1.4 - 2026-08-14

### Security

- Normalize executable paths and strictly validate version strings before
  copying redacted diagnostics.
- Expand current-tree and Git-history checks for credentials, private machine
  paths, and email addresses while allowing only explicit test fixtures.

### Documentation and project maintenance

- Add matching English and Simplified Chinese project guides with language
  navigation.
- Add sanitized Terminal Dark menu bar, popover, and Connection screenshots.
- Document public source installation, security reporting, clipboard behavior,
  and the Codex-assisted vibe-coding workflow.
- Add Issue and pull request templates, SHA-pinned CI, and Dependabot coverage
  for GitHub Actions.

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
