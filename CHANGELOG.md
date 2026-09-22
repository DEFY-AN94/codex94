# Changelog

All notable changes to Codex94 are documented here.

## 3.1.1 - 2026-09-23

Version `3.1.1 (17)`. Release dates use Australia/Melbourne.

### Fixed

- Hide the floating strip's 5-hour column when the selected quota bucket does
  not provide that window. Weekly-only accounts use a 480-point strip; buckets
  with both windows keep the 680-point layout. Screen fitting still applies.
- Resize the same floating panel when its quota windows change, preserving its
  top-left position where screen space allows, normal typography, pin/expanded
  state, and manual-refresh behavior. Layout changes reuse the existing
  snapshot and make no request.
- Allow local security checks in linked Git worktrees by excluding only the
  Git administration entry; source and history scanning remain enabled.

## 3.1.0 - 2026-09-23

Version `3.1.0 (16)`. Release dates use Australia/Melbourne.

### Added

- Add a compact floating quota strip, targeting 680 × 90 logical points, with
  pin, drag, hide, and expand controls. It reads the existing quota snapshot;
  the refresh action appears on freshness hover or keyboard focus and uses
  the existing manual refresh path. The popover shortcut remains unchanged.
- Add custom inclusive source-date ranges alongside 7-day, 30-day, and
  all-returned views. Show reported daily average, selected-interval peak,
  coverage, and the preceding equal-length interval's reported total/coverage.
  Show percentage change only when both intervals are complete and the prior
  total is nonzero; missing days remain unreported.
- Export the selected chart as PNG or copy its image after a user action.
  Images follow the selected range, bar/line style, language, and appearance,
  with fetch time, coverage, and any stale-data notice. CSV export remains.

### Privacy and validation

- Store only floating pin state and position in two new preferences;
  visibility, expansion, custom dates, and Token snapshots remain memory-only.
  Add no polling cadence, reset-credit consumption, history database, network
  endpoint, system permission, or signing-policy change.
- Add synthetic Floating UI coverage alongside Display, Recovery, and Token
  usage; extend usage checks for custom ranges and image-export controls.
  Validate PNG rendering and copying with synthetic data and named test
  pasteboards. Native
  NSPanel behavior across Spaces and fullscreen apps needs separate validation.

## 3.0.1 - 2026-09-21

Version `3.0.1 (15)`. Release dates use Australia/Melbourne. This maintenance
release prepares shared parsing and presentation boundaries for later features.

### Fixed and optimized

- Prevent quota responses from an obsolete executable or identity context from
  changing current state, cache, pinned selection, notifications, or Token
  statistics. Preserve the existing single-flight queue and refresh priority.
- Share strict source-date and nonnegative-count validation where field rules
  match, keeping unknown values distinct from zero and preserving quota's
  separate percentage handling.
- Reuse prepared chart data and date-formatting context instead of rebuilding
  them during chart interaction, without changing source-date gaps, range
  semantics, bar/line selection, or CSV contents.
- Move retired Token usage client cleanup off the main actor during reset;
  retain synchronous shutdown draining and the existing bounded process-group
  termination algorithm.
- Reject invalid development-script modes before stopping any Codex94 process
  or starting a build, and document component ownership and reuse rules.

No new feature, broad timer/store rewrite, cache migration, signing-policy
change, or automatic installation is part of this maintenance scope.

## 0.3.0 - 2026-09-21

Version `0.3.0 (14)`. Release dates use the maintainer's Australia/Melbourne
calendar; GitHub publication timestamps are recorded in UTC.

### Added

- Add an on-demand **Token usage** Dashboard page using the official
  `account/usage/read` endpoint: service-reported lifetime and peak daily tokens,
  streaks, longest turn duration, a daily chart and an exportable daily table.
- Keep statistics in memory, independently of quota polling and connection
  status. Missing values and missing dates remain unknown; repeated reads replace
  the snapshot instead of adding usage again. Unsupported Codex versions display
  a dedicated message without breaking the menu bar.
- Add 7-day, 30-day, and all-returned daily views ending at the latest source
  date, exact values on chart hover/selection, and CSV export of the displayed
  daily records. Preserve source-date gaps and distinguish unknown data from
  explicit zero; do not infer an account reporting timezone or complete coverage.
- Add a remembered bar/line chart choice, with selected-date guides centered
  on each bar or data point. Line segments stop at missing source dates.
- Add **Check for updates** in About. A manual click reads this repository's
  latest public stable GitHub Release, displays its version and plain-text
  notes, and offers a validated Release-page link in the system browser.
  Downloading and installing remain user-managed.

### Security and privacy

- Keep Token usage snapshots in memory except for a user-requested CSV export.
  Ignore thread details and retain the existing Codex authentication boundary,
  independent quota status, and cache schema v2.
- Disclose the new direct GitHub metadata request. It sends no Codex account or
  usage data, uses no cookies or credential-store access, and persists no update
  results. Add no background update polling, automatic app download/install,
  system profiling, signing-key storage, or third-party runtime dependency.

## 0.2.2 - 2026-09-20

Version `0.2.2 (13)`.

### Added

- Add a fourth dual-window menu-bar layout that displays one selected bucket's
  5-hour and Weekly values together. Save its bucket choice independently;
  preserve the original three layouts and their existing quota-selection rules.
- Let mouse left-click and right-click on the menu-bar item toggle the same
  popover, keeping the existing refresh-on-open behavior.
- Add a configurable global shortcut for the same popover action, unset by
  default and requiring Control or Option, with optional Command and Shift.
  Opening the popover keeps normal refresh behavior.
- Add opt-in local quota notifications, disabled by default. Explicit enabling
  requests macOS notification permission. Start with 20% and 10% remaining
  thresholds that can each be adjusted or disabled, the default bucket, optional
  extra buckets, and optional recovery alerts. Keep observation baselines and per-window-cycle
  deduplication in memory.
- Add a prominent, read-only **Manual quota resets** (**手动额度重置**) card to
  Popover and Overview. The card displays the available count without a reset
  button, using the existing response's authoritative
  `rateLimitResetCredits.availableCount`. Preserve
  zero, show missing/null data as unavailable, distinguish a cold unfetched
  state, and label retained values after failed refreshes as cached.

### Compatibility

- Keep notification authorization checks compatible with the Xcode 16.4
  toolchain without transferring system notification objects across actors.

### Security and privacy

- Keep cache schema v2 and exclude the reset-credit count and individual credit
  details from disk. Add no reset-redemption control or consume RPC.
- Store only new preferences under `dualWindowBucketSelection.v1`,
  `globalHotKey.v1`, and `notifications.v1`. Notification messages contain the
  bucket name, window, and percentage without email; macOS Notification Center
  can retain delivered messages. This optional local system service is not
  remote telemetry.
- Retain the existing Codex subprocess/authentication boundary. Add no session
  or auth-file readers, history collection, multi-account management, or updater.

## 0.2.1 - 2026-09-12

### Fixed

- Keep Launch at Login status observable when returning to the app and show a
  localized failure without exposing system error details. Tests use a fake
  service and do not register real Login Items.
- Clamp extreme quota percentages before subtraction so malformed snapshots
  cannot overflow while computing the remaining percentage.
- Keep a session-only consumed Reset watermark across clock rollback and later
  snapshots; reuse the existing single-flight refresh and no-retry behavior.
- Change a saved bucket/window selection to Auto when a fresh successful
  snapshot confirms it is absent. Cache loading and refresh failures preserve
  the preference; an option returning later does not undo Auto.
- Let the popover fall back to the first displayable bucket when the default
  bucket has no windows. Keep weekly-only data valid without plan-type rules,
  hard-coded model availability, or retirement dates.
- Preserve requested window presets when fitting a smaller screen, distinguish
  long quota-bucket names in menus, and localize the executable picker using
  the selected app language.
- Make source installation require running copies to be quit, use a unique
  locked staging transaction, verify the App, and restore the old copy when a
  replacement fails. Preserve recovery files if rollback cannot finish.

### Maintenance

- Share strict App-target version/build parsing between the release gate, CI,
  and UI fixtures. CI uses committed metadata; local checks support worktree
  changes. Keep the isolated fixture loader and tracked-input checks.
- Keep complete App verification in the DMG packager and retain a single
  Universal Release build, both architecture checks, and two explicit assets.
- Correct published stable-version instructions and retain historical
  changelog entries and synthetic screenshot provenance.

### Security and privacy

- Retain cache v2, existing preference keys, fixed Codex subprocess requests,
  and current authentication, network, permission, and entitlement boundaries.
- Continue unsigned, unnotarized Universal DMG and source distribution from
  the published `v0.2.1` tag.

## 0.2.0 - 2026-09-03

### Added

- Add a first-party, Universal 2 (`arm64` + `x86_64`) DMG path for technical
  users on macOS 14+, while retaining source installation from the annotated
  `v0.2.0` tag through `script/install.sh`.
- Add a native `package_dmg.sh` create/verify workflow for the unsigned,
  unnotarized `Codex94-0.2.0-macos-universal-unnotarized.dmg` and its one-line
  SHA-256 checksum file. The mounted image contains only `Codex94.app` and an
  `Applications -> /Applications` shortcut.
- Upload short-lived CI candidates and generate main-only GitHub artifact
  attestation for the DMG. Attestation records repository/workflow/commit
  provenance; it is not Apple signing, notarization, or a security verdict.

### Changed

- Accept both `/Applications/Codex94.app` and
  `~/Applications/Codex94.app` as stable Launch at Login locations while
  rejecting mounted images, translocation, downloads, temporary locations,
  approximate paths, and symlinked App leaves.
- Build the Release App once as exact Universal 2, verify both architecture
  slices as ad-hoc signed with Hardened Runtime, no Team ID, and no entitlement
  keys, then pass that same App into DMG packaging.
- Document the DMG and source-install tracks, checksum and attestation checks,
  Apple Privacy & Security → Open Anyway flow, two uninstall locations, and the
  requirement not to run both installed copies at once.

### Security and privacy

- Keep the outer DMG completely unsigned, without Developer ID, Apple
  notarization, stapling, or an automatic updater. Only the App inside has the
  existing ad-hoc Hardened Runtime signature; users must verify the exact
  checksum and make their own trust decision before using Apple's official
  Open Anyway flow.
- Keep runtime data access, cache/preferences, subprocess behavior, network
  boundary, entitlements, and permissions unchanged. DMG staging and CI upload
  allowlists exclude source, credentials, identity, real quota, preferences,
  cache, logs, screenshots, and private paths.
- Adopt a manual non-replacement policy for published assets. SHA-256, GitHub
  Release API digests, and attestation can detect drift, but Immutable Releases
  is not enabled and the platform does not prevent an authorized maintainer
  from replacing an asset.

## 0.1.9 - 2026-08-30

### Added

- Add a default Dashboard Overview that reuses the existing connection status,
  freshness presentation, menu-bar quota picker, bucket ordering, and quota rows
  to show every displayable bucket and only its returned 5-hour or Weekly
  windows. Empty data is explicit and never presented as `0%`.
- Schedule one in-memory post-reset refresh for the earliest future target among
  displayable windows, strictly at `resetsAt + 5` seconds or later. Equal targets
  are deduplicated; wake, system-clock, and adjacent refresh handling continue
  through the existing single-flight coordinator without a Reset-specific retry.
- Show the exact version and build in About with a user-triggered copy action,
  and add a project link to `https://github.com/DEFY-AN94/codex94` while retaining
  the existing creator link.

### Changed

- Apply all three saved menu-bar layouts immediately to the existing status item
  and its width instead of waiting for the next app launch.
- Derive UI-fixture version and build metadata from the exact committed app
  target at `GITHUB_SHA`, retain the explicit build-input allowlist, and use a
  fixture-schema temporary-path prefix rather than a release-version prefix.

### Security and privacy

- Reuse `menuBarLayout.v1`, cache schema v2, the existing RPC/parser/process
  boundary, and the existing permission set. No preference key, cache field,
  persistent Reset ledger, identity field, authentication access, direct network
  interface, background helper, telemetry, or system permission is added.
- Keep Overview rendering read-only with respect to quota requests, cache, and
  connection state, and omit email, executable paths, and raw bucket identifiers
  from the page and its accessibility identifiers.
- Share one user-triggered clipboard component between redacted Diagnostics and
  About version copying. Tests use an isolated named pasteboard rather than
  reading, clearing, or overwriting the user's general pasteboard.

### Validation

- Add deterministic coverage for Overview routing and rendering, exact About
  metadata and isolated copying, Reset target/single-flight/wake/clock behavior,
  live menu-bar layout changes, and committed-metadata UI fixture preparation.

## 0.1.8 - 2026-08-29

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
- Share the Reset description across visible content and accessibility labels,
  with English and Simplified Chinese strings and separate recovery buttons
  with dedicated labels.

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
  popover/Dashboard images with reviewed synthetic release captures; retain
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
