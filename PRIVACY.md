# Privacy

Codex94 is a local macOS utility. It has no analytics, advertising, telemetry
upload, crash-reporting SDK, update checker, or Codex94-operated server.

## Data access

Codex94 starts a locally installed Codex executable and sends two documented-by-
behavior JSON-RPC requests over the child process's standard input/output:

- `account/rateLimits/read` for quota windows
- `account/read` with `refreshToken: false` only when **Quota + account** is
  selected

The Codex child process may contact OpenAI services using the login it already
owns. Codex94 does not receive, read, export, or persist that login, its cookies,
or its access and refresh tokens. Codex94 does not implement an OAuth flow or
make direct quota HTTP requests.

When account information is enabled, the returned email address is held only in
memory and displayed only in Dashboard. Switching to **Quota only** removes it
from the in-memory snapshot.

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

Version `0.1.8` adds two UI preference keys:

- `menuBarLayout.v1` stores the layout used at the next app launch. It is
  separate from the existing menu-bar quota selection and its legacy migration.
- `statusAccentOverrides.v1` stores up to four independent, opaque sRGB color
  overrides as normalized six-digit uppercase `RRGGBB` values. Invalid values fall back
  for the affected role. **Restore Default Colors** clears only these overrides,
  not quota selection, layout, theme, language, paths, or window settings.

Codex94 also keeps the selected Dashboard section only in memory; the
existing macOS window-frame autosave behavior is unchanged. Absolute Reset text
is derived from the existing quota reset timestamp and current display locale
and time zone. It adds no cache fields or identity data. Local accessibility
labels may include the visible quota and Reset information, but do not add
account identity, opaque bucket identifiers, or executable paths.

Changing layout/colors, rendering Reset text, or opening a recovery destination
does not request quota, write quota cache, or change connection state. Recovery
buttons only open an existing Dashboard section; they do not execute a login or
introduce a separate retry request. Existing refresh triggers are unchanged.

Unified Logging receives only operation stage, duration, byte count, executable
source category, and normalized error category. Raw RPC payloads, email,
credentials, and full executable paths are not logged.

## User-initiated clipboard access

When the user selects **Copy redacted diagnostics**, Codex94 normalizes the
detected executable path and version, then writes the structured diagnostic text
to the macOS system clipboard. This happens only after a user action. Codex94
does not upload the clipboard contents or diagnostics, and users should review
the copied text before sharing it.

## Permissions

Codex94 does not request browser, Documents, Keychain, Accessibility, contacts,
camera, microphone, or location access. A standard file picker appears only when
the user explicitly chooses a Codex executable.

See [SECURITY.md](SECURITY.md) for the executable trust boundary and security
reporting process. The uninstall commands in [README.md](README.md) remove the
app's stored data and preferences.
