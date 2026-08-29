# Changelog

All notable changes to Codex94 are documented here.

## Unreleased

The working candidate is `0.1.8 (9)`, not a stable source release. Candidate
`164ae10` passed 155 compiled tests, the release gate, and CI display smoke.
Recovery CI failed; remaining isolated GUI acceptance is pending.

### Added

- Add Ring + Percentage, Percentage Only, and Ring Only menu-bar layouts.
  Layout choices are saved for the next app launch; the default keeps the
  existing 58 pt status item and 52x22 pt content.
- Add independent, opaque sRGB overrides for healthy, warning, critical, and
  hard-unavailable error colors. Colors update immediately; Restore Default
  Colors clears only those overrides, leaving other preferences unchanged.
- Show localized absolute Reset dates, minute-precision times, and the UTC
  offset at the reset instant alongside the existing countdown. Popover rows
  use a separate secondary line and measured natural height; Dashboard
  Connection shows the actual resolved menu-bar quota, including fallback.
- Add Open Connection or Open Diagnostics to issue banners. These actions only
  navigate within the existing Dashboard; ordinary opening preserves its
  current section. Connection includes sign-in guidance without executing login.
- Share the Reset description across visible content and accessibility
  labels, with English and Simplified Chinese strings and independently
  accessible recovery buttons.

### Changed

- Center status badges inside a visible ring; Percentage Only uses a fixed
  trailing badge slot. Refreshing/cached badges keep the connection accent;
  hard-unavailable badges, banners, and the Dashboard error dot use the separate
  error color, defaulting to the unmodified theme red.
- Preserve fixed quota thresholds of 50% and 20%. Display preferences, Reset
  rendering, and recovery navigation do not request quota or write quota cache;
  the existing launch, popover, scheduled, wake, and manual refresh paths remain.

### Security and privacy

- Store layout and color choices under `menuBarLayout.v1` and
  `statusAccentOverrides.v1`. Colors use normalized six-digit uppercase `RRGGBB` values;
  invalid stored entries fall back per role. No new identity fields, quota
  schema, credentials, network interface, or permissions are introduced.
- Document the local UI preferences, use synthetic test/screenshot fixtures,
  and report CI, GUI, and screenshot validation separately. Replace the four
  popover/Dashboard images with reviewed synthetic candidate captures; retain
  the unchanged default menu-bar example from the previous stable version.

## 0.1.7 - 2026-08-28

### Added

- Show the last successful quota age in the popover header and in the menu-bar
  and popover accessibility descriptions, including distinct refreshing,
  cached, unavailable, and no-success states in English and Simplified Chinese.
- Refresh once after a system wake when no successful snapshot exists or the
  last success is at least 60 seconds old. Fresh snapshots are left unchanged,
  and wake requests reuse the existing single-flight refresh path.

### Fixed

- Cancel and reap in-flight Codex version probes and app-server process groups
  during app termination with bounded cleanup, preventing refresh children from
  remaining after Codex94 exits.

## 0.1.6 - 2026-08-24

### Fixed

- Keep quota severity independent from connection and data freshness. Cached
  snapshots retain their last known green, amber, or red quota color, while
  refreshing, cached, and unavailable states use distinct blue/cyan status
  badges.
- Show a gray `--` when no quota snapshot is available instead of presenting
  missing data as `0%`.

### Added

- Add a pure, tested `StatusPresentation` mapping shared by the menu bar and
  popover, with localized English and Simplified Chinese help and combined
  accessibility labels for quota and connection state.

## 0.1.5 - 2026-08-23

### Fixed

- Keep the popover at 500 pt wide while following the active quota content's
  natural height, preserving the header's top spacing without leaving unused
  space below shorter single-window or multi-window layouts.
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
