# Component ownership and reuse

This describes ownership and reuse constraints for the published
[`4.1.2 (26)` release](https://github.com/DEFY-AN94/codex94/releases/tag/v4.1.2),
published on 2026-10-05 (Australia/Melbourne), including the unpublished
`4.0.2 (23)` candidate it carries forward.
Test results and final package acceptance are separate evidence; this document
defines component responsibilities, not a substitute for those records.

## 4.1.2 display release: historical quota is not current quota

`ClaudeQuotaHistoryPresentation` is an in-memory, display-only value derived from
one already accepted, selected report when no current snapshot can be produced.
It contains only source, original report time, quota windows and model limits;
account UUIDs and producer identifiers never enter the presentation value.
`ClaudeQuotaStore` owns its publication and clears it on disable or observed
identity invalidation. It preserves the existing source-selection, pending-report
confirmation and late-result generation rules. A file reread does not become a
new observation time; invalid/future report data is not invented into history.

`ClaudeQuotaHistoryView` is shared by the compact popover and Dashboard card.
`ClaudeQuotaHistoryFormatting` reuses the existing percentage, absolute-source-time
and relative-age formatters for those surfaces, native tooltip/accessibility text
and floating expanded detail. Native rings, floating main metrics, Auto choices
and notifications continue using only the existing `QuotaSnapshot` path.
Partially valid reports retain their current-window presentation; model-only
current quota semantics are unchanged. History adds no timer, disk record,
preference, data source or request. Expired statusline reports are not newly
adopted on cold start; persisted local usage data can be reread when still safe.

## 4.1.1 maintenance release

`4.1.1 (25)` keeps the existing sources and polling frequency. The store
isolates an observed cache account context from previously accepted backup
reports and in-flight CLI results. Missing, unsafe or decoded-invalid cache
state after a known account retires that context; a torn JSON write is transient.
A statusline fingerprint identifies a stream, not an authenticated account.
After context loss it needs explicit reconfirmation before it can be selected.
Each pending confirmation has an in-memory UUID captured by the dialog and
checked by the store; an old dialog cannot adopt a replacement report.
The first accepted report establishes a new notification baseline; falling
back to an older observation does not emit fresh recovery notifications.

Eligible reports must yield a usable snapshot at the reference time before
newest-report selection. A selected report remains whole and keeps its original
timestamp. The existing shared-window requirement for model limits is unchanged.

The file helper opens with `O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC` before checking
for a regular, bounded, single-link file. The local usage reader additionally
requires the current owner; existing statusline ownership semantics are retained.
A pre/post-read stamp mismatch is transient and is retried by the next existing
poll. The local reader normally skips unchanged bytes; a rejected future
`fetchedAtMs` has a bounded revalidation point and relevant clock/wake recovery.

`StrictJSONPercentage` centralizes finite, non-Boolean values in 0...100.
Statusline capture decodes windows and producer information from one JSON parse.
Projection still recomputes freshness/expiry every poll but publishes only
changed values. UI Auto captions use the existing quota resolver and do not
start a request. Validation of this release is recorded separately in
[RELEASING.md](RELEASING.md).

## Local usage cache as the primary Claude source (introduced in 4.1.0)

Version `4.1.0 (24)` introduced this source. It changed only the
Claude side; Codex ownership, preferences and cache v2 are unchanged.

### Source tiers

Claude data comes from three tiers. `ClaudeQuotaStore` owns one slot per tier,
the poll schedule and the notification baseline; it never merges slots.

1. **Primary: Claude Code's local usage cache.** Claude Code writes the result
   of its own plan-usage fetch, the data behind its `/usage` screen, into its
   global state file under the `cachedUsageUtilization` key; Claude Code
   2.1.208 and later keep it as "last-known usage". `ClaudeLocalUsageCacheReader`
   interprets that key and nothing else.
2. **Backup: the status-line connection (statusline bridge).** The existing
   passive connection is shown when its report is strictly newer than the
   cache, or when the cache is absent or unreadable. Producer-fingerprint
   confirmation is unchanged.
3. **Last option: the CLI `/usage` read.** It stays default-off behind
   `claude.cliUsageEnabled.v1` and keeps its quota-consumption warning. When
   enabled it runs on the existing refresh interval and its result participates
   in selection; disabling it discards only CLI data. `readOnceWithCLI()` runs
   the official CLI exactly once regardless of the switch. With the switch off,
   its one-shot client retires afterwards; when on, it reuses the regular client.
   If Claude Code writes an updated cache, the primary tier reads it on a later
   poll; Codex94 never writes or force-refreshes that file.

This replaces 4.0.1's rule that CLI mode never loads passive reports. That rule
isolated two mutually exclusive modes whose data could not be compared; 4.1.0
treats the same sources as tiers of one selection with comparable observation
times. Explicit mode switches no longer clear the other source's data. Instead
`ClaudeQuotaFreshnessPolicy.select` decides what is shown. The notification
baseline is kept across eligible tier switches with forward observation time.
An observed cache identity change or loss, a different statusline producer, or
a rejected CLI login resets it. Cross-source account identity is not proven. An
automatic CLI failure is projected while CLI data is shown or while the shown
passive report is out of date. A one-time failure is shown beside its button
only; a successful one-time report participates in normal quota selection.

### `ClaudeLocalUsageCacheReader` ownership

The reader owns the file location, the safe-open rules and the parse. The file
is `~/.claude.json`, or `$CLAUDE_CONFIG_DIR/.claude.json` when that variable is
set in Codex94's own environment, mirroring Claude Code. It opens read-only
with `O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC`, refuses symlinks anywhere in the path, foreign owners,
non-regular or hard-linked files and anything over 16 MiB, and never writes.
It records a size/mtime/inode stamp and returns `.unchanged` without parsing
when the stamp matches, except when a transient read or rejected future timestamp
needs revalidation.

From the usage key it keeps `fetchedAtMs` as the report time (when Claude Code
fetched usage, not when Codex94 read the file), `five_hour`/`seven_day`
utilization with strict ISO-8601 `resets_at`, and model-scoped weekly limits
(`weekly_scoped` entries, at most 16; the older `seven_day_opus`/`seven_day_sonnet`
keys are a fallback). Everything else in the file, including account email,
organization, project paths and MCP settings, is discarded as soon as the JSON
is decoded and is never retained, logged or exported. The `accountUuid` is
returned to the store, which compares it in memory with the previous reading
only to detect a different login and reset the notification baseline. It is
never persisted and never enters the diagnostics export; it is not account
verification for any other purpose.

Bytes that do not decode, for example mid-rewrite, are reported as
`.unparsable`: the store keeps its last good report as a candidate while the
published state reads `invalid`, and the completed write changes the stamp and
is parsed on the next poll. A decoded document without a usable
`cachedUsageUtilization` (after `/logout` or a layout change) is `.invalid` and
drops the previous report.
`ClaudeLocalUsageCacheState` (`absent`, `unreadable`, `invalid`, `valid`) is
published for Dashboard → Services and for the `claudeLocalCache` diagnostics
line; no path accompanies it.

### `ClaudeQuotaFreshnessPolicy`

The policy is pure. The store owns slots and schedule; the policy decides which
report is shown and whether it still counts as current.

- `select(localCache:statusline:cli:at:)` rejects candidates without a usable
  snapshot, starts with the cache and lets a backup
  replace it only when its `reportedAt` is strictly newer; equal times keep the
  primary. Exactly one report is shown, so percentages from different sources
  are never averaged or merged.
- `maximumAge(for:)` is 60 minutes for the cache (Claude Code's own last-known
  rule), the existing 10-minute baseline for statusline, and
  `max(10 min, refresh interval + 60 s)` for CLI.
- `isCurrent` also requires a non-empty snapshot. Windows whose reset time
  passed disappear and are never shown as 100% remaining. Past the age limit
  the UI shows the amber cached marker and the data time but keeps the numbers.

### Presentation and models

`ClaudeQuotaSource` gains `localCache` ahead of `statusline` and `cliUsage`.
`ClaudeQuotaReport` carries optional `modelLimits`; `snapshot(at:)` projects
them as extra weekly-only buckets with identifiers derived from the display
name (`claude.model.<slug>`), so a "Fable" weekly limit appears under
**Per-model weekly limits** on the Claude card, in the menu-bar quota picker
and in automatic most-constrained selection. Older cached reports without the
field decode with an empty list. The Claude card shows the source name and the
**Claude Code fetched** time and has three new empty states: no cache yet (run
`claude` in a terminal and enter `/usage`, or use the one-time CLI read), cache
unreadable, and windows expired. Dashboard → Services gains a read-only
**Claude data sources** section showing the three tiers, the current source
and the local-cache state.

### Boundaries kept

No preference key, cache file, entitlement, network endpoint or installer step
is added. `AppUpdateClient.swift` remains the only network client; no HTTP,
OAuth, Keychain, cookie or token reading exists. `security_check.sh` now also
forbids `.credentials.json`, the `Claude Code-credentials` Keychain item,
`SecItemAdd`/`SecItemUpdate`/`SecItemDelete`, `SecKeychain` and the
`api/oauth/usage` endpoint string in production sources, and requires that the
literal `claude.json` appears only in `Services/ClaudeLocalUsageCacheReader.swift`.

Codex94 reads only files the official client leaves on the Mac because
[Anthropic's legal page](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use)
(2026-02-20) restricts OAuth tokens to Claude Code and native Anthropic apps
and forbids third parties from collecting, storing or intermediating Claude.ai
credentials or session tokens. The paused OAuth work lives in draft PR #44 and
is not part of 4.1.0. Validation records for each revision are separate; see
[RELEASING.md](RELEASING.md).

## 4.0.2 candidate (carried into 4.1.0): callback safety and compact presentation

The system notification adapter accepts callbacks on the system's call-out
queue through an explicit `@Sendable` boundary. It passes transferable status
values and resumes continuations; it must not inherit a MainActor requirement
inside a UserNotifications completion block. The notification controller and
its published state remain on MainActor. Test authorization lookup, permission
completion and delivery completion from a background fake adapter, preserving
disabled defaults and cancellation/generation rules.

Dashboard and the popover reuse the same provider snapshots with different
presentations: large service cards in Dashboard, terminal-style compact rows
and a smaller reset-count display in the popover. This adds no quota request
or reset-consumption path.

`MenuBarServiceMode.compactBoth` renders two separate provider rings in one
native item. `single` retains one provider item; the saved `both` value retains
two independent native items. The existing `menuBarServiceMode.v1` key stores
the choice without migrating `both`. Single-provider items omit redundant
name labels. Keep provider values and stale/error states independent, and
retain the existing image-cache and shared-popover ownership.

The passive Claude source remains **Claude Code statusline output**. Ordinary
Claude App/web chat does not emit that local report, so a configured connection
without data is not evidence of a failed login. The official Usage-page action
opens a fixed HTTPS URL in the system browser; it does not scrape the page or
read cookies, credentials or quota JSON. No quota API is added, and the CLI
reader remains a separate default-off option.

## 4.0.1: independently enabled providers

Version `4.0.1 (22)` was the previous stable release. The `v4.0.0` tag is
retained as an unpublished candidate. Passive statusline reports are the
default Claude data source. The earlier optional CLI input-footer compatibility
fix is retained; it does not make that reader an automatic fallback.

`QuotaProviderID` identifies Codex and Claude. Existing Codex preference keys
and cache v2 stay compatible; new monitoring/display choices and Claude
preferences have their own keys. Monitoring defaults to Codex only. A display
selection never implicitly enables a provider or starts a request.
`claude.cliUsageEnabled.v1` is a separate default-off opt-in for the optional
CLI reader. Existing Claude monitoring preferences do not enable it during
migration. Without it, no CLI client is created and refreshes load only the
passive sources: the local statusline cache and, since 4.1.0, Claude Code's
local usage cache (see above). Turning it off retires in-flight work and clears
CLI reports while leaving statusline monitoring available.

Passive statusline is the default data path. The conditional OAuth proposal was
reviewed against [Anthropic's credential-use rules](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use)
on 2026-10-03; its authorization prerequisite is not met, so no OAuth transport,
credential reader or refresh-token flow is added. Consequently, OAuth-specific
401/429 handling and automatic sign-in recovery are not claimed as implemented.

The [official statusline schema](https://code.claude.com/docs/en/statusline#available-data)
provides quota windows and a session identifier, but no verified account identity.
CLI mode therefore never loads passive reports as automatic fallback, and
explicit mode switches clear visible data from the previous source (4.1.0
replaces this with tiered selection; see above). Passive monitoring
persists the selected producer fingerprint; another or unknown producer requires
explicit adoption and resets notification comparisons. This is report-stream
isolation, not account authentication, and cannot detect an account change inside
the same session. Cached values are always labelled accordingly. Normal Claude
Code use must supply reports; ordinary App/web chat is not this source. The
monitor never sends a model prompt to populate reports.

`AppStore` composes the existing Codex state, `ClaudeQuotaStore` and global app
services. It routes enable/disable, wake, popover and shutdown events. Each
provider owns its request generation, single-flight operation, background task,
cached data and notification controller/policy. Disabled Codex also invalidates
its Token store. Old results cannot update the next enabled generation.

`ProviderPresentation` shares pure selection/options and snapshot projections
between native status items and the floating panel. `AppDelegate` owns one or
two native status items and one shared popover showing all enabled providers.
All-disabled mode retains a neutral settings entry. `MenuBarStatusRenderer`
keeps the existing sRGB non-template path and includes provider labels in its
image cache key. The floating window follows its saved provider selection and
resizes from the actual available windows.

`ClaudeCLIUsageClient` runs only official Claude Code's built-in `/usage` in an
owned directory. It uses bounded PTY output with screen replay, terminal-query
responses and the shared process-group lifecycle. Unknown terminal/login
screens fail explicitly. `ClaudeResetTextParser` parses supported displayed
dates without fabricating a reset at fetch time plus five hours.

`ClaudeStatuslineBridge` is selected before SwiftUI application startup. It
accepts stdin, forwards the user's previous statusline command and writes only
whitelisted quota data. `ClaudeStatuslineInstaller` owns preview, opt-in
configuration, key backup and conflict-aware removal. The Claude store owns
report freshness: cache reads and duplicate statusline reports cannot renew
quota age, reset-expired windows disappear, and unknown data is never 100%.

Claude reset reads reuse the store's existing 15-second poll; they add no timer.
Raw reported reset dates produce sorted, distinct `resetsAt + 5` targets, even
after their windows disappear from the display. A refresh accepted by the
single-flight path records its start time for due-target coverage. A request begun before a target that
finishes afterward leaves one follow-up read pending, while simultaneous manual,
background and reset reads remain single-flight. A failed reset attempt consumes
that target instead of retrying it every poll; normal refreshes and other due
targets remain eligible. Coverage belongs to the report source/producer context;
passive reports do not inherit a CLI request's coverage. Authentication failure and disable clear
the reset context, and clock rollback does not repeat a consumed target.
`nextAutomaticRefreshAt` is the earlier normal/reset due time, not a guarantee of
execution at that instant: the next poll and any in-flight read can delay it.

Shared quota models preserve Codex's strict integer wire/cache contract while
carrying an optional validated fractional percentage for Claude. Auto selection,
warning colors and notification thresholds compare precise values. Compact
menu-bar percentages are rounded; expanded quota text preserves one decimal.

Validation must cover both enabled services, either service alone, all disabled,
late results, quick re-enable, missing/fractional windows, source changes,
statusline restoration and process cleanup. Synthetic UI/render tests and
unattended live monitoring are separate release evidence.

| Owner | Responsibility |
| --- | --- |
| `AppDelegate` | Compose the running app, own one or two native status items and the shared popover, retain Dashboard and floating-window controllers, route mouse/hotkey actions, and register/remove platform observers. Forward wake and clock events to the store. |
| `DashboardWindowController` / `DashboardWindowState` | Own the reusable window lifecycle, size/restoration behavior, visibility, and selected page. Opening a page must not recreate application services. |
| `FloatingWindowController` / `FloatingWindowState` | Own the reusable native panel, placement/screen fitting, pinning, visibility, and expansion. Receive the existing store; do not own another quota fetcher or polling timer. |
| `AppStore` | Own quota state, cache writes, selection reconciliation, notification observations, freshness-gated popover reads, and single-flight/background/Reset coordination. Own and cancel the bounded transient retry budget; isolate unverified identity from child features. |
| `MenuBarStatusRenderer` | Own the native status-button image, visible-input render cache and appearance/backing-scale observer. Reuse pure SwiftUI content for transparent sRGB artwork; update only accessibility/tooltip text on freshness ticks. Never fetch quota. |
| `TokenUsageStore` | Own on-demand aggregate statistics and their request lifetime. Replace snapshots, reject obsolete results, and manage retired clients without coupling statistics failures to quota status. |
| `AppUpdateController` | Own the explicit GitHub metadata check and its UI state. It does not poll, download, install, or share quota authentication. |
| Token image export views/helpers | Render the current prepared chart without interaction controls or identity; own explicit PNG save/copy actions. Pass the pasteboard explicitly so tests can isolate it. |
| `CodexExecutableLocator` | Own explicit-path precedence, known bundled/standard CLI candidates, and bounded `--version` compatibility checks. Tests inject App roots and synthetic executables. |
| `ClaudeLocalUsageCacheReader` | Own the Claude Code state-file location (home or `CLAUDE_CONFIG_DIR`), the read-only `O_NOFOLLOW` open with its symlink/owner/type/size refusals, the size/mtime/inode stamp, and parsing of the `cachedUsageUtilization` key only. Return a report, the in-memory account identifier and a state; never write, retain other keys, or start a request. |
| `ClaudeQuotaFreshnessPolicy` | Own the pure source-tier selection (cache first; a backup replaces it only when strictly newer) and the per-source maximum ages. Decide only what is shown and whether it is current; own no slot, timer or I/O. |
| Platform and transport services | Own Codex subprocesses, notification delivery, hotkey registration, and the fixed update HTTP request. Keep bounded process-group termination in its existing service. |
| Pure models and support types | Own parsing, date/count rules, selection projections, chart preparation, formatting inputs, and scheduling decisions without starting I/O. |

## Rules for focused reuse

- Reuse a function when the field semantics match. `SourceDay` and
  `StrictJSONInteger` belong in `Support/ServiceValues.swift`, not in a
  Token-specific model imported by the quota parser. Missing is not zero;
  do not impose nonnegative-count rules on quota percentages that intentionally
  preserve extreme inputs before display clamping.
- A request's single-flight status and its source context are separate facts.
  Results from an obsolete executable/identity context must not update state,
  cache, preferences, notifications, or another feature's snapshot. Preserve
  queue completion so the current preference-triggered request can still run.
- Keep quota, Token usage, and update-check lifecycles separate. Their triggers,
  persistence, errors, and cancellation rules differ; shared task syntax alone
  is not a reason to replace them with one generic store.
- Project chart dates and aggregates from a snapshot/range once, then reuse
  them for marks, selection, interval comparison, tables, CSV, and PNG. Custom
  ranges use source-day coordinates; comparison requires complete intervals
  and a nonzero baseline before displaying percentage change. Reuse formatting
  within an explicit locale/calendar/time-zone context; do not share mutable formatter state across
  unrelated actors or silently change the service's date interpretation.
- Views receive state and narrow actions. Rendering relative time, changing
  style/range, or navigating recovery pages must not start quota requests or
  write its cache. AppKit window/input ownership stays at the platform boundary.
- Make the dependencies needed by a test injectable. Use controlled fetchers to
  pause old and new responses independently, and fake notification/update/input
  services instead of real accounts, system registration, or browser actions.
- Reset may retire a Token client in the background, but application shutdown
  must still drain owned clients with the existing bounded termination policy.
  Moving ownership must not weaken process-group cleanup or ignore old results.

## Validation seams

`AppStoreTests` covers quota ordering, cache/selection effects, wake/Reset
coordination, and shutdown. `TokenUsageStoreTests` covers request generations
and retired clients. Version `4.1.0` adds `ClaudeLocalUsageCacheReaderTests`
and `ClaudeQuotaFreshnessPolicyTests` for the safe-open refusals, strict
parsing, stamp reuse, tier selection and per-source ages; both passed in the local Xcode 27.0 run, and CI on Xcode 16.4 is pending. Parser and presentation tests cover strict values, dates,
gaps, chart projections, and CSV. External synthetic UI tests cover actual
window/navigation interactions separately from these model tests. Version
`3.1.0` adds Floating interactions and Token custom-range controls. Image tests
inspect PNG dimensions/format and cached/fresh image text, and use named
pasteboards; actual synthetic
images still need visual review for clipping, labels, theme, and stale status.
Cross-Space/fullscreen behavior needs native-panel acceptance, not a conclusion
from the collection-behavior flags alone.

The release gate builds the Universal App once; the DMG packager verifies its
complete payload and signing boundary. The source installer owns its lock,
staging, and rollback. Share small validation helpers where appropriate rather
than duplicating those ownership boundaries. See [CONTRIBUTING.md](../CONTRIBUTING.md)
and [the release workflow](RELEASING.md) for required evidence and distribution rules.


## 3.1.1: floating quota availability

`FloatingQuotaLayout` derives the strip's 480/680-point preferred width and
compact metrics from the actual selected bucket's optional 5-hour window.
Plan labels do not override real quota data, and a reported 0% remains a real
window. The cold placeholder uses the weekly-only layout.

The controller observes `AppStore.objectWillChange` on the next main-run-loop
turn, after forwarded preference and snapshot values have committed. It reads
the selected menu-bar bucket rather than the independently browsed popover
bucket, and resizes only when the quota layout changes. Fitting uses the
current panel position so a pending drag save cannot restore an older position.
Existing screen clamping, motion preferences, pin state and teardown remain
owned by the controller; layout changes do not request or cache quota data.

## 3.1.2: bundled executable discovery

`CodexExecutableLocator` checks the nested `CodexCLI.app` executable in the two
known `/Applications/ChatGPT.app` and `/Applications/Codex.app` roots before
legacy flat-resource paths. Homebrew and standard CLI fallbacks remain, while
an explicit manual choice is authoritative and is not bypassed on failure.
Discovery does not recursively search directories or read authentication data;
transport and quota-decoding responsibilities remain separate.

## 3.1.3: recovery and native status rendering

The transport validates quota first, then allows a short optional-account read.
The quota response's timestamp is retained across that optional wait. Explicit
authentication failure and shutdown still fail the request. The store owns the
bounded retry budget and cancels obsolete retry tasks with its existing
connection-generation boundary. Missing identity is not paired with a previous
account's details or Token snapshot; notification baselines are isolated too.

`MenuBarStatusRenderer` owns the native button image and reuses
`MenuBarStatusContent` to create transparent, sRGB, non-template artwork. It
rerenders only when visible inputs, appearance or backing scale change. Its
freshness timer updates accessibility/tooltip text only, without quota requests.
The maintainer separately confirmed the reported menu-bar Spaces color flash
was resolved on the tested Mac with the reviewed CI candidate. This does not
cover every macOS version, floating-panel behavior across Spaces, fullscreen,
or keyboard interaction. Static image tests alone do not establish animation
behavior; the exact candidate identity is in [RELEASING.md](RELEASING.md).


## 3.1.4: bounded recovery and schedule presentation

Quota request/transaction budgets are 10/20 seconds; Token usage remains 5/15,
and optional identity remains capped at 2 seconds. Transient quota failures
allow three extra attempts after 5/20/60-second delays. The store continues to
own single-flight reads, retry cancellation and the background/reset schedules.

`nextAutomaticRefreshAt` projects the earliest armed retry, background or reset
deadline only while waiting after a transient failure. Unknown wall-clock
estimates suppress the date. Views share a local `HH:mm:ss` formatter and
localized text; native status text changes do not invalidate its image cache.
No new polling timer is added. Failed transport stages log fixed categories and
durations at error level without server messages or payloads.
