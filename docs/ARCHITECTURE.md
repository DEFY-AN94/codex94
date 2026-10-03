# Component ownership and reuse

This describes ownership and reuse constraints for development `4.1.0 (24)`,
with the separate unreleased `4.0.2 (23)` maintenance candidate described below.
The published stable version remains the
[`4.0.1 (22)` release](https://github.com/DEFY-AN94/codex94/releases/tag/v4.0.1),
published on 2026-10-03 (Australia/Melbourne).
Test results and final package acceptance are separate evidence; this document
defines component responsibilities, not a substitute for those records.

## 4.1.0 development: OAuth coordination with an unavailable production provider

`ClaudeQuotaStore` remains the only Claude state exposed to the UI. It delegates
`oauthPreferred` to `ClaudeOAuthMonitor`; `statuslineOnly` and explicitly selected
`legacyCLI` retain separate local paths. Claude stays disabled by default, while
the new source choice defaults to OAuth preferred. An existing explicit legacy
CLI opt-in is preserved. The OAuth path and passive fallback cannot construct a
CLI fetcher; source changes retire the previous generation and clear its data.

`ClaudeOAuthCredentialProvider` separates credential ownership from HTTP. Its
production implementation is `UnavailableClaudeOAuthCredentialProvider`, which
performs no credential, browser, Keychain, file or CLI access. Real authorized
client/callback/scope information and a controlled integration check remain
pending. Browser sign-in, credential storage and OAuth connect/disconnect UI are
not implemented; accepting explicit in-memory credentials in injected clients
is not evidence of a completed production integration.

`ClaudeOAuthUsageClient` owns fixed usage/profile GET endpoints, separate 10/2
second deadlines, bounded 64 KiB response streaming, destination validation and
typed errors. Ephemeral sessions disable cookie/credential/cache storage and
reject redirects and ambient authentication. `ClaudeOAuthResponseParser` accepts
only supported windows, finite percentages, strict optional reset dates and
unambiguous account/organization UUIDs; missing data stays unknown.

`ClaudeOAuthMonitor` owns one request task and one coordinator timer. Usage and
profile run concurrently: quota is published as soon as it is usable, labelled
identity-pending until the current profile is verified. Profile failure neither
borrows old identity nor turns a successful quota read into a quota error.
Pending/failed identity suppresses OAuth cache writes and notifications. A normal
refresh that confirms the same account preserves its private notification
baseline; changed identity, credential context or source resets it.

Current credential-context and generation checks discard late results. A failed
quota transaction may recover once: application-owned credentials call the
provider's renewal contract; external credentials call its read-only reload
contract. No production renewal implementation exists yet. Auth/scope rejection
suspends that credential context without a manual bypass. A 429 applies shared
cooldown to both endpoints and retains any later deadline; invalid/missing
Retry-After uses five minutes. Network/server failures have at most two automatic
recovery attempts at 60-second intervals, then return to the configured cadence.

Scheduling uses process-relative `ContinuousClock` seconds, including sleep.
Popover/wake reuse requires both wall-clock query age and continuous elapsed age
to be nonnegative and below 60 seconds. Wake, manual, normal and reset reads share
the same request slot. Reset coverage prevents repeated attempts after clock
rollback. Next-attempt text is a projection, not a guarantee of execution while
the OS is asleep or a request is active.

`ClaudeOAuthQuotaCache` only accepts normalized OAuth reports with verified
account/organization context. Separate digest-named private files isolate each
context; tokens and raw responses are never cached. Source, query completion time
and identity confidence travel with the report. Query completion is local timing,
not a server-provided measurement timestamp.

`ClaudeQuotaSourcePolicy` admits only fresh identifiable passive reports with
valid resets as fallback candidates. The candidate is frozen for explicit user
confirmation; an existing passive producer preference proves no OAuth account.
Adoption marks the report unverified and preserves its original time. Only the
adopted producer may update it automatically; another producer requires new
confirmation. Expiry removes unusable data; credential/source changes clear the
association. OAuth recovery restores the primary source and resets notification
comparison. Statusline reports never emit alerts; the separately opted-in legacy
CLI behavior remains independent.

## 4.0.2 candidate: callback safety and compact presentation

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

Version `4.0.1 (22)` is the stable release. The `v4.0.0` tag is retained as an
unpublished candidate. Passive statusline reports are the
default Claude data source in that published version. The earlier optional CLI
input-footer compatibility fix is retained; it does not make that reader an
automatic fallback.

`QuotaProviderID` identifies Codex and Claude. Existing Codex preference keys
and cache v2 stay compatible; new monitoring/display choices and Claude
preferences have their own keys. Monitoring defaults to Codex only. A display
selection never implicitly enables a provider or starts a request.
`claude.cliUsageEnabled.v1` is a separate default-off opt-in for the optional
CLI reader. Existing Claude monitoring preferences do not enable it during
migration. In the 4.0.1 path, without it no CLI client is created and refreshes
only load the local statusline cache. Turning it off retires in-flight work and
clears CLI reports while leaving statusline monitoring available.

For 4.0.1, passive statusline was the default data path. The conditional OAuth
proposal was reviewed against [Anthropic's credential-use rules](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use)
on 2026-10-03; its authorization prerequisite was not met, so that release added
no OAuth transport, credential reader or refresh-token flow. The 4.1.0 development
components above supersede this transport description only; they do not establish
production authorization or automatic sign-in.

The [official statusline schema](https://code.claude.com/docs/en/statusline#available-data)
provides quota windows and a session identifier, but no verified account identity.
CLI mode therefore never loads passive reports as automatic fallback. Explicit
mode switches clear visible data from the previous source. Passive monitoring
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

Legacy CLI reset reads reuse the store's existing 15-second poll; they add no timer.
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
| `ClaudeQuotaStore` / `ClaudeOAuthMonitor` | Keep one Claude UI state owner; delegate OAuth requests, credential generations, identity verification, cooldown, scheduling and explicit passive fallback to the independent monitor. |
| `ClaudeOAuthCredentialProvider` / `ClaudeOAuthQuotaCache` | Separate credential ownership from transport; production acquisition remains unavailable. Cache normalized reports only under verified account/organization context. |
| Platform and transport services | Own Codex subprocesses, notification delivery, hotkey registration, the fixed update HTTP request and separately allowlisted Claude OAuth GETs. Keep bounded process-group termination in its existing service. |
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
