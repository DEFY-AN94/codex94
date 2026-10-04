# Privacy

Codex94 is a macOS utility. It has no analytics, advertising, telemetry upload,
crash-reporting SDK, system profiling, or Codex94-operated server. The published
stable version is [`v4.1.0 (24)`](https://github.com/DEFY-AN94/codex94/releases/tag/v4.1.0),
released on 2026-10-05 (Australia/Melbourne). It includes the user-triggered
public GitHub release check described below, without automatic installation.

The unpublished `4.0.2 (23)` candidate, carried forward into 4.1.0, changes
notification callback handling and quota presentation. Its compact dual-ring
mode uses the existing service-mode preference and does not combine provider
percentages or add quota collection.
The official Claude Usage-page button hands a fixed HTTPS URL to the system
browser only when clicked. Codex94 does not inspect that page, its cookies or
login state. Browser navigation is separate from Codex94's quota reader and
is not telemetry uploaded by this project.

## 4.1.0: Claude Code's local usage cache

Version `4.1.0 (24)` was published on 2026-10-05 (Australia/Melbourne). Its
changes are Claude-side only, and Codex quota behavior is unchanged. Codex94 gains a read-only primary Claude
source: the plan-usage cache that Claude Code itself writes into its global
state file after fetching `/usage`, described in the next section. The existing
status-line connection (the statusline bridge) becomes the backup source and
the optional CLI `/usage` read becomes the last option. The CLI reader stays
off by default and keeps its quota-consumption warning; it is no longer
mutually exclusive with the passive sources, and disabling it discards only
CLI data. A new **Read once with the CLI** button in Dashboard → Services
starts the official CLI exactly once, regardless of that switch, under the
same warning. Afterwards Claude Code refreshes its own cache, which the primary
source then picks up. Exactly one report is shown at a time; percentages from
different sources are never averaged or merged.

Model-scoped weekly limits found in the same cache appear as additional Claude
quota buckets in the card, the menu-bar quota picker and the automatic
most-constrained selection. They are derived from the same read; no further
request, file or preference is added. Redacted diagnostics gain one
`claudeLocalCache` line whose value is `absent`, `valid`, `unreadable` or
`invalid` (or `none` while Claude monitoring is off), without a path or account
identifier. No new preference key, cache
file, entitlement, network endpoint or installer step is introduced, and
`claude.cliUsageEnabled.v1` keeps its meaning.

Direct OAuth remains out of scope. Anthropic's
[legal page](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use)
(2026-02-20) restricts OAuth tokens to Claude Code and native Anthropic apps and
forbids third parties from collecting, storing or intermediating Claude.ai
credentials or session tokens. Codex94 therefore reads only files that the
official client leaves on the Mac. The paused OAuth work lives in draft PR #44
and is not part of 4.1.0.

## Claude Code local usage cache (4.1.0)

Claude Code 2.1.208 and later keep the result of their plan-usage fetch, the
data behind the `/usage` screen, as "last-known usage" under the key
`cachedUsageUtilization` in their global state file `~/.claude.json`. When
`CLAUDE_CONFIG_DIR` is set in Codex94's own environment, the file is read from
that directory instead, mirroring Claude Code. Codex94's
`ClaudeLocalUsageCacheReader` is the only code that names this file, and it
interprets only that one key.

From the key it extracts `fetchedAtMs`, which becomes the report time shown as
"Claude Code fetched", the `five_hour` and `seven_day` utilization percentages
with their ISO-8601 `resets_at` values, and model-scoped weekly limits (display
name, percentage and reset time; at most sixteen rows). Everything else in the
file is discarded immediately. The file also contains the account email,
organization, project paths and MCP settings; Codex94 never retains, logs,
displays or exports them. The `accountUuid` value is compared in memory only,
so that a cache written by a different login starts a fresh notification
baseline. It is never persisted, logged, shown or exported.

The file is only read. The reader opens it read-only with `O_NOFOLLOW`, refuses
symlinks, hard-linked files, files owned by another user, non-regular files and
files larger than 16 MiB, and parses the bounded JSON. It re-parses only when
the file's size, modification time or inode changes, and it never creates,
writes, renames or deletes the file. The parsed quota windows enter the same
in-memory Claude state that previous versions already hold; they are not
written to `statusline-quota.json`, `UserDefaults`, the quota cache or logs.
Logs record fixed source/result words only. Codex94 never writes this file
itself; only Claude Code's own `/usage` fetch refreshes it, including one
started by the optional CLI reader or the explicit one-time CLI read above.

A cache report counts as current for 60 minutes after Claude Code fetched it,
matching Claude Code's own last-known rule. Older reports keep their numbers
and data time with the amber cached marker. Windows whose reset time has passed
disappear and are never shown as 100% remaining. The statusline bridge report
replaces the cache only when its observation time is strictly newer, or when
the cache is absent or unreadable; its existing producer-fingerprint
confirmation is unchanged. Codex94 still does not read `.credentials.json`, the
Keychain, browser cookies, tokens or conversation transcripts, and the
repository security scanner forbids those identifiers in production sources.

## Optional Claude monitoring (4.0.1)

Version 4.0.1 uses passive local reports by default and keeps the optional CLI
reader separate. The `v4.0.0` tag is preserved as an unpublished candidate.

Claude monitoring is off by default. Enabling monitoring alone reads existing
local status-line reports. A separate `/usage` option is also off by
default; only explicit opt-in permits starting the locally installed official
Claude Code program and its built-in `/usage` command. The option warns that
these CLI sessions may consume subscription quota; no zero-consumption guarantee
is made. Live `/usage` probing remains suspended. Direct OAuth integration is deferred under
[Anthropic's credential-use rules](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use);
Codex94 neither obtains nor refreshes Claude subscription tokens. Claude Code
owns subscription authentication and any connection to Anthropic. The probe
runs in a dedicated Codex94 directory, disables tools, hooks, MCP servers and
remote-control startup, and has bounded output, runtime and process cleanup.
Its folder-trust handler accepts only the verified, app-owned
`~/Library/Application Support/Codex94/Claude/UsageProbe` directory. Claude Code
may consult its own local state when rendering `/usage`; Codex94 extracts only
quota windows and reset labels from that terminal output.
It does not send a conversation prompt. Codex94 does not read Claude tokens,
browser cookies, Keychain entries or conversation transcripts.
The probe sets `DISABLE_AUTOUPDATER=1` and
`CLAUDE_CODE_SKIP_PROMPT_HISTORY=1` only in its child environment, requesting
that Claude Code skip updater work and prompt/session-history writes. These
are [official CLI controls](https://code.claude.com/docs/en/env-vars); older CLI
versions may not support the history control. Codex94 does not delete or scan
existing Claude conversation files, and does not alter the parent environment
or saved settings to apply these probe flags.

An optional statusline integration receives Claude Code's JSON through standard
input. Only 5-hour/weekly percentages and reset times enter the quota cache.
Source, observation times and opaque hashes for duplicate-report detection are
also stored locally; a session hash is not treated as account identity. Raw
JSON, directory/transcript paths and raw session IDs are not written to the
quota cache. Reading the same report again does not renew its data timestamp.
Reports can remain old while Claude Code is idle or closed. The interface
distinguishes a statusline report from an active CLI usage query.
Ordinary Claude App or web chat does not emit this Code statusline report.
Installing the connection or signing into the chat app alone cannot populate
the cache; no new quota API or automatic App/web reader is introduced in 4.0.2.
The selected passive producer fingerprint is also saved in preferences. It
pins one reporting stream across App restarts, not an authenticated account.
Reports from a different or unidentified producer require explicit adoption;
their raw session identifier is still never persisted. CLI mode does not
automatically consume the passive cache after a request failure.

Connecting the statusline explicitly previews a change to the user's Claude
settings. It preserves other settings, forwards the original command's stdin
and output, and stores only the previous statusline setting for restoration.
The local installation manifest includes the settings, cache and executable
paths and the original statusline command. These are configuration needed to
run and undo the integration, not quota telemetry. A modified statusline is
not silently overwritten during removal. Disabling Claude monitoring stops
its app tasks and quota capture; the original statusline still runs.
A conflicting installation has an explicit recovery action that forgets only
the verified old installation record while preserving current settings and
backups. It refuses to forget a record if the current command still references
that bridge, preventing a dangling statusline command.

Codex and Claude keep separate quota state, preferences, notification baselines
and refresh tasks. Menu-bar and floating-provider selection only change
presentation. This release monitors one default Claude Code profile and does
not merge accounts or infer subscription allowance from local Token counts.
The existing Token statistics/export features remain Codex-only.

New preference keys are `codexMonitoringEnabled.v1`,
`claudeMonitoringEnabled.v1`, `menuBarServiceMode.v1`, `primaryProvider.v1`,
`floatingProvider.v1`, `claude.cliUsageEnabled.v1`, `claude.passiveProducerID.v1`,
`claude.refreshInterval.v1`,
`claude.menuBarQuotaSelection.v1`, `claude.dualWindowBucketSelection.v1` and
`claude.notifications.v1`. The passive report is stored separately at
`~/Library/Application Support/Codex94/Claude/statusline-quota.json`; active CLI
snapshots remain in memory. Redacted diagnostics add only enabled-provider,
display-mode, Claude source/connection/error and report-time fields, not quota
values, usernames, session hashes or settings contents.

Before uninstalling Codex94 or reverting to a version before 4.0, disconnect an
installed statusline bridge from Services settings while the current App is
still available. This restores the previous command and avoids leaving a
command pointing to a removed or incompatible executable. Backups remain local.

## Quota recovery and status presentation (3.1.3–3.1.4)

Quota is requested before optional account details. An account-detail timeout
may leave a fresh quota snapshot with no identity; an earlier account's email
is not reused. In **Quota + account** mode, unverified identity clears or
invalidates account-dependent Token data and notification baselines. The optional
error state is in memory only and is not added to quota cache v2.

In 3.1.4, a transient quota failure may produce at most three additional read
attempts, after 5, 20 and 60 seconds (four attempts in one cycle). These reuse
the same read-only quota RPC, including when
the initial attempt followed a reset deadline; they never redeem reset credits.
A new user/normal polling cycle starts its own bounded budget. Authentication,
executable-discovery and malformed-data failures do not automatically retry.
Only fixed trigger/stage names, timings and error categories are logged; no
identity, response body, credentials or raw quota values are added to logs.
Failed stages use error-level logging so the fixed failure category and duration
remain available without retaining a server message or payload.

Quota reads use 10-second request and 20-second transaction budgets. Token usage
keeps 5/15 seconds, and optional account details keep a 2-second cap. The next
scheduled retry/background/reset time is held only in memory and displayed as
local clock text. Unknown estimates after a clock change are hidden. This text
adds no request, timer, stored preference or account identity.

Opening a connected popover with a successful snapshot less than 60 seconds old
reuses it instead of sending another read. The native menu-bar image and its
freshness tooltip derive only from existing quota/status state. Appearance,
backing-scale changes and the tooltip timer do not fetch quota, record desktop
content, or access account stores. The tooltip adds no account identity.

## Data access

Codex94 starts a locally installed Codex executable and uses these JSON-RPC
requests over the child process's standard input/output:

- `account/rateLimits/read` for quota windows and, when returned, the manual
  reset-credit count
- `account/read` with `refreshToken: false` only when **Quota + account** is
  selected
- `account/usage/read` on demand from the Token usage page introduced in `0.3.0`,
  independently of the quota/account-display choice

The Codex child process may contact OpenAI services using the login it already
owns. Codex94 does not receive, read, export, or persist that login, its cookies,
or its access and refresh tokens. Codex94 does not implement an OAuth flow or
make direct quota HTTP requests.

Version `0.1.9` may start the same quota read once for the earliest future Reset
across displayable windows, strictly at `resetsAt + 5` seconds or later. This
uses the existing Codex subprocess and single-flight refresh path; it does not
add a direct network interface, request a token, or enable account data when
**Quota only** is selected.

When account information is enabled, the returned email address is held only in
memory and displayed only in Dashboard. Switching to **Quota only** removes it
from the in-memory snapshot.

Version `0.2.2 (13)` reads only the authoritative
`rateLimitResetCredits.availableCount` total from that existing quota response.
It accepts a nonnegative integer, keeps zero distinct from missing/null data,
and does not retain individual credit identifiers or details. The count is
held only in memory, including a visibly cached last value after a failure.
It is not saved in the quota cache and returns to an unfetched state at a cold
start. Codex94 does not redeem reset credits or send a consume request.

## Token statistics (0.3.0)

First opening Token usage or pressing its Refresh button requests
`account/usage/read` through the same local Codex executable. The feature does
not read session logs, conversation databases or credential files. It does not
request `account/read`; quota-only mode remains independent of account display.
Statistics failures do not change the quota connection state.

Only the five documented summary numbers and daily date/token pairs are parsed.
Other fields, including thread-level details, are ignored and not retained.
The latest statistics snapshot is kept in memory only, never appended to the
quota cache or logged. Explicit executable/identity changes and detected
sign-out invalidate it; there is no cross-account history merge. On a transient failure, retained
values keep their original fetch time and are shown with an error status.

A user-initiated CSV export writes the displayed daily dates and token counts
to a location chosen by the user. It contains no identity, task titles, prompts,
credentials or raw RPC. User-initiated exports are separate from the app’s
memory-only statistics store.
Dates retain the service's calendar-day labels; the app does not assume its
undocumented reporting timezone or treat omitted days as zero usage.
The 7-day and 30-day views end at the latest returned date, not the current
local day. Filtering dates and inspecting the chart do not make another request.
`tokenUsageChartStyle.v1` stores only the selected bar/line presentation in
UserDefaults. Changing chart style reuses the loaded response and makes no
request or statistics-cache write.
Summary scope and complete history coverage are unspecified; the app does not
infer model/project, input/output, cost, hourly, or thread-level statistics.

### 3.1.0: custom ranges and chart images

Custom start/end dates are view-local state. The app uses UTC calendar
coordinates to preserve source date labels, not to infer the service's
reporting timezone. Date filtering, reported averages/peaks, coverage, and
previous-interval comparison derive only from the loaded snapshot. They do not
request new data, fill missing days with zero, or create a history database.

An explicit PNG export writes the selected chart to a user-chosen file.
**Copy chart image** writes that PNG to the macOS general pasteboard only after
its button is clicked. Images follow the selected range/style/language/theme
and include date range, fetch time, coverage, and stale-data status when
applicable. They contain no account identity, service-summary cards, task
content, credentials, paths, or raw RPC. Exported files and clipboard contents
exist independently of the in-memory snapshot; the app does not read or upload
the clipboard. Automated copy tests use isolated named pasteboards.

## Data stored locally

`~/Library/Application Support/Codex94/quota-snapshot.json` uses cache schema v2
to store quota-bucket identifiers and optional names, plan type, quota window
types and durations, percentages, reset times, and fetch time. Legacy
single-bucket snapshots are migrated into this versioned structure. The cache
excludes email, account ID, tokens, RPC payloads, and executable paths. Its mode
is `0600`, and the containing directory is owner-only.

macOS `UserDefaults` stores UI preferences, refresh frequency, the selected
account-information mode, the preferred menu-bar quota selection, and an
optional Codex executable path chosen by the user. The model bucket being
browsed in the popover is held only for the current app run and is not written
to `UserDefaults`. macOS may also store the Dashboard window frame and
launch-at-login state.

Version `0.1.8` introduced two UI preference keys; `0.1.9` reuses both keys and
their migration without adding another preference:

- `menuBarLayout.v1` stores the selected layout. In `0.1.9`, the same running
  status item applies it immediately. It remains separate from the existing
  menu-bar quota selection and its legacy migration.
- `statusAccentOverrides.v1` stores up to four independent, opaque sRGB color
  overrides as normalized six-digit uppercase `RRGGBB` values. Invalid values fall back
  for the affected role. **Restore Default Colors** clears only these overrides,
  not quota selection, layout, theme, language, paths, or window settings.

Version `0.2.2 (13)` adds three preference keys while retaining cache v2:

- `dualWindowBucketSelection.v1` stores the fourth layout's bucket selection,
  independently of the original three layouts' existing quota selection.
- `globalHotKey.v1` stores the optional keyboard shortcut's key and modifiers.
  No shortcut is registered by default. A configured shortcut must include
  Control or Option, with optional Command and Shift. System hotkey registration
  does not record typed text or add keyboard-event logs.
- `notifications.v1` stores the enabled state, warning thresholds, additional
  bucket choices, and recovery-alert preference. It does not store observed
  quota values, notification baselines, or per-cycle delivery history.

Version `3.1.0 (16)` adds `floatingWindowPinned.v1` for pin state and
`floatingWindowPosition.v1` for screen coordinates only. Floating visibility
and expansion are memory-only. The strip reads the same quota snapshot;
showing, dragging, pinning, or expanding it adds no quota request, reset-credit
consumption, cache field, or polling cadence. Its explicit refresh action uses
the existing manual refresh path.

Codex94 also keeps the selected Dashboard section and the post-reset task state
only in memory; the existing macOS window-frame autosave behavior is unchanged.
Overview reads the existing snapshot and does not persist a second model, new
identity data, or page-specific quota data. Absolute Reset text and scheduling
derive from the existing quota reset timestamp. They add no cache fields or
persistent Reset ledger. Local accessibility labels may include visible quota
and Reset information, but Overview identifiers use page-local ordinals rather
than account identity, opaque bucket identifiers, or executable paths.

Changing layout/colors, opening or browsing Overview, rendering Reset text, or
opening a recovery destination does not itself request quota, write quota cache,
or change connection state. Recovery buttons only open an existing Dashboard
section; they do not execute a login or introduce a separate retry request. The
post-reset task uses the existing quota refresh path: each consumed target
gets one Reset-triggered attempt, without rearming that target. The generic
current transient-failure budget described above may also follow that attempt.

Version `0.2.1` keeps a consumed Reset watermark only in memory, including
across clock changes; no Reset history is written to disk. If a fresh successful
snapshot confirms that a pinned quota bucket/window is absent, the existing
menu-bar preference becomes Auto. Loading cache or receiving a refresh error
does not change that preference. This applies to returned 5-hour/Weekly windows
without deriving access from plan names or model-retirement dates.

Launch at Login status and localized failure feedback use the existing system
service. Tests inject a fake service and never modify real Login Items. Numeric
input clamping, window fitting, longer menu labels, and localized executable
picker text add no data collection, persistent field, or permission.

## Optional local notifications

Version `0.2.2` adds local macOS notifications, disabled by default.
Explicitly enabling the feature requests system notification authorization.
Default warning thresholds are 20% and 10% remaining, and each can be adjusted
or disabled. The default bucket is monitored, with optional extra buckets and
optional recovery alerts.

The app evaluates fresh successful snapshots. Its baseline and per-window-cycle
deduplication state are memory-only and are discarded when the app exits;
cached snapshots and failed requests are not new alert observations. Messages
contain the bucket's display name, quota window, and percentage, without email,
account IDs, credentials, raw RPC, or executable paths.

Delivery uses the local macOS notification service. Notification Center may
retain delivered messages under the user's system settings, so memory-only
app policy state does not mean delivered notifications leave no local record.
This is a local operating-system service and permission, not a Codex94 remote
telemetry channel or project-operated server.

## Manual release checks (0.3.0)

Only **About → Check for updates** initiates an update check. It sends an
unauthenticated HTTPS request to the fixed public endpoint
[`api.github.com/repos/DEFY-AN94/codex94/releases/latest`](https://api.github.com/repos/DEFY-AN94/codex94/releases/latest).
There is no startup check, background polling, automatic app download,
installation, or update-triggered relaunch.

The check does not read cookies, Keychain items, GitHub credentials, or Codex
authentication data. No account identity, quota values, token statistics,
conversation content, or system profile is sent. As with any HTTPS request,
GitHub can receive ordinary network metadata such as the client's IP address
and request headers; this is not a zero-network feature.

The returned version and release notes are kept in memory only. Codex94 does
not save update results to its quota cache or preferences. Release notes are
displayed as plain text. A separate user action opens only the validated
repository Release page in the system browser. The browser then manages its
own requests, cookies, history, and any download the user chooses.

The checker adds no update framework, signing key, installation helper, or
third-party runtime dependency. See [docs/updating.md](docs/updating.md) for the
user flow and future automatic-installation conditions.

## Distribution and CI artifacts

Version `0.2.0` adds packaging and stable-path compatibility, not a new runtime
data flow. The Universal DMG contains only `Codex94.app` and an
`Applications -> /Applications` shortcut. The published checksum identifies the
DMG; GitHub artifact attestation records repository/workflow/commit provenance.
Neither file contains or grants access to Codex login state.

DMG staging, short-lived CI candidates, and the two-file Release upload
allowlist exclude source checkout metadata, credentials, account identity, real
quota, preferences, cache, Application Support, logs, test screenshots,
diagnostics, and private filesystem paths. Automated tests and retained UI
artifacts continue to use isolated synthetic data.

Downloading a Release in a browser and macOS recording quarantine or presenting
Gatekeeper/Privacy & Security UI are operating-system distribution behaviors.
Codex94 does not read browser data, change quarantine, or automate Open Anyway.
The explicit GitHub check is a separate runtime network path, not
an effect of DMG installation. Installing at `/Applications/Codex94.app` or
`~/Applications/Codex94.app` does not duplicate the cache schema: both locations
use the same bundle identifier and local data, which is why users should not run
both copies at once.

Quota and statistics logging includes only operation stage, duration, byte
count, executable source category, and normalized error category. Raw RPC payloads, email,
credentials, full executable paths, Reset timestamps, quota-bucket identifiers,
and account data are not logged. The reset trigger name itself is non-sensitive.

## User-initiated clipboard access

When the user selects **Copy redacted diagnostics**, Codex94 normalizes the
detected executable path and version, then writes the structured diagnostic text
to the macOS system clipboard. When the user selects **Copy version** in About,
it writes the exact displayed version and build. These text writes and the
`3.1.0` chart-image copy happen only after a user action. Codex94 does not read
or upload clipboard contents or diagnostics,
and users should review copied diagnostics before sharing them. Selecting the
project link similarly opens the exact repository URL through the system.
The release-check request is separate and does not upload clipboard
contents or diagnostics.

## Permissions

Codex94 does not request browser, Documents, Keychain, Accessibility, contacts,
camera, microphone, or location access. Standard file dialogs appear only when
the user explicitly chooses a Codex executable or an export destination
(CSV or PNG). The floating panel and image export add
no system permission or entitlement.
Version `0.1.9` added no system
permission or entitlement; versions `0.2.0` and `0.2.1` likewise add none.
Version `0.2.2` adds only the explicit, optional local-notification
permission described above. Its global shortcut does not require Accessibility
access, and opening the popover through that shortcut uses the existing refresh
path.

See [SECURITY.md](SECURITY.md) for the executable trust boundary and security
reporting process. Removing either App copy does not automatically remove local
data; the separate uninstall commands in [README.md](README.md) let users remove
the installed locations, cache, and preferences they choose.
