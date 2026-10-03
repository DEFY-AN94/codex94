# Component ownership and reuse

This describes ownership and reuse constraints in the published stable
[`3.1.4 (20)` release](https://github.com/DEFY-AN94/codex94/releases/tag/v3.1.4).
Test results and final package acceptance are separate evidence; this document
defines component responsibilities, not a substitute for those records.

## 4.0.0 development: independently enabled providers

`QuotaProviderID` identifies Codex and Claude. Existing Codex preference keys
and cache v2 stay compatible; new monitoring/display choices and Claude
preferences have their own keys. Monitoring defaults to Codex only. A display
selection never implicitly enables a provider or starts a request.

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
| `AppDelegate` | Compose the running app, own the status item and popover, retain Dashboard and floating-window controllers, route mouse/hotkey actions, and register/remove platform observers. Forward wake and clock events to the store. |
| `DashboardWindowController` / `DashboardWindowState` | Own the reusable window lifecycle, size/restoration behavior, visibility, and selected page. Opening a page must not recreate application services. |
| `FloatingWindowController` / `FloatingWindowState` | Own the reusable native panel, placement/screen fitting, pinning, visibility, and expansion. Receive the existing store; do not own another quota fetcher or polling timer. |
| `AppStore` | Own quota state, cache writes, selection reconciliation, notification observations, freshness-gated popover reads, and single-flight/background/Reset coordination. Own and cancel the bounded transient retry budget; isolate unverified identity from child features. |
| `MenuBarStatusRenderer` | Own the native status-button image, visible-input render cache and appearance/backing-scale observer. Reuse pure SwiftUI content for transparent sRGB artwork; update only accessibility/tooltip text on freshness ticks. Never fetch quota. |
| `TokenUsageStore` | Own on-demand aggregate statistics and their request lifetime. Replace snapshots, reject obsolete results, and manage retired clients without coupling statistics failures to quota status. |
| `AppUpdateController` | Own the explicit GitHub metadata check and its UI state. It does not poll, download, install, or share quota authentication. |
| Token image export views/helpers | Render the current prepared chart without interaction controls or identity; own explicit PNG save/copy actions. Pass the pasteboard explicitly so tests can isolate it. |
| `CodexExecutableLocator` | Own explicit-path precedence, known bundled/standard CLI candidates, and bounded `--version` compatibility checks. Tests inject App roots and synthetic executables. |
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
and retired clients. Parser and presentation tests cover strict values, dates,
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
