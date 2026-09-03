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

Version `0.1.9` may start the same quota read once for the earliest future Reset
across displayable windows, strictly at `resetsAt + 5` seconds or later. This
uses the existing Codex subprocess and single-flight refresh path; it does not
add a direct network interface, request a token, or enable account data when
**Quota only** is selected.

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

Version `0.1.8` introduced two UI preference keys; `0.1.9` reuses both keys and
their migration without adding another preference:

- `menuBarLayout.v1` stores the selected layout. In `0.1.9`, the same running
  status item applies it immediately. It remains separate from the existing
  menu-bar quota selection and its legacy migration.
- `statusAccentOverrides.v1` stores up to four independent, opaque sRGB color
  overrides as normalized six-digit uppercase `RRGGBB` values. Invalid values fall back
  for the affected role. **Restore Default Colors** clears only these overrides,
  not quota selection, layout, theme, language, paths, or window settings.

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
Codex94 does not read browser data, change quarantine, automate Open Anyway, or
gain a browser, network, analytics, update, or telemetry interface from the DMG
workflow. Installing at `/Applications/Codex94.app` or
`~/Applications/Codex94.app` does not duplicate the cache schema: both locations
use the same bundle identifier and local data, which is why users should not run
both copies at once.

Unified Logging receives only operation stage, duration, byte count, executable
source category, and normalized error category. Raw RPC payloads, email,
credentials, full executable paths, Reset timestamps, quota-bucket identifiers,
and account data are not logged. The reset trigger name itself is non-sensitive.

## User-initiated clipboard access

When the user selects **Copy redacted diagnostics**, Codex94 normalizes the
detected executable path and version, then writes the structured diagnostic text
to the macOS system clipboard. When the user selects **Copy version** in About,
it writes the exact displayed version and build. Both writes happen only after a
user action. Codex94 does not read or upload clipboard contents or diagnostics,
and users should review copied diagnostics before sharing them. Selecting the
project link similarly opens the exact repository URL through the system; there
is no updater or project-operated network client.

## Permissions

Codex94 does not request browser, Documents, Keychain, Accessibility, contacts,
camera, microphone, or location access. A standard file picker appears only when
the user explicitly chooses a Codex executable. Version `0.1.9` added no system
permission or entitlement, and version `0.2.0` likewise adds none.

See [SECURITY.md](SECURITY.md) for the executable trust boundary and security
reporting process. Removing either App copy does not automatically remove local
data; the separate uninstall commands in [README.md](README.md) let users remove
the installed locations, cache, and preferences they choose.
