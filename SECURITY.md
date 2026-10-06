# Security

## Boundary

Codex94 launches the user's existing Codex executable with the fixed command
`codex -s read-only -a never app-server --stdio`, then requests quota data through
`account/rateLimits/read` over local stdio JSON-RPC. Version `0.3.0 (14)`
also requests service-reported aggregate Token usage through the official
`account/usage/read` method on first entry to the statistics page or an explicit
statistics refresh. This request is independent of quota polling. The sandbox
remains read-only and the noninteractive child cannot request an approval.
Codex itself owns authentication. Codex94 does not implement OAuth or a direct
HTTP client for quota or Token usage and does not directly inspect authentication
stores, browser state, session logs, or local usage databases.

Version 4.0.1 adds optional Claude subscription monitoring through an explicitly
installed local statusline bridge by default, with a separate optional official
Claude Code `/usage` reader. Authentication remains inside Claude Code. There is no
direct Claude quota HTTP/OAuth implementation or credential-store access.
The CLI reader has a separate, default-off opt-in with a quota-consumption
warning. Enabling Claude monitoring does not opt into CLI sessions. While the
CLI reader is off, automatic and ordinary manual refreshes read only local files
(the explicit one-time CLI action is separate): in
4.0.1 the statusline cache alone, and from 4.1.0 also Claude
Code's own usage cache in `.claude.json` (read-only, `cachedUsageUtilization`
key only). Disabling the CLI reader cancels and retires an active reader.
In 4.0.1, source modes are isolated: a CLI failure does not adopt an
account-unverified statusline report (4.1.0 replaces this
isolation with tiered selection). Passive monitoring pins its selected report
stream and asks for explicit adoption when a different session reports; a
session fingerprint never proves account identity. No OAuth token access or
refresh is implemented.
The CLI probe has an owned working directory, disabled tools/hooks/MCP and
remote-control startup, bounded output and a deadline. Only a recognized
built-in usage action is submitted; unexpected login/onboarding screens are
reported rather than interpreted as a prompt.
The child requests disabled automatic updates and prompt/session-history
writes through documented process-local flags. Older Claude Code releases may
not implement the history flag. Version-output validation establishes expected
CLI compatibility, not publisher identity; installed executables remain part
of the user's trust boundary.

Statusline JSON is untrusted input. The bridge bounds parsing and stores a
small allowlist of quota windows, source/timestamps and opaque producer hashes.
It preserves an existing user-supplied statusline command and its stdout;
that command retains its original local execution authority. Installation
previews the change, preserves unrelated settings, backs up only the previous
statusline key and checks for conflicting changes before restoration. The
manifest and cache use private local files; neither is included in releases.
See [PRIVACY.md](PRIVACY.md) for the new configuration and cache inventory.

Version `4.1.0 (24)` adds one read-only file source and no
new network path. `ClaudeLocalUsageCacheReader` opens Claude Code's global
state file `.claude.json`, in the home directory or in `CLAUDE_CONFIG_DIR` when
Codex94's own environment sets it, read-only with `O_NOFOLLOW`. It refuses
symlinks, hard-linked files, foreign owners, non-regular files and files over
16 MiB, parses the bounded JSON, interprets only the `cachedUsageUtilization`
key and discards every other key, including account email, organization,
project paths and MCP settings. It never writes, and normally re-parses when the
file's size/mtime/inode stamp changes. Version 4.1.1 additionally retries
transient reads and revalidates future timestamps. The cache is untrusted input:
percentages must be finite values from 0 to 100, timestamps must be strict
ISO-8601 with a zone, model-limit rows are capped at sixteen and malformed rows
are skipped, and a malformed or partially written cache keeps the previous
report. The `accountUuid` value is compared in memory only to detect a
different login; it is never persisted or logged.

Sources are tiered, not merged: the local usage cache is primary, the
status-line connection (statusline bridge) is the backup when its report is
strictly newer or the cache is absent or unreadable, and the optional CLI
`/usage` read is the last option. The CLI reader stays default-off with its
quota-consumption warning; it is no longer mutually exclusive with the passive
sources, and a **Read once with the CLI** button runs the official CLI exactly
once under the same warning. Exactly one report is shown at a time; tiers of
the same account share one notification baseline, which only a different login,
a different status-line producer or a rejected CLI login resets.
`script/security_check.sh` additionally forbids `.credentials.json`, the
Keychain item name `Claude Code-credentials`, `SecItemAdd`, `SecItemUpdate`,
`SecItemDelete`, `SecKeychain` and the `api/oauth/usage` endpoint string in
production sources, and requires that the literal `claude.json` appears only in
`Services/ClaudeLocalUsageCacheReader.swift`. `AppUpdateClient.swift` remains
the only network client. No HTTP/OAuth client, Keychain, cookie or token
reading was added: Anthropic's credential-use rules reserve OAuth tokens for
Claude Code and native Anthropic apps, so Codex94 reads only files that the
official client leaves on the Mac. The paused OAuth work is draft PR #44 and is
not part of 4.1.0.

The app is intentionally not App Sandboxed because the child Codex process must
access its own existing login state. Hardened Runtime is enabled for installed
artifacts. The Codex child receives only `HOME`, an absolute-entry-only `PATH`,
`TMPDIR`, and locale values. RPC responses and version output are bounded, all
requests have deadlines, and child processes are terminated after use.
The Claude child also receives the current OS username for its own login lookup,
a fixed terminal/locale, and the process-local update/history controls above.
The app does not forward arbitrary authentication variables from its environment.

Codex94 validates that an executable produces a bounded, single-line
`codex-cli` version response. This checks compatibility; it is not a code-signing
or publisher-identity guarantee. Users must trust the installed or manually
selected Codex executable. Codex may make network requests using its existing
login, but Codex94 never receives that credential.

Version `0.3.0` adds one separate direct network client for the About
page's user-initiated **Check for updates** action. It requests only
`https://api.github.com/repos/DEFY-AN94/codex94/releases/latest`, using a bounded,
timed HTTPS request and an ephemeral session with cookie, credential, and cache
storage disabled. Redirects and HTTP authentication challenges are rejected;
normal system TLS certificate validation remains enabled. No Codex credentials,
quota, Token usage, prompts, or system profile are sent. GitHub can receive
ordinary connection metadata such as the IP address and request headers.

Release metadata is untrusted input: the checker validates stable-release
status, the version, and this repository's HTTPS Release-page URL. Notes are
plain text. The system browser owns subsequent navigation and downloads after
the user opens that page. The check does not verify an installation package,
download or install an App, relaunch it, or run in the background. See
[docs/updating.md](docs/updating.md) for the user flow and maintenance boundary.

## Distribution trust boundary

Since version `0.2.0`, Codex94 offers a Universal 2 DMG for technical users alongside the
existing source-install path. The outer DMG is completely unsigned, has no
Apple Developer ID signature, and is not notarized or stapled. The App inside
is ad-hoc signed with Hardened Runtime only; its two architecture slices are
checked for integrity, runtime, no Team ID, and no entitlement keys. This does
not establish publisher identity or Apple trust, and macOS may block the first
launch.

Verify `Codex94-4.1.4-SHA256SUMS.txt` before opening the DMG. The optional
GitHub command
`gh attestation verify Codex94-4.1.4-macos-universal-unnotarized.dmg -R DEFY-AN94/codex94`
can prove repository/workflow/commit provenance for the exact DMG. A matching
checksum or attestation is not notarization, malware review, a security audit,
or Gatekeeper approval. If the exact release is trusted, use only Apple's
[Privacy & Security → Open Anyway](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/26/mac/26)
flow. Do not disable Gatekeeper or remove quarantine attributes.

Codex94 has no automatic updater. Published DMG/checksum assets follow a manual
non-replacement policy. SHA-256, GitHub Release API digests, and attestation can
detect drift, but GitHub Immutable Releases is not enabled and the platform
does not prevent an authorized maintainer from replacing an asset.

## Stored data

Cache v2 contains only quota-bucket identifiers and optional names, plan type,
window type and duration, used percentage, reset timestamp, and fetch timestamp.
It is stored under `~/Library/Application Support/Codex94` with owner-only
permissions. It excludes account identifiers, email, credentials, executable
paths, and raw RPC data; legacy snapshots are migrated into the same minimized
schema. Account email and the popover's currently browsed model are memory-only.
`UserDefaults` stores UI choices, including the preferred menu-bar quota
selection, refresh frequency, account-information mode, and an optional
manually selected Codex path. See [PRIVACY.md](PRIVACY.md) for the complete
inventory.

Version `0.1.8` introduced only local UI preferences for menu-bar layout
(`menuBarLayout.v1`) and four independent opaque sRGB color overrides
(`statusAccentOverrides.v1`, normalized uppercase `RRGGBB`). Version `0.1.9`
reuses those keys and cache schema v2 unchanged. It applies layout changes to
the existing status item immediately, and its default Overview reads the same
snapshot without exposing email, executable paths, or raw bucket identifiers.

The `0.1.9` post-reset task exists only in memory and reuses the existing
Codex-subprocess request and single-flight coordinator. It chooses the earliest
future displayable-window target at `resetsAt + 5` seconds or later, consumes a
target after at most one attempt, and persists no ledger. Logs do not include
Reset timestamps, bucket identifiers, account data, or paths. About version
copying is user-triggered and shares the same bounded clipboard component as
redacted Diagnostics. These changes add no credential access, identity field,
cache field, preference key, direct network interface, background helper,
telemetry, entitlement, or system permission.

Version `0.2.0` does not change that runtime boundary, cache schema, preference
inventory, authentication access, direct-network behavior, entitlement set, or
system permissions. DMG staging and CI upload allowlists contain the packaged
App and release metadata only; they exclude credentials, identity, real quota,
preferences, cache, logs, screenshots, and private filesystem paths.

Version `0.2.1` keeps these boundaries. Extreme numeric inputs are
clamped before remaining-quota arithmetic, and a session-only watermark avoids
repeating consumed Resets after clock rollback. A fresh successful snapshot
may change an unavailable pinned quota selection to Auto using the existing
preference; cached data and failed requests cannot trigger that change.
Launch at Login tests use a fake service, not real registration. The source
installer requires running copies to be quit, verifies a unique staged App,
and retains recovery files when rollback cannot safely restore the old App.

Version `0.3.0` keeps Token usage summaries and daily date/token pairs in
memory. It ignores thread-level response fields and does not add statistics to
cache v2. Each successful read replaces the previous snapshot rather than
accumulating usage. Missing values and dates remain unknown, not zero. A
user-requested CSV export writes only the reported daily dates and exact token
counts in the selected range to the chosen destination. That exported file
persists independently of the app's memory-only statistics.

`tokenUsageChartStyle.v1` stores only the selected `bar` or `line` presentation
in `UserDefaults`. Chart style and date-range changes are local presentation
operations, not additional usage requests. Manual update-check results and
release notes also stay in memory; the checker adds no stored authentication,
update feed, signing key, automatic installation, or third-party runtime
dependency. These additions do not change the distribution signing policy.

### 3.1.0 additions

The floating panel projects the existing quota snapshot and uses the existing
manual refresh action. Its only new persisted fields are pin state and screen
position (`floatingWindowPinned.v1`, `floatingWindowPosition.v1`); visibility
and expansion are not persisted. It adds no polling, credit consume request,
authentication access, permission, or entitlement.

Custom Token dates and comparison metrics are local projections of the loaded
snapshot. Missing days and zero baselines do not produce invented growth
percentages. PNG export and chart-image copying are explicit user actions;
images contain only the chart/range, fetch time, coverage, and stale-data
notice, without identity or raw RPC. PNG files and the system clipboard are
user-directed outputs, not a statistics cache or history store. Tests use
synthetic data and isolated named pasteboards, never the general pasteboard.
The existing subprocess, fixed GitHub endpoint, and distribution-signing
boundaries remain unchanged.

## Supported versions

Version `4.1.0 (24)` adds the read-only Claude Code usage-cache
source, source tiering, the one-time CLI read and per-model weekly buckets
described above. It adds no quota API, credential access, preference key,
cache file, entitlement or installer step. The App target and the UI test bundle build locally on Xcode 27.0, and the
hosted unit suite passed there: 544 tests executed, 1 existing hosted-focus
skip, 0 failures. The metadata, installer and security-scanner script
self-tests also passed locally, and `script/release_check.sh` passed
locally on Xcode 27.0 for `4.1.0 (24)`: it verified the Universal App and an
unsigned DMG candidate (SHA-256
`9be68277c0f6db6d820da06e3da0b9f8bb29dba7bb99a999d0eeefe9facb9fd0`; a local
artifact, not the release asset). On CI (Xcode 16.4) the `test` job and the
display, floating, recovery and usage UI smokes passed for the first PR head;
the providers smoke failed four times on test-side causes that were
corrected afterwards (an exact-text assertion predating the cached-data
prefix, a fixture whose scoped Fable limit was the tightest window and
relabelled the native item, a new screenshot name missing from the artifact
allowlist, then a fixture-policy check that still required the CLI opt-in
to stay on while the smoke itself toggles it); the release commit passed
every check on final main, and the published release is recorded in
[docs/RELEASING.md](docs/RELEASING.md).

The unpublished `4.0.2 (23)` candidate, carried into 4.1.0, repairs a
notification callback actor boundary and changes presentation. It adds no
quota API, credential access or automatic installer. The fixed official Claude
Usage link is opened only by an
explicit user action in the system browser; Codex94 does not read the resulting
page or browser session. Claude Code `/usage` remains independently default-off.

Version `4.0.1 (22)` uses passive Claude reports by default with explicit
report-stream adoption and a separate default-off CLI reader. The retained
`v4.0.0` tag identifies an unpublished candidate, not a supported stable release.

The supported published stable version is [`v4.1.4 (28)`](https://github.com/DEFY-AN94/codex94/releases/tag/v4.1.4),
released on 2026-10-07 (Australia/Melbourne).
Feature branches and `main` may contain development work that has not passed
release acceptance. Current stable-version links identify the published release.
Version `3.1.4` adjusts bounded quota deadlines and permits three extra
read-only attempts after transient failures. Failure-stage logs contain fixed
categories and timings, not raw payloads. The next-attempt display uses existing
in-memory schedules and adds no permission, endpoint or persistent account data.

Version `3.1.3` prioritizes quota over optional identity, adds a bounded
transient-error retry budget, and renders menu-bar status through native
non-template images. Authentication failures remain errors, and unavailable
identity never inherits another account's details or Token snapshot. Rendering
and freshness tooltips add no account output, network endpoint or permission.
The authentication, stored-data and distribution trust boundaries above remain.
The bundled-CLI discovery compatibility introduced in `3.1.2` is retained.

Version `0.1.8 (9)` passed the full GitHub test/release job, synthetic Display
and click-functional Recovery UI jobs, Actions/Swift CodeQL, and separate
synthetic A/B GUI smokes. For `0.1.9 (10)`, PR #11 remains the historical record
for exact-head test, Display/Recovery UI, Actions/Python/Swift CodeQL, and final
App acceptance. The synthetic Overview image embedded in the README has been
visually and privacy reviewed. Contributor validation guidance is documented in
[CONTRIBUTING.md](CONTRIBUTING.md); static source checks alone are not runtime
security or release evidence. Every release candidate needs its own checks,
candidate App acceptance before Ready, and final CI artifact/tag/Release
verification and maintainer acceptance before publication.

## Reporting

Use GitHub's **Report a vulnerability** link when it is available in the
repository Security tab. If private vulnerability reporting is temporarily
unavailable, do not open a public Issue or publish sensitive details; contact
the maintainer only through an existing private channel.

Include only the redacted diagnostics generated by the app, and review them
before sharing. Never include tokens, cookies, account identifiers, raw RPC
payloads, private paths, or other sensitive information. See
[GitHub's private reporting documentation](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/report-privately).
