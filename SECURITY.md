# Security

## Boundary

Codex94 launches the user's existing Codex executable with the fixed command
`codex -s read-only -a never app-server --stdio`, then requests quota data over
local stdio JSON-RPC. The sandbox remains read-only and the noninteractive child
cannot request an approval. Codex itself owns authentication. Codex94 does not
implement OAuth or a usage HTTP client and does not directly inspect
authentication stores, browser state, session logs, or local usage databases.

The app is intentionally not App Sandboxed because the child Codex process must
access its own existing login state. Hardened Runtime is enabled for installed
artifacts. The child receives only `HOME`, an absolute-entry-only `PATH`,
`TMPDIR`, and locale values. RPC responses and version output are bounded, all
requests have deadlines, and child processes are terminated after use.

Codex94 validates that an executable produces a bounded, single-line
`codex-cli` version response. This checks compatibility; it is not a code-signing
or publisher-identity guarantee. Users must trust the installed or manually
selected Codex executable. Codex may make network requests using its existing
login, but Codex94 never receives that credential.

## Distribution trust boundary

Since version `0.2.0`, Codex94 offers a Universal 2 DMG for technical users alongside the
existing source-install path. The outer DMG is completely unsigned, has no
Apple Developer ID signature, and is not notarized or stapled. The App inside
is ad-hoc signed with Hardened Runtime only; its two architecture slices are
checked for integrity, runtime, no Team ID, and no entitlement keys. This does
not establish publisher identity or Apple trust, and macOS may block the first
launch.

Verify `Codex94-0.2.2-SHA256SUMS.txt` before opening the DMG. The optional
GitHub command
`gh attestation verify Codex94-0.2.2-macos-universal-unnotarized.dmg -R DEFY-AN94/codex94`
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

## Supported versions

The supported published stable version is [`v0.2.2 (13)`](https://github.com/DEFY-AN94/codex94/releases/tag/v0.2.2).
Feature branches and `main` may contain development work that has not passed
release acceptance. Current stable-version links identify the published release.

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
