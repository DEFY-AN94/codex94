# Privacy

Codex94 is a macOS utility. It has no analytics, advertising, telemetry upload,
crash-reporting SDK, system profiling, or Codex94-operated server. The published
stable version is [`v3.0.1 (15)`](https://github.com/DEFY-AN94/codex94/releases/tag/v3.0.1),
released on 2026-09-21 (Australia/Melbourne). It includes the user-triggered
public GitHub release check described below, without automatic installation.

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
credentials or raw RPC. Exporting is the only statistics persistence feature.
Dates retain the service's calendar-day labels; the app does not assume its
undocumented reporting timezone or treat omitted days as zero usage.
The 7-day and 30-day views end at the latest returned date, not the current
local day. Filtering dates and inspecting the chart do not make another request.
`tokenUsageChartStyle.v1` stores only the selected bar/line presentation in
UserDefaults. Changing chart style reuses the loaded response and makes no
request or statistics-cache write.
Summary scope and complete history coverage are unspecified; the app does not
infer model/project, input/output, cost, hourly, or thread-level statistics.

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
post-reset task is a new trigger for the existing quota refresh path: each
consumed target gets at most one attempt and no Reset-specific immediate retry.

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
it writes the exact displayed version and build. Both writes happen only after a
user action. Codex94 does not read or upload clipboard contents or diagnostics,
and users should review copied diagnostics before sharing them. Selecting the
project link similarly opens the exact repository URL through the system.
The release-check request is separate and does not upload clipboard
contents or diagnostics.

## Permissions

Codex94 does not request browser, Documents, Keychain, Accessibility, contacts,
camera, microphone, or location access. Standard file dialogs appear only when
the user explicitly chooses a Codex executable or a CSV export destination.
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
