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
or its access and refresh tokens.

When account information is enabled, the returned email address is held only in
memory and displayed only in Dashboard. Switching to **Quota only** removes it
from the in-memory snapshot.

## Data stored locally

`~/Library/Application Support/Codex94/quota-snapshot.json` stores quota window
types, percentages, reset times, plan type, and fetch time. It excludes email,
account ID, tokens, RPC payloads, and executable paths. Its mode is `0600`, and
the containing directory is owner-only.

macOS `UserDefaults` stores UI preferences, refresh frequency, the selected
account-information mode, and an optional Codex executable path chosen by the
user. macOS may also store the Dashboard window frame and launch-at-login state.

Unified Logging receives only operation stage, duration, byte count, executable
source category, and normalized error category. Raw RPC payloads, email,
credentials, and full executable paths are not logged.

## Permissions

Codex94 does not request browser, Documents, Keychain, Accessibility, contacts,
camera, microphone, or location access. A standard file picker appears only when
the user explicitly chooses a Codex executable.

See [SECURITY.md](SECURITY.md) for the executable trust boundary and security
reporting process. The uninstall commands in [README.md](README.md) remove the
app's stored data and preferences.
