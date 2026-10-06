# Release workflow: source + technical-user DMG

The published stable version is [`v4.1.3 (27)`](https://github.com/DEFY-AN94/codex94/releases/tag/v4.1.3),
released on 2026-10-07 (Australia/Melbourne). Later docs-only commits do not
move its tag or regenerate its assets. Keep public download and source-clone
instructions on the published release until a later publication is confirmed.

Each release uses one verified source commit, one annotated tag, and exactly
two manual assets: a Universal 2 DMG and its one-line SHA-256 checksum. The outer
DMG is unsigned and unnotarized. The inner App is ad-hoc signed with Hardened
Runtime, no Team ID, and no entitlements. GitHub attestation proves provenance
of the DMG; it is not Apple signing, notarization, malware review, or Gatekeeper
approval. The checksum is the second asset, not a separately attested subject.

## 1. Authorization and acceptance

Each gate needs separate explicit maintainer authorization:

1. Commit, push the development branch, and create a Draft PR.
2. Mark that Draft Ready, after the maintainer accepts the candidate App.
3. Merge the reviewed PR.
4. Create and narrowly push the annotated tag at the verified release commit.
5. Create a Draft GitHub Release using that existing tag and upload two assets.
6. Install/replace the final CI App and perform maintainer-led Open Anyway
   acceptance where needed.
7. Publish that Draft as the public Latest Release, not a prerelease.

An earlier authorization does not authorize a later gate. Candidate App
acceptance before Ready and final CI DMG/install acceptance are separate.
Launching an explicitly approved candidate does not authorize replacing an
installed App or operating real Login Items/System Settings. Keep pending
acceptance visible in the PR. Never mark Ready merely because CI is green.

## 2. Local candidate and shared metadata

The latest menu-display release is **`4.1.3 (27)`**, published on
**2026-10-07** (Australia/Melbourne) from PR #53. Stable downloads point to
`v4.1.3`; the verified package and installation record appears below. The `4.0.2 (23)` candidate
was merged through PR #43 and carried into 4.1.0 without a separate release.
Never move or reuse existing tags, including the retained `v4.0.0` candidate.

The next candidate is **4.1.4 (28)**, dated **2026-10-07**
(Australia/Melbourne). Verify current/history/unknown native inputs, historical
weekly-first Auto and manual zero/missing choices, time-only tooltip updates,
Dashboard-only quota pickers, the separate report-age line and Claude-only
five-hour countdown suppression. Verify one-time menu clicks against a fake
CLI, and slow shutdown/fetch completion in both orders with no overlapping
clients or automatic one-shot retry. All routine tests use synthetic data.
The maintainer authorized at most two real CLI acceptance attempts for this
update, with failed starts/timeouts included; prefer one and stop after success.
Keep automatic CLI off, record attempts before launch, and never retry in a loop.
A production-client harness is separate evidence from the Store/UI fake tests;
report its process-cleanup and quota-consumption limitations accurately. OAuth
remains paused. Stable links stay on 4.1.3 until publication is verified.

The **4.1.3 (27)** release checks validate shared meter geometry for current Codex/Claude
and historical Claude rows in both languages/themes, including 0/100, fractional
percentages and long names. History must keep its original time and remain
separate from current snapshots, Auto, notifications and native rings. Reuse
existing synthetic rendering and Providers scenarios; do not invoke real
`/usage` or write test data into the user's cache. Record the local candidate,
brief background observation, PR checks and final-main CI assets separately.
The verified 4.1.3 source, package and installation are recorded below.

The **4.1.2 (26)** release checks use synthetic data to verify that fully expired
accepted reports retain values and source time in historical UI, while current snapshots/rings/Auto/notifications
remain empty or unchanged. Check source switching, account invalidation, disable,
late CLI results, pending confirmations, unchanged rereads, clock changes and cold
local-cache recovery. No-record and malformed/future-data states remain unknown.
Review history cards/terminal rows in both languages and themes, native tooltip
and floating expanded detail, and enforce zero extra requests from presentation.
Record 4.1.2 local, PR, final-main, package and installed-App evidence separately.
Do not launch real `/usage` or seed the user's actual cache for these checks.

For 4.1.1, use synthetic reports and disposable files to verify:

- Observed account change, cache absence/unreadability/decoded-invalid state,
  stop/restart and late CLI completion cannot restore a previous context.
  A transient torn write preserves the last good report. An already-open report
  confirmation cannot approve a replacement; validate its captured confirmation ID. Reconfirmed statusline
  data is a report stream, not authenticated account proof.
- The first accepted report establishes a notification baseline. A fallback to
  an older observation never causes a fresh recovery alert. Later new reports
  still trigger the configured thresholds.
- Source eligibility is checked before usable-window filtering and newest-report
  selection. Keep exactly one report and its timestamp, including on fallback.
- FIFO, directory, symlink, hardlink, ownership and size rejection remain bounded.
  A file changed during reading is retried by the existing poll.
- Future-timestamp recovery works without a file change; unchanged normal polls
  avoid parsing. Expiry and freshness still advance without duplicate published state.
- Local-only refresh does not invoke CLI; explicit one-time and scheduled CLI
  paths remain distinct. Use fakes for both, not live `/usage`.
- Auto's caption matches the existing resolver, including model/weekly-only,
  unavailable and manual-selection states in both languages and themes.

Run focused regressions, the full local release gate, all five UI smokes,
Actions/Python/Swift CodeQL and final-main artifact attestation. Record local
candidate installation and approximately ten minutes of observation separately.
The previous release's 544-test result does not validate 4.1.1. OAuth remains paused.

The following 4.1.0 checks remain applicable to the local-cache source.
For 4.1.0, verify the following against its own source and artifacts. Use
synthetic state files under `CLAUDE_CONFIG_DIR` and the synthetic Claude
executable; do not read the maintainer's real `~/.claude.json`, launch the real
CLI or send a prompt to populate test data.

- Local cache states: absent (no file), valid, unreadable (symlink, foreign
  owner, non-regular or hard-linked file, over 16 MiB) and invalid (no usable
  `cachedUsageUtilization`). Check the Claude card's empty states and the
  Services local-cache state for each, that a torn rewrite keeps the last good
  report while the state reads invalid, that a decoded file without usage data
  drops it, and that the diagnostics export carries `claudeLocalCache` with
  exactly one of absent/valid/unreadable/invalid while Claude monitoring is on
  (none once it is off) and no path or account identifier. Confirm the reader
  never writes the file.
- Expired windows leave the current snapshot, picker and menu-bar percentage;
  expiry never implies 100% remaining. From 4.1.2, an accepted fully expired
  report may be shown separately as historical values with its original time
  and an explicit current-quota-unknown label.
- 60-minute freshness: a cache report is current for 60 minutes after
  `fetchedAtMs`, then shows the amber cached marker and the **Claude Code
  fetched** time while keeping its numbers. Statusline keeps 10 minutes; CLI
  keeps max(10 min, refresh interval + 60 s). Re-reading an unchanged file
  must not renew report age.
- Source switching: with cache and statusline reports present, the cache is
  shown unless the statusline report's observation time is strictly newer;
  equal times keep the cache. The same rule applies to a CLI report. Values
  are never averaged or merged. An observed identity change resets the notification
  baseline; `accountUuid` stays in memory. In 4.1.1, context loss also clears old
  backups, and older fallback reports cannot generate new alerts.
- CLI option off keeps passive data: turning `claude.cliUsageEnabled.v1` off
  discards only CLI data and leaves the cache or statusline report shown with
  no CLI launch. Turning it on runs the reader on the existing interval and its
  result participates in selection. The key keeps its meaning and default.
- Read once with the CLI: the Dashboard → Services action runs the official
  `/usage` exactly once with the option off, shows the quota-consumption
  warning, retires the one-shot client afterwards and does not enable the
  option. The cache then picks up Claude Code's refreshed file on the next poll.
- Per-model weekly limits: `weekly_scoped` entries (for example "Fable") appear
  under **Per-model weekly limits**, in the menu-bar quota picker and in
  automatic most-constrained selection. Malformed rows are skipped without
  invalidating the shared windows; older cached reports without the field decode.
- Security scanner: `script/security_check.sh` rejects `.credentials.json`,
  `Claude Code-credentials`, `SecItemAdd`/`SecItemUpdate`/`SecItemDelete`,
  `SecKeychain` and `api/oauth/usage` in production sources, and rejects
  `claude.json` outside `Services/ClaudeLocalUsageCacheReader.swift`;
  `script/tests/test_security_check.py` covers both rules.
- No new network client: `AppUpdateClient.swift` remains the only network
  client. The diff adds no HTTP/OAuth client, Keychain, cookie or token reading,
  preference key, cache file, entitlement, endpoint or installer step. Codex
  behavior, existing Codex preferences and cache v2 are unchanged.

The Providers UI smoke fixture seeds a synthetic `.claude.json` through
`CLAUDE_CONFIG_DIR` and is intended to show that turning the CLI option off
displays the cache source without launching the CLI; it passed on the release
commit (see the 4.1.0 record below).

Local evidence so far: The App target and the UI test bundle build locally on Xcode 27.0, and the
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
to stay on while the smoke itself toggles it), so its rerun, candidate
acceptance, tag, the CI DMG and publication followed; the 4.1.0 acceptance
record below is the authoritative result.

The `4.0.2 (23)` checks below are retained because that candidate was carried
forward into 4.1.0 without publication; verify them on the 4.1.0 revision:

- Invoke authorization, permission and delivery completions from a background
  fake notification adapter. They must not trigger MainActor isolation checks;
  disabled defaults and late-result cancellation must remain intact. Do not
  request real notification permission as part of automated tests.
- Inspect large dual-service Dashboard cards, compact terminal-style popover
  rows and the smaller read-only reset count in both languages and themes.
  Retain unknown/zero/reset-expired and cached-data distinctions.
- Check all three service-display choices: `single`, new `compactBoth` with
  one native item and two independent rings, and unchanged `both` with two
  native items. Existing saved `both` must retain its behavior. Verify either
  service alone, both, and neither; single-service items hide redundant names.
  Display changes must not fetch quota, redeem resets or rewrite quota cache.
- Verify the passive empty state names Claude Code statusline as its source and
  explains that App/web chats do not supply it. Verify the SwiftUI Link's fixed
  official Usage destination and that rendering causes no additional request
  or browser opening; do not activate the live link during CI.
  There is no new quota API or automatic App/web reader. `/usage` stays
  separately default-off; do not resume real CLI probing for these checks.

Record actual local tests, synthetic UI results, changed-behavior acceptance,
final-main checks and package identities separately. No 4.0.2 or 4.1.0
validation result is implied by the historical records below.

Version 4.0.1 follows the revised conditional data-source plan. The OAuth
authorization prerequisite is not met, so it uses passive statusline reports
by default. Live `/usage` probing
remains suspended. The CLI reader stays an independent default-off option with
a quota-consumption warning, never an automatic fallback. Validate source
isolation and report age with synthetic data; do not launch Claude or send a
prompt merely to populate test data. Earlier green CI does not validate these
new source boundaries or resolve the historical CLI consumption/timeout concern.
Version 4.1.0 replaces that mode isolation with tiered selection, as described
above; the 4.0.1 records do not validate the tiered rules.

Version `4.0.1 (22)`, released on 2026-10-03 (Australia/Melbourne), carries
forward dual-provider monitoring with passive Claude
reports by default and a separate, explicitly enabled CLI option.
The maintainer chose to retain `v4.0.0` unchanged and removed its Draft Release;
do not move or reuse that tag. The 4.0.0 candidate's test and native-observation
records do not establish validation of these source boundaries. Final checks,
artifacts and installation need separate records. Its release records remain historical; current stable links point to 4.1.3.

During the earlier 4.0 release work, the maintainer approved a ten-minute
live-observation scope.
The earlier 4.0.0 candidate observation lasted 626 seconds: two Codex and one
Claude background refreshes, plus one popover read per service, all succeeded
with zero failures. It included interaction and is neither an unattended run
nor evidence for the new fix. Record the new candidate's outcome separately.

Start from a clean, freshly fetched baseline. Review changes since the published
tag and any branch/tag/Release name conflicts. Preserve unknown worktree
changes and existing tags; do not stash/reset/clean or force-push as preparation.
Keep candidate changelog notes under Unreleased without inventing a date.
Historical release entries and the existing synthetic screenshot provenance
remain unchanged. Planning and Goal files stay outside the Git repository.

Version `3.1.4 (20)`, dated **2026-09-28** (Australia/Melbourne), separates
quota 10/20-second budgets from Token usage 5/15 and optional-account 2 seconds.
Retain exact four-attempt checks for the 5/20/60 retry schedule, a no-request
observation beyond the longest backoff, and closed-popover automatic recovery.
Check the next scheduled time across retry/background/reset changes and unknown
clock estimates, with no extra image render, timer or RPC. Record local
background-refresh observation separately from synthetic CI.

Version `3.1.3 (19)`, dated **2026-09-28** (Australia/Melbourne), prioritizes
quota before optional identity, uses at most two transient-failure retries,
and freshness-gates popover opens. Retain quota-first/identity-isolation,
retry-budget/cancellation, and no-read-on-fresh-reopen tests. Native image
checks cover sRGB colors, transparency, dimensions, the real status-button
image and independent blue/amber/error state colors. Keep manual Spaces
acceptance tied to its exact candidate and Mac rather than inferring it from
static image or AX-geometry checks.

Version `3.1.2 (18)`, dated **2026-09-27** (Australia/Melbourne), restores
discovery of the newer nested bundled Codex CLI layout while retaining legacy
fallbacks and explicit manual selection. Retain synthetic new-layout,
fallback-ordering and manual-path regression checks; record live RPC acceptance
separately from automated tests.

Version `3.1.0 (16)` adds the floating strip, custom Token ranges, and image
exports. Retain the following regression checks for those features:

- The floating strip's 680 × 90 logical-point target, screen fitting, dragging,
  pinning, hiding/reopening, expansion, and hover/keyboard-focus refresh control.
  Showing or changing the strip must not start polling, redeem reset credits,
  or rewrite quota cache. Explicit refresh uses the existing manual path;
  the global shortcut still toggles the same popover. Check both themes and
  languages. Record native macOS 14+ behavior across Spaces/fullscreen apps
  only after testing it; configured NSPanel flags alone are not acceptance.
- `floatingWindowPinned.v1` and `floatingWindowPosition.v1` contain only pin
  state and position. Expansion, visibility, and custom dates stay memory-only.
- Custom inclusive source-date ranges, reported average/selected-range peak,
  coverage, and prior equal-length interval totals/coverage. Test gaps, explicit
  zero, ranges beyond returned data, overflow, and zero/incomplete baselines;
  percentage change must remain unavailable where it is not defined. Preserve
  summary cards, bar/line selection, and no-fetch/no-cache-write behavior.
- CSV retention and user-triggered PNG save/copy. Inspect actual synthetic
  images in English/Chinese, light/dark, and bar/line styles for chart, date
  range, fetch time, coverage, and an unclipped stale-data notice. Check PNG
  format/dimensions, current selection, failure versus cancellation, and absence
  of identity. Copy tests use named pasteboards, never the general pasteboard.

For `3.1.1 (17)`, additionally verify 480-point weekly-only/cold
layouts have no 5-hour accessibility node, reported dual layouts remain 680,
and live quota-group changes reuse the same panel and preserve the top-left
where available screen space permits. Keep ordinary typography in the
480-point layout. Check explicit zero, cached/failed responses, no extra
requests or cache writes, hidden updates and post-shutdown notifications.

Local validation for `3.1.1 (17)` recorded 345 tests executed, 1 skipped, and
0 failures. The hosted focus skip is not a pass. Record external UI, CodeQL,
final-main packaging and installed-artifact acceptance from the actual final
revision and assets; this local count does not establish those outcomes.

Validation for `3.1.0` includes a fourth **Floating** UI scenario and expanded
Token usage coverage. Its local unit suite recorded 340 tests executed, 1 skipped,
and 0 failures; the skipped hosted key-window focus check is not a pass.
Keep local, external UI, CodeQL, native interaction, and final-package evidence
separate and tied to the revision actually tested.

Version `3.0.1 (15)` was published on 2026-09-21 (Australia/Melbourne).
Its historical tag and DMG remain bound to
`ab6d48e5011eba2c10e9f31f51e4ef1f3c166307`. Current download and clone
instructions point to `v4.1.3`. The 3.0.1 maintenance release isolates quota
request contexts, shares strict
service-value parsing, reuses chart preparation/formatting, retires old Token
clients outside the main actor, and validates development-script arguments
before side effects. It does not introduce a broad timer rewrite, new data
source, cache schema, signing policy, or automatic installer. See
[component ownership and reuse rules](ARCHITECTURE.md).

For the `3.0.1` maintenance changes, regressions must inspect the interval between
an obsolete response and its queued replacement, not only the final snapshot:
the old success/error must not change cache, pinned preferences, alert baselines,
or the new Token context. Also retain malformed-value/date tests, source-date
gap and chart/CSV equivalence checks, and bounded cleanup/shutdown tests using
synthetic clients. An invalid build-script mode must exit before process or
filesystem side effects. Report the actual validation evidence separately.

Version `0.2.2 (13)` was published on 2026-09-20. It introduced a fourth
dual-window layout with independent bucket selection, mouse left/right clicks
toggling the same popover, a global shortcut unset by default, opt-in local
quota notifications, and a read-only Manual quota resets card. These quota
features remain available in `0.3.0`.

Version `0.3.0 (14)` was published on 2026-09-21 (Australia/Melbourne). It adds
service-reported Token statistics, bar/line daily charts and CSV export, plus
manual checks of the latest public stable GitHub Release. Downloading and
installing an App remain user-managed. The historical `v0.3.0` tag and DMG
remain bound to `21f2b60097b742a036af0ab9eac0535c7361c77d`; later maintenance
or documentation releases do not move that tag or replace those asset bytes.

Regression checks for the `0.2.2` features should cover the three legacy layouts and
their saved selection, the independent dual-window preference, and both mouse
buttons using the same popover toggle and the current freshness-gated refresh path. Check
hotkey registration/failure through a fake adapter, requiring Control or Option
with optional Command and Shift. Notification tests use a fake system service:
disabled defaults,
explicit-enable authorization, adjustment/disabling of the 20% and 10% thresholds,
default and optional extra buckets, optional recovery, baseline suppression,
and per-cycle memory-only deduplication. Keep real notification permission and
shortcut interaction in maintainer-led acceptance rather than automated tests.
Verify messages exclude email and other identity, while documentation discloses
system Notification Center retention. Verify reset-credit zero versus null,
cold versus cached states, unchanged cache v2, and no consume request or credit
details on disk. The new preference keys are `dualWindowBucketSelection.v1`,
`globalHotKey.v1`, and `notifications.v1`; history, updater, and multi-account
features were not included in `0.2.2`.

Regression checks for the `0.3.0 (14)` features also cover the following:

- Token statistics use only the official `account/usage/read` request, on first
  page entry or an explicit statistics refresh. Keep requests and error states
  independent of quota polling and the menu-bar connection state. Verify
  complete, partial, unavailable, and unsupported responses with synthetic
  data, and ensure repeated reads replace rather than accumulate usage.
- Check 7-day, 30-day, and all-returned ranges against the latest returned
  source date. Verify both bar and line charts, remembered
  `tokenUsageChartStyle.v1` selection, centered selection guides, and line breaks
  across missing dates. Missing fields/dates must remain distinct from explicit
  zero. Range and style changes must not fetch usage or rewrite the quota cache.
  Do not infer a reporting timezone, complete history, cost, or model/project
  breakdown from the aggregate response.
- Verify CSV export contains only the displayed reported dates and exact token
  counts, preserves missing dates without filling them, and retains explicit
  zero values. Cancelling export must not report a write failure. Statistics
  otherwise remain in memory and cache v2 stays unchanged. Published screenshots
  and test fixtures must remain synthetic.
- Check the manual About update action with injected responses for newer,
  equal, and older stable versions, invalid metadata/URLs, offline/timeouts,
  rate limits, and oversized responses. The only metadata endpoint is
  `https://api.github.com/repos/DEFY-AN94/codex94/releases/latest`; retain its
  fixed HTTPS boundary, disabled cookie/credential/cache storage, rejected
  redirects, and absence of account or usage data in the request. Release notes
  remain plain text, and only a validated repository Release page may open in
  the system browser. Automated tests must not browse, download, install, or
  poll for real updates. Record maintainer-led verification of the About action
  and Release-page navigation separately; this feature does not automate App
  replacement or relaunch. See [docs/updating.md](updating.md).

Read version/build from the App target using the shared standard-library
helper. It requires one App target and matching explicit Debug/Release values:

```bash
metadata="$(/usr/bin/python3 -I script/release_metadata.py)"
release_version="$(jq -er '.version' <<< "$metadata")"
release_build="$(jq -er '.build' <<< "$metadata")"
release_tag="v$release_version"
dmg_name="Codex94-$release_version-macos-universal-unnotarized.dmg"
checksum_name="Codex94-$release_version-SHA256SUMS.txt"
distribution="$PWD/.build/Distribution/$release_version"
```

Do not use shell `eval` or a second VERSION file. Local checks read worktree
metadata; CI uses `--revision "$GITHUB_SHA"` and requires HEAD to equal that
SHA. UI fixture preparation validates the helper's regular tracked blob before
loading it, retaining Python `-I` and the explicit build-input allowlist.

Run the gate with full Xcode and the existing contributor tools:

```bash
brew install ripgrep jq
./script/release_check.sh
git diff --check
git status --short
```

The gate runs isolated metadata/installer tests, the static security check,
hosted XCTest, and one Universal Release build. The packager owns the complete
App verifier and checks both the supplied App and its mounted DMG copy:
metadata, exact arm64/x86_64 slices, signature integrity, runtime, empty
entitlements, and absence of private builder paths. The gate compares built
version/build to the project metadata before invoking packaging.

`package_dmg.sh` keeps its narrow `create APP OUTPUT_ROOT` and
`verify DMG CHECKSUM VERSION BUILD` interfaces. It never builds, installs,
launches/stops Apps, reads credentials, or changes quarantine. Output is exactly
the DMG and checksum, with no screenshots or auxiliary manifest:

```bash
./script/package_dmg.sh verify \
  "$distribution/$dmg_name" "$distribution/$checksum_name" \
  "$release_version" "$release_build"
```

Preserve the readonly UDZO mount, strict two-entry payload, literal
`Applications -> /Applications` link, unsigned outer image, checksum grammar,
no-overwrite lock, atomic output-directory publication, and exact mount cleanup.
`spctl` rejection is expected for this distribution and is diagnostic only.

Tests use synthetic data and disposable directories. The source installer
requires running Codex94 copies to be quit and uses lock/staging/signature
checks plus rollback; two renames are not crash-atomic. Never run its production
entry point as an automated test or delete an unrecognized transaction, backup,
or lock. Do not wait for real Reset/sleep, alter system time, use real quota, or
repeat extensive manual UI checks for this patch.

If implementation changes invalidate a local candidate, record its hash and
archive it recoverably under the approved
`.build/DistributionArchive/<UTC timestamp>-<12-character HEAD>/<version>/`
layout before rebuilding. Do not overwrite a destination or damage the formal
candidate during negative tests.

## 3. Draft PR, candidate App, and merge

After gate 1, record baseline main, PR head, the tested merge SHA/tree,
version/build, checks, risks, rollback, artifact hashes, and both acceptance
states. GitHub's default PR artifact identifies the tested merge SHA, not the
PR head; record them separately.

Wait for CI, every synthetic UI smoke required by the candidate, and
Actions/Python/Swift CodeQL on the actual tested revision. The `4.1.3` release gate
includes five UI scenarios: Display, Recovery, Token usage, Floating, and
Providers. Providers uses synthetic data, including a synthetic local usage
cache under `CLAUDE_CONFIG_DIR`; passing it does not verify real Claude account
quota, ordinary App/web collection or a restored live CLI reader.
Skipped, cancelled, unavailable, pending, or failed is not passed. Review the
synthetic images themselves for UI and privacy. Retain the existing screenshots
as historical captures unless separately replacing them with reviewed evidence.

Prepare the candidate App from the exact PR head and give its version/build,
commit and hash to the maintainer for a brief acceptance of changed behavior.
Any App source/resource/project-setting/Info.plist change invalidates this
acceptance. Pure documentation edits need relevant checks and CI, not repeated
App interaction. Only then may gate 2 mark Ready. Gate 3 separately permits
merge.

Before tagging, the maintainer confirms the actual release date. Replace the
candidate's Unreleased heading through a reviewed change and the normal
Draft/Ready/merge gates; do not permanently tag an Unreleased changelog. If
the release day changes before tagging, correct the date and repeat the checks
on the revised commit. Public stable links still point to the published version.

After the date change is merged, fetch and freeze the release commit as
`RELEASE_SHA`.
Wait for all checks on that commit, its two-file DMG artifact, and main-only
attestation. Resolve release-blocking source/docs defects through the normal
Draft/Ready/merge flow before tagging; do not repair a tagged binary in place.

## 4. Final CI bytes, tag, and Draft Release

Download the artifact named `codex94-dmg-<RELEASE_SHA>` from its verified
final-main workflow run after the date change into a new review directory.
Record the run ID,
release SHA/tree, both file hashes, and attestation URL. Reverify those exact
files with `package_dmg.sh verify`. Public assets must use these CI bytes,
not a locally rebuilt substitute. If the seven-day artifact expires, rerun the
workflow on the same release commit, reverify the new bytes and obtain fresh
asset acceptance.

From a checkout at the frozen release commit, re-read committed metadata:

```bash
test "$(git rev-parse HEAD)" = "$RELEASE_SHA"
metadata="$(/usr/bin/python3 -I script/release_metadata.py --revision "$RELEASE_SHA")"
release_version="$(jq -er '.version' <<< "$metadata")"
release_build="$(jq -er '.build' <<< "$metadata")"
release_tag="v$release_version"
```

Set `dmg_path`, `checksum_path`, and `release_body_file` to the exact reviewed
local files. The body is local review material, not a third release asset.
Verify provenance and, only after gate 4, publish the tag:

```bash
gh attestation verify "$dmg_path" -R DEFY-AN94/codex94
test "$(git rev-parse origin/main)" = "$RELEASE_SHA"
test -z "$(git tag --list "$release_tag")"
test -z "$(git ls-remote --tags origin "refs/tags/$release_tag" "refs/tags/$release_tag^{}")"
git tag -a "$release_tag" "$RELEASE_SHA" -m "Codex94 $release_tag"
test "$(git cat-file -t "$release_tag")" = tag
test "$(git rev-parse "${release_tag}^{}")" = "$RELEASE_SHA"
git push origin "refs/tags/$release_tag:refs/tags/$release_tag"
```

Recheck the remote tag object and peeled commit, and a shallow clone's commit
and version/build. Never move an existing tag or use `git push --tags`.
Verify the Release name is unused. After gate 5:

```bash
gh release create "$release_tag" "$dmg_path" "$checksum_path" \
  --title "Codex94 $release_tag" --notes-file "$release_body_file" \
  --draft --verify-tag --latest=false --prerelease=false
```

Do not use `--clobber`. Download both Draft assets again, verify the DMG,
checksum and provenance, and compare each asset's GitHub API
`sha256:<64 lowercase hexadecimal characters>` digest with its local hash.
Missing or mismatched digests stop publication. GitHub's automatic source
ZIP/TAR files are additional source downloads, not manual assets and not
covered by the DMG checksum.

## 5. Release notes and final asset acceptance

Use a concise bilingual body with actual version/build, verified DMG SHA,
release changes, installation instructions, and this safety notice. Replace
all placeholders before upload. Use the actual release date confirmed and
reviewed before tagging; do not invent a date during candidate implementation.

```markdown
# Codex94 VERSION (BUILD)

Release date / 发布日期: CONFIRMED_RELEASE_DATE

CHANGE_SUMMARY_EN
CHANGE_SUMMARY_ZH

Assets / 资产:
- Codex94-VERSION-macos-universal-unnotarized.dmg
- Codex94-VERSION-SHA256SUMS.txt
- macOS 14+, Apple Silicon arm64 + Intel x86_64
- DMG SHA-256: VERIFIED_DMG_SHA256

The DMG is unsigned and unnotarized. The App inside is ad-hoc signed with
Hardened Runtime only; macOS may block its first launch. GitHub attestation
proves provenance, not Apple trust or a malware/security review.
DMG 未签名且未公证；内部 App 只有 Hardened Runtime ad-hoc 签名，macOS 可能
阻止首次启动。GitHub attestation 证明构建来源，不代表 Apple 信任或安全审查。

Verify both downloaded assets before opening:
请先同时下载 DMG 和 checksum，再验证：
    shasum -a 256 -c Codex94-VERSION-SHA256SUMS.txt
    gh attestation verify Codex94-VERSION-macos-universal-unnotarized.dmg -R DEFY-AN94/codex94

Quit every Codex94 copy, drag Codex94.app onto Applications, and open that
installed copy. If blocked and you trust the verified release, follow Apple's
[Privacy & Security → Open Anyway](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/26/mac/26)
flow. Do not remove quarantine or disable Gatekeeper.
退出所有 Codex94 副本，把 Codex94.app 拖入 Applications，再打开安装后的副本。
如被阻止且你信任已验证版本，请使用上面的 Apple 官方“仍要打开”流程，
不要删除 quarantine 或关闭 Gatekeeper。

Source installation remains available from annotated vVERSION. Do not run
copies from /Applications and ~/Applications together; they share local data.
Codex94 has no automatic updater.
仍可从 annotated vVERSION 源码安装。不要同时运行两个 Applications 位置的副本，
它们共用本地数据；Codex94 没有自动更新功能。
```

Gate 6 permits final-asset installation/replacement separately from candidate
acceptance. Download from the Draft Release in a browser, verify hashes and
attestation, inspect quarantine without changing it, and inspect the mounted
two-item payload. The maintainer may then replace the intended App and open the
exact installed path; preserve any other installed copy.

Only the maintainer operates Privacy & Security/Open Anyway or real Login
Items. Automation must not enter passwords, alter quarantine, disable Gatekeeper,
or change system settings. Confirm version/build, basic launch, and the accepted
installation paths. If quarantine is absent or an existing account approval
allows direct launch, record first-launch Gatekeeper evidence as uncertain;
the maintainer decides whether to accept that limitation.

## 6. Publish and document the actual release

After the maintainer accepts the exact final assets, gate 7 permits publishing
the same Draft:

```bash
gh release edit "$release_tag" --draft=false --latest --prerelease=false --verify-tag
```

Redownload the public assets and verify names, exactly two manual files, both
hashes/API digests, checksum, mounted structure, signature and architecture,
attestation, annotated tag, source archives, and Latest/non-prerelease state.
The tag must still peel to the frozen `RELEASE_SHA`.

Once publication is confirmed, prepare the documentation follow-up: verify the
changelog date already matches publication and update README English/Chinese
stable status, download
and clone instructions, SECURITY supported version, and any current-version
references. Remove candidate wording only for the version that was actually
published. Recheck PR/bug templates and release notes; retain history and
screenshot provenance. That docs-only PR still needs its own commit/push,
Ready, and merge authorizations and passing checks; publication does not
automatically authorize those writes.

Such a later docs-only commit can advance main beyond `RELEASE_SHA`. Record
that distinction: the release tag/DMG remain bound to the verified release
commit, and the documentation follow-up does not move the tag or regenerate
assets. Published assets follow a manual no-replacement policy; Immutable
Releases is not enabled. If App or DMG bytes need repair, publish a new patch
version through these gates.


### 3.1.0 final acceptance — 2026-09-23

- [PR #26](https://github.com/DEFY-AN94/codex94/pull/26) was marked Ready after
  its checks passed and then merged. The release commit is
  `e580729dc81fd8db295c965119cdbcee87b7a157`; annotated tag `v3.1.0` has object
  `7250e3a2a272a6f5b973d0844211d508ba04727e` and peels to that commit.
- The exact final-main [CI run](https://github.com/DEFY-AN94/codex94/actions/runs/35736572657)
  passed the test/package gate, all four external UI scenarios, and DMG
  attestation. The hosted suite executed **340 tests: 1 skipped, 0 failures**.
  The separate [Actions/Python/Swift CodeQL run](https://github.com/DEFY-AN94/codex94/actions/runs/35736572351)
  passed. The skipped key-window focus test is not counted as a pass; mandatory
  panel lifecycle/no-fetch coverage ran separately.
- Floating evidence verifies both entry points, the same owned window after
  hide/reopen, drag/position, pin/expand, cold and cached failures, and manual
  refresh. Token evidence verifies custom-range entry, interval metrics,
  comparison, PNG/CSV native save-panel cancellation, and image actions being
  disabled during a live retry. Direct date-field editing, native cross-app
  focus, Spaces and fullscreen remain outside that automated acceptance.
  Recovery retains its instrumented click-only acceptance and pending keyboard,
  AXPress and hosted-tooltip limitations.
- The published DMG and checksum were re-downloaded anonymously; their names,
  sizes and GitHub digests matched the verified CI files. Public ZIP and TAR
  archives matched all **144** frozen Git blobs and executable modes. The
  production anonymous update client discovered `v3.1.0` and its exact DMG URL.
- DMG SHA-256:
  `7a6f3dec5cc8e2a06697fea79992a2951fb3908a828fe14c977e64cf93347464`.
  SHA256SUMS-file SHA-256:
  `2dff0c90e28959bfebdf8683a4ca7785ac9eb5d5b342e94fbbba6e06e68dee21`.
  Build provenance was verified against this repository's CI workflow,
  `refs/heads/main`, the exact source digest, and GitHub-hosted runners.
- `/Applications/Codex94.app` was backed up, replaced, and verified against the
  complete CI-App file/mode manifest, both-architecture signature and installed
  process path. The installed main-binary SHA-256 is
  `75df87d444fa33afefbde83d6c0f1a2c8cbc97dd3232dae5392b759f39c2714a`.
  The old 3.0.1 App was retained for rollback. The local desktop inspection
  connection was unavailable, so no new local visual/manual acceptance is
  claimed. Quarantine and Gatekeeper were unchanged; fresh-account first-launch
  Gatekeeper acceptance remains unverified. The unsigned/unnotarized DMG and
  ad-hoc-signed App retain the distribution limitations above.

The maintainer authorized implementation, installation and the PR-to-release
workflow. This record distinguishes delegated automated checks from a new
human manual test. Later documentation commits update stable links and this
record without moving the release tag or replacing either asset.


### 3.1.1 final acceptance — 2026-09-23

- [PR #28](https://github.com/DEFY-AN94/codex94/pull/28) passed its checks, was
  marked Ready and merged. The release is frozen at
  `370e3800de1f54b94efe2e4d4761d671a2710fd4`; annotated tag `v3.1.1` has object
  `55e1041e14baae6c376a379e1a955927bfcc8d53` and peels to that commit.
- The exact final-main [CI](https://github.com/DEFY-AN94/codex94/actions/runs/35749196911)
  passed its test/package gate, four external UI scenarios and DMG attestation.
  The suite recorded **345 executed, 1 skipped, 0 failures**. The separate
  [Actions/Python/Swift CodeQL](https://github.com/DEFY-AN94/codex94/actions/runs/35749196810)
  run passed for the same source. The optional hosted key-window test remains
  a skip; mandatory panel lifecycle and adaptive-layout coverage passed.
- New main-sourced floating evidence verifies **480 → 680 → 480**, absence of
  the unreported 5-hour accessibility node, normal single-column typography,
  the same window and position, and no additional request or quota-cache write
  from quota selection/layout changes. Six actual synthetic screenshots were
  reviewed. Pin, drag, expand/hide/reopen and cached failure behavior also passed.
  Existing native focus/Spaces/fullscreen and Recovery instrumented-click
  limitations remain; older releases' screenshots are not substituted for this
  run's adaptive-layout evidence.
- Both public assets were downloaded anonymously and matched CI bytes and API
  digests. Public source ZIP/TAR inventories matched all **144** frozen Git
  blobs and executable modes. The production anonymous update client returned
  `v3.1.1` and the exact DMG URL.
- DMG SHA-256:
  `364285015fa44a652b8370c8d4399660bd51e2a5c41e7f671b82aa4e3ca1b14a`.
  SHA256SUMS-file SHA-256:
  `0ace064685e9ccfb1fa81b14578143d90708b351aa7ea472d67ee7fdd269cfa0`.
  Attestation was checked against this repository's CI workflow, main ref,
  exact source digest and GitHub-hosted runner provenance.
- The installed `/Applications/Codex94.app` matched the complete CI file/mode
  manifest and both-architecture signature, and launched from that exact path.
  Its main-binary SHA-256 is
  `6165a756f72e22469b02b1ec6b335775cc60b14e5c9a63f0bdcbbb1f9cce9364`.
  The previous 3.1.0 App was retained for rollback. The desktop inspection
  connection remained unavailable; no additional local visual/manual test is
  claimed. Quarantine and Gatekeeper were unchanged, and fresh-account
  first-launch acceptance remains unverified. Distribution signing limitations
  are unchanged. Documentation follow-ups do not move this tag or replace assets.

### 3.1.2 compatibility release — 2026-09-27

[PR #31](https://github.com/DEFY-AN94/codex94/pull/31) fixes
[issue #30](https://github.com/DEFY-AN94/codex94/issues/30). The release source is
`8df7f920316b05f7065053d86203f66e6cf6e846`. Local validation recorded **353 tests
executed, 1 skipped, 0 failures**; the skip is not a pass. Final
[main CI](https://github.com/DEFY-AN94/codex94/actions/runs/36274627725):
passed, including packaging, all four external UI scenarios and DMG attestation; [CodeQL](https://github.com/DEFY-AN94/codex94/actions/runs/36274626869):
passed for Actions, Python and Swift.

- Publication/Latest verification: public Latest, non-prerelease, published on 2026-09-27 (Australia/Melbourne).
- Annotated tag object: `0bb89d58004e9c601f98e94fc37dbea625ff662e`; frozen-source binding: `v3.1.2` peels to the release commit above.
- DMG SHA-256: `1a450a19b21f436089b0a04ed161a0f15f68ba5e12f088a178be0006faec80bd`; checksum-file SHA-256: `7fda028de93ddcbaaba309e6e4830544e3119963ffd15282913bdac8d1f80638`.
- Public assets/attestation/source archives: both public assets matched the final CI bytes
  and GitHub API digests; attestation matched the exact main source. ZIP and TAR
  each matched all 144 tracked files. The production update client found `v3.1.2`.
- Installed App binary SHA-256: `a5ac3b39cdf2c88fc3a53c4eabddd963166fee814e2b00f7320e32ec8ee2352e`.
  Installation, retained 3.1.1 backup, and final live-quota check: the exact
  `/Applications/Codex94.app` matched the complete file/mode manifest, signature
  and all attributes, and ran as the only instance. The previous 3.1.1 App was
  retained for rollback. With no manual CLI override, the cache fetch time
  advanced after launch and no refresh errors were observed.

Quarantine was unchanged. The local desktop inspection connector was unavailable,
so no new local visual/manual UI acceptance is claimed. Previously documented
signing, first-launch Gatekeeper and untested native-interaction limits remain.


### 3.1.3 refresh and menu-bar release — 2026-09-28

[PR #34](https://github.com/DEFY-AN94/codex94/pull/34) fixes
[issue #33](https://github.com/DEFY-AN94/codex94/issues/33). The full suite
recorded **381 tests executed, 1 skipped, 0 failures**, including 11 native
menu-bar renderer tests. The hosted key-window focus skip is not a pass.

PR head `956aa1744dd4d71f03c0d714a4935d5dba952181` was tested as merge commit
`f476d066c857cf7c71b980ab2d00c81c9c677918`, tree
`e2410a6e6533a94bc7fb3329340f0f45cbe7a7e5`.
[PR CI 36325976370](https://github.com/DEFY-AN94/codex94/actions/runs/36325976370)
passed the full test/package job and Display, Recovery, Token usage and
Floating UI jobs.
[PR CodeQL 36325973592](https://github.com/DEFY-AN94/codex94/actions/runs/36325973592)
passed Actions, Python and Swift. Main-only attestation was skipped for that
PR run and is not counted as a passed PR check.

The maintainer confirmed that the reported menu-bar color flash during Spaces
switching was resolved on the tested Mac with the exact reviewed PR CI
candidate: `3.1.3 (19)`, App main-binary SHA-256
`1fd8dcbcdcb27c250ab6939f3f0eb761a603c68622fc286f2431caa72a17d26a`, copied
from the PR DMG with SHA-256
`949b19ec364b7d418fc844ce83eaac2aca5e920928137276b340b2719ee5e0fd`.
That candidate's files/modes matched its DMG, its signature was checked and
quarantine was not modified. These are candidate identifiers, not the final
published asset hashes. This manual acceptance is limited to that Mac and
candidate; it is not a claim about every macOS version, fullscreen configuration,
floating-panel Spaces behavior, keyboard focus, or fresh-account Gatekeeper.

- Frozen release source: `1dedf6230753f52510004c0355ec91ad626fbc23`.
- Final-main CI and DMG-attestation evidence: [CI 36345607838](https://github.com/DEFY-AN94/codex94/actions/runs/36345607838) passed the full suite (381 executed, 1 skipped, 0 failures), all four synthetic UI jobs, packaging and DMG attestation.
- Final-main Actions/Python/Swift CodeQL evidence: [CodeQL 36345607726](https://github.com/DEFY-AN94/codex94/actions/runs/36345607726) passed Actions, Python and Swift.
- Publication/Latest verification: anonymous GitHub readback confirmed [v3.1.3](https://github.com/DEFY-AN94/codex94/releases/tag/v3.1.3) as public, non-draft, non-prerelease and Latest (Release ID `397794268`, published `2026-09-27T20:11:27Z`, or 2026-09-28 in Australia/Melbourne).
- Annotated tag object and `v3.1.3` source binding: tag object `f1f841f8a50e6e1f7e0178cdfac40cd8955ca8d8` peels to the frozen release commit above; its tree is `f435dda8ccfa6e72a05ceca1561815ac3223fd8a`.
- Final DMG SHA-256: `15ee4d64be474c765ccb3d3480a712c1f581c11dd952bc085e5984fd0faf824c`; checksum-file SHA-256: `d839fa7693998e42d2c8c1936fafc24a20fd585957f906d42270626b98c97ee2`.
- Public assets: both downloads matched the final-main CI bytes and GitHub API
  digests. Package verification confirmed Universal 2, ad-hoc Hardened Runtime,
  empty entitlements, no Team ID, and an unsigned, unnotarized outer DMG.
- Strict DMG attestation verification passed for this repository's `main`, the
  frozen source/signing SHA, and `.github/workflows/ci.yml`; the certificate
  identified CI run `36345607838`, attempt 1, on a GitHub-hosted runner.
- Public ZIP and TAR archives each matched all 146 tracked files at the frozen
  commit, without extraction. The production update client used no cookies or
  credentials, recognized 3.1.3 as newer than 3.1.2, and returned the correct
  release and DMG URLs.
- Installed App binary SHA-256: `1fd8dcbcdcb27c250ab6939f3f0eb761a603c68622fc286f2431caa72a17d26a`.
- Final installation, retained rollback copy and live-refresh acceptance: the final App was installed and launched; its full file manifest, signature and extracted extended attributes were verified after launch. Launch refresh and the first scheduled background refresh succeeded. The complete 3.1.2 backup and original were retained; quarantine, signatures and user preferences were not changed. The installed main binary matches the PR candidate accepted for the reported Spaces color issue; no new animation capture or broader native acceptance is claimed.

The synthetic UI evidence confirms freshness-gated reopening, bounded retry
exhaustion, existing layout/selection behavior, and the amber cached indicator
versus blue active refresh. Recovery remains click-functional with pending
keyboard/AXPress/tooltip acceptance. Token UI checks open and cancel PNG/CSV
save panels; they do not perform real Save/Copy or validate direct custom-date
field editing. There is no CI capture of a real Spaces animation in these
artifacts. Final package and installation evidence above must remain distinct
from the maintainer's PR-candidate color acceptance. Documentation follow-ups
do not move the release tag or replace asset bytes.


### 3.1.4 background recovery release — 2026-09-28

[Fix PR](https://github.com/DEFY-AN94/codex94/pull/37) addresses
[issue #36](https://github.com/DEFY-AN94/codex94/issues/36), now closed.

- Full test result: 396 tests executed, 1 existing hosted-focus skip, 0 failures.
- Frozen release source: `0aae38d7eff9c910ce25778c60ccf429b67cd22a`.
- Final-main CI, four synthetic UI jobs and DMG attestation: [CI
  36380134556](https://github.com/DEFY-AN94/codex94/actions/runs/36380134556) passed the
  full suite, all four synthetic UI jobs, packaging and DMG attestation.
- Final-main Actions/Python/Swift CodeQL: [CodeQL
  36380133690](https://github.com/DEFY-AN94/codex94/actions/runs/36380133690) passed
  Actions, Python and Swift.
- Annotated `v3.1.4` tag and source/tree binding: tag object
  `6f3e03525fc74a4443e37eec5660abc8677993b3` peels to the frozen commit above, tree
  `02f3cefaa9e2454bb4a44f6c85faa5f49c271a14`.
- Final DMG SHA-256: `24f1b3a5dc5bbbd0cb084e8f242cb5eb817653b059e44cef619c0127940620a5`.
- Checksum-file SHA-256:
  `8686683b54ce34a4e70f66997c81dffc76f2d055a6cd5087ba0e51e268e52ac0`.
- Public Latest, asset digests, strict attestation and ZIP/TAR verification: anonymous
  readback confirmed public, non-prerelease Latest Release `397971188`, published
  `2026-09-28T05:25:29Z`. Both public assets matched final CI bytes and API digests.
  Package verification and strict attestation passed for the exact source/signing SHA,
  `main`, `ci.yml` and GitHub-hosted run `36380134556` attempt 1. Public ZIP and TAR
  each matched all 146 tracked files. The production updater recognized 3.1.4 as newer
  than 3.1.3 with valid release/DMG URLs.
- Local candidate background-refresh observation and exact binary identity: the locally
  built Release candidate, binary SHA-256
  `29bf8026cf99385a4adc7fad32af6383561c27a9f096c365fc163d889c3bd22c`, ran without
  menu/manual refreshes for 50 minutes 23 seconds, with 10 background successes.
  Across launch and those background cycles, four successful quota stages took
  just over five seconds. No real quota
  failure occurred during this observation; it does not establish failure recovery for
  that candidate.
- Installed App binary SHA-256:
  `e19d83ff7d3176aba2d8d556003821d4c1a6ac0d6e3708b0dfe01fd32c0a1b7b`.
- Final installation, retained rollback copy and refresh acceptance: the final CI
  Release App was installed and observed without clicks. Its launch quota read timed out
  after 10.001 seconds; an automatic retry started 5.04 seconds later and succeeded with
  a 722 ms quota stage. The first five-minute background refresh also succeeded. Full
  files/modes, signature and all extracted extended attributes were verified; the
  complete old 3.1.3 backup and original were retained, and quarantine was unchanged.

[PR Display CI](https://github.com/DEFY-AN94/codex94/actions/runs/36378589587)
verified exactly four attempts, 61 seconds without a fifth, and recovery with
the popover closed after at least 31 seconds of simulated service failure,
using production retry delays. This synthetic Debug UI evidence is separate
from both Release binaries and the local observations above. Earlier 3.1.3
Spaces acceptance remains bound to that Mac and candidate; it is not new 3.1.4 native-interaction evidence. Documentation
follow-ups do not move the release tag or replace its assets.

### 4.0.1 passive Claude monitoring release — 2026-10-03

- Version/build: `4.0.1 (22)`. Release source: `841a4e57fff51ddc7813e642cc013c2211a93622`;
  tree `4e1308bf0c59d2852c781bee1066866749b3cabc`. [PR #41](https://github.com/DEFY-AN94/codex94/pull/41)
  was marked Ready and squash-merged after its final-head checks passed.
- Final-main [CI 37120608417](https://github.com/DEFY-AN94/codex94/actions/runs/37120608417)
  passed test/package, five synthetic UI scenarios and main-only attestation.
  **503 tests executed, 1 existing hosted-focus skip, 0 failures**; the skip is
  not counted as a pass. The installed-entry-point regression also passed on CI.
- Final-main [CodeQL 37120608168](https://github.com/DEFY-AN94/codex94/actions/runs/37120608168)
  passed Actions, Python and Swift analysis. The tested PR tree and final main
  tree match. A shallow clone of the annotated release tag reproduced the
  frozen commit/tree and version/build.
- Annotated `v4.0.1` tag object: `021bd52acfb1e1f98a316dd1234dcd83eb3a365a`,
  peeling to the frozen source above. The unpublished `v4.0.0` tag remains
  unchanged (`bff5a990619c3f05faf30c134c9ba8e17043c051`, peeling to
  `53b20227a1689c5200c13f53130e987a8a843b93`); its Draft Release was removed.
- CI artifact `11273218056`, `codex94-dmg-841a4e57fff51ddc7813e642cc013c2211a93622`, had ZIP
  SHA-256 `9d2f9f292f5e49869b2254b95edfa301bcbe6758f3143930131f810ed146d0be`.
  It contained exactly the DMG and checksum file.
- DMG SHA-256: `c60ba6f6ea94a9e488caec1a6fac63e2425cd816ec8adebabef754b231b5c03b`.
- Checksum-file SHA-256: `eb9aa98d4db94d30cc9412368c4a40c2292459fd67043960ad8e2679cfcdce05`.
- [GitHub attestation 52408733](https://github.com/DEFY-AN94/codex94/attestations/52408733) was strictly verified
  against the exact source/signing SHA, this repository, `refs/heads/main`,
  `.github/workflows/ci.yml`, a GitHub-hosted runner, and CI run 37120608417
  attempt 1. The verified statement's subject matches the DMG name/hash.
- [Public v4.0.1 Release](https://github.com/DEFY-AN94/codex94/releases/tag/v4.0.1), ID `402497037`,
  was published as Latest at `2026-10-03T12:13:44Z`. Both Draft and anonymous
  public asset downloads matched the original CI bytes and GitHub API SHA-256
  digests. Anonymous Latest discovery returned this stable, non-draft release.
  Manual asset IDs are `607756378` (DMG) and `607756379` (checksum).
- The installed `/Applications/Codex94.app` executable SHA-256 is
  `a90674b3249795508b25ef5edd20685d3f0d226ac3f09b420cba8efe0f3cdc96`. Its 14 bundle entries plus root mode match the
  extracted final CI App. Original signing was preserved; quarantine was not
  removed or changed. Extraction added only macOS `com.apple.provenance`
  metadata, recorded separately. The installed copy was verified without
  re-signing, and the previous local candidate was retained during replacement.
- Final-package checks confirmed macOS 14+, arm64 and x86_64, an unsigned and
  unnotarized outer DMG, and an ad-hoc Hardened Runtime App with no Team ID or
  added entitlements. This existing installation context did not require a new
  Open Anyway operation; it does not establish notarization or first-launch
  Gatekeeper acceptance on another Mac.
- Codex startup quota reading succeeded. Claude monitoring is enabled locally
  in passive mode and the independent CLI flag remains off. The optional
  statusline connection was installed without changing unrelated Claude
  settings; there was no previous statusline command to replace.
- Two calls to the exact final installed App's bridge entry point used only
  isolated synthetic manifests/settings/caches. Both exited successfully,
  captured the expected two windows, preserved the original `reportedAt` on
  repeated input, advanced only receipt time, and left the GUI process and
  binary unchanged. No fake report was written into the user's actual cache,
  and no Claude process or model request was started for this validation.
- No natural passive account report had arrived at acceptance, so real passive
  quota values are not claimed as verified. Native UI control was unavailable;
  reviewed local renders and fresh-host CI interactions used synthetic data.
  The earlier interaction-inclusive 626-second CLI observation is historical
  and does not validate passive account data.

Direct OAuth remains unimplemented because the proposal's official-authorization
prerequisite was not established. Passive reports have no verified account ID;
report-stream selection is not authentication. The optional CLI reader remains
default-off, with a quota-consumption warning and suspended live probing.
Later documentation commits do not move either tag or replace release assets.

### 4.1.0 local usage cache release — 2026-10-05

- Version/build: `4.1.0 (24)`. Release source: `5931618240b9fc60090f9626f292d1f7bdba20d6`;
  tree `c4636fee119e292902f1d82d15c44d8d03d247c8`. [PR #46](https://github.com/DEFY-AN94/codex94/pull/46)
  (the change; final head `f7b197f`) was marked Ready and squash-merged as
  `d0ff9bd` after its final-head checks passed, and [PR #47](https://github.com/DEFY-AN94/codex94/pull/47)
  dated the changelog and was squash-merged as the release source. The maintainer
  authorized Ready, merge and the remaining gates in chat once CI was green.
- Final-main [CI 37213593738](https://github.com/DEFY-AN94/codex94/actions/runs/37213593738)
  passed test, five synthetic UI scenarios and main-only attestation on Xcode 16.4.
  **544 tests executed, 1 existing hosted-focus skip, 0 failures**; the skip is not
  counted as a pass. The display smoke was cancelled at the 20-minute job timeout on
  attempt 1 after uploading its evidence and passed on attempt 2 (failed-jobs
  rerun); the DMG artifact and attestation come from attempt 1.
- Final-main [CodeQL 37213593623](https://github.com/DEFY-AN94/codex94/actions/runs/37213593623)
  passed. A shallow clone of the annotated release tag reproduced the frozen
  commit/tree and version/build.
- Annotated `v4.1.0` tag object: `394c142673c417d9742fb21adc5490eaba670b5b`,
  peeling to the frozen source above. The first narrow push attempt reported a
  transient failure without creating the remote ref; the retry created it.
- CI artifact `11307836866`, `codex94-dmg-5931618240b9fc60090f9626f292d1f7bdba20d6`,
  had the GitHub API ZIP digest
  `sha256:d7bab2a036b2804d161fe9425731b0336e9a51c50403e593d73adc1359efd9b9`.
  It contained exactly the DMG and checksum file.
- DMG SHA-256: `658e00bf5fc24239cbe4fe2a8e71a08614ff8ceac29a9e15f8eae7f0e2a669fc`.
- Checksum-file SHA-256: `c8ddeee6bb0b24d9352e1d07886ad1a6cb24e064f8d161ca4da011777e1e2c05`.
- [GitHub attestation 52604145](https://github.com/DEFY-AN94/codex94/attestations/52604145)
  was verified against this repository, `refs/heads/main`,
  `.github/workflows/ci.yml`, the source commit above and CI run 37213593738
  attempt 1; the statement's subject matches the DMG name/hash.
  `package_dmg.sh verify` passed on the artifact, on the Draft download and on
  the anonymous public download.
- [Public v4.1.0 Release](https://github.com/DEFY-AN94/codex94/releases/tag/v4.1.0), ID `403105633`,
  was published as Latest at `2026-10-04T16:30:10Z` (2026-10-05 03:30
  Australia/Melbourne). Draft and anonymous public asset downloads matched the
  original CI bytes and the GitHub API SHA-256 digests. Anonymous Latest
  discovery returned this stable, non-draft release. Manual asset IDs are
  `610182702` (DMG) and `610182700` (checksum).
- At the maintainer's instruction, installation followed publication. The
  running `/Applications/Codex94.app` 4.0.2 (23) candidate (executable SHA-256
  `74f58ef7db3265abedb0a141018230c220d5528f836884eabc107db6710f2b27`) was quit
  and moved to the Trash, not deleted, and the App from the verified DMG was
  installed at the same path. The installed executable SHA-256 is
  `f2fc931e94d1e7604a7c1e5d16f2978c79b7b916f29306c693d0c44d12ea07fd`; its 15
  bundle entries, every file hash and the root mode match the DMG payload, and
  the original signing was preserved. The DMG was fetched with the GitHub CLI,
  so no quarantine attribute existed and the copy carries only
  `com.apple.provenance`; first-launch Gatekeeper evidence is therefore
  uncertain. The installed copy launched and stayed running. `~/Applications`
  holds no copy.
- Final-package checks confirmed macOS 14+, arm64 and x86_64, an unsigned and
  unnotarized outer DMG, and an ad-hoc Hardened Runtime App.
- Runtime reading of the maintainer's real Claude usage cache was not inspected
  by automation; the Providers UI smoke verified the cache source with synthetic
  data only.

Direct OAuth remains unimplemented; the paused work stays in draft PR #44.
Later documentation commits do not move the tag or replace release assets.


### 4.1.1 cache maintenance release — 2026-10-05

- Version/build: `4.1.1 (25)`. [PR #49](https://github.com/DEFY-AN94/codex94/pull/49)
  was marked Ready and squash-merged after independent review, local acceptance
  and all required PR checks. The maintainer authorized development, installation,
  Ready, merge and publication in the task goal.
- Release source: `e86cad021bf984f738df379e57cf9174dc45430c`; tree `fdf02e5b8907b4b9d671cc2ae0523385b1ca75ab`.
  PR head `4240ec5b441be113bd7edbd450743dec47774a01` and tested merge
  `e51cd6ffed0cd1700ab3873019f331c2bab792db` have the same tree.
- Local Xcode 27.0 full gate: **565 tests executed, 1 existing hosted-focus skip,
  0 failures**; metadata/installer/security checks, Universal build and package
  verification passed. The skip is not a pass. Initial focused testing passed
  116 tests; the added confirmation-context follow-up passed 62 focused tests.
- PR [CI 37232196265](https://github.com/DEFY-AN94/codex94/actions/runs/37232196265)
  passed its 565-test gate and all five UI scenarios on Xcode 16.4. PR
  [CodeQL 37232194575](https://github.com/DEFY-AN94/codex94/actions/runs/37232194575)
  passed Actions/Python/Swift and aggregate analysis. Main-only attestation was
  intentionally skipped for the PR.
- Final-main [CI 37233582007](https://github.com/DEFY-AN94/codex94/actions/runs/37233582007)
  and [CodeQL 37233582061](https://github.com/DEFY-AN94/codex94/actions/runs/37233582061)
  passed for the frozen release source, including all five UI scenarios and
  DMG attestation.
- Local candidate executable SHA-256: `140a414ac84a6594f4a4b44a9453e67eac1071671e07bad449bb97a15082371b`.
  Local DMG SHA-256: `6ef934133ae6ab370eb050b67bb3d1773c7d0e154455be2444522e9d1c7648fd`; these were local
  validation artifacts, not the public release bytes.
- Local candidate observation ran for 610 seconds in the same App process:
  two successful Codex background refreshes, zero failures, zero Claude CLI
  read starts, and the CLI preference off before and after. Startup confirmed
  a valid Claude local-cache read. No live `/usage` or cloud quota comparison
  was performed; no synthetic data was put into the user's real cache.
- Reviewed synthetic bilingual/theme renders and native CI screenshots. The
  first floating capture was blank; later compact, expanded and dual-window
  captures plus functional assertions provide the accepted visual evidence.
  Local native UI control was unavailable. Existing keyboard, Spaces, hosted
  tooltip and custom-date-editing limits remain explicit in artifact JSON.
- CI artifact `11314614865` supplied exactly the DMG and checksum.
  DMG SHA-256: `898c9bf487ffdfabd3e8c7a2e70e410baf2829f9d8e25b4e6b9d9bd867ac95ce`.
  Checksum-file SHA-256: `614b1b767cd93880382cbd0e237c634a87631c76389bddd9190d5d454b59d743`.
  [Attestation 52645893](https://github.com/DEFY-AN94/codex94/attestations/52645893)
  was verified against this repository, `refs/heads/main`, the CI workflow,
  GitHub-hosted runners and the frozen source. The annotated tag object is `d042833df34800baa9a6983a73bdb006d4b77cec` and peels
  to that source.
- [Public v4.1.1 Release](https://github.com/DEFY-AN94/codex94/releases/tag/v4.1.1)
  (ID `403215362`, published `2026-10-04T21:27:34Z`) was verified through the
  Release API as public, stable and latest. Asset IDs are `610706738` (DMG)
  and `610706741` (checksum). Draft and
  public downloads matched the verified CI bytes. The exact final CI App was
  installed and launched, with executable SHA-256 `1910fd7e666b62f94371e533c4ec67981031d1afe9f01d65229a4d59ea659c52`.
  All 14 descendant bundle entries matched the CI App, including file bytes,
  modes and link destinations. Public ZIP and TAR archives matched all 173
  committed Git blobs and executable modes; a fresh shallow tag clone reproduced
  the frozen source/tree and version/build. The prior App was preserved for
  rollback. No tag or published asset was moved
  or overwritten. The App remains ad-hoc signed and the DMG unnotarized;
  attestation is provenance evidence, not Apple notarization. No quarantine was
  removed; none was present on the installed App. Fresh-account first-launch
  Gatekeeper acceptance remains unverified.

### 4.1.2 historical quota display release — 2026-10-05

- Version/build: `4.1.2 (26)`. [PR #51](https://github.com/DEFY-AN94/codex94/pull/51).
  Release source: `eb893574db3d57863803532f1d8a11c576bac3ea`; tree `617898d72b7ea2bb8b6fc26dbb59c450ce31c22f`.
  PR head `0983a6a04a7e0701dd555aec7d1e6dadb31bbd1e` and tested merge `2b8818896f375104411c0426669e0d718651675d`
  are bound to the reviewed evidence; the tested merge and release have the same tree.
- Local full gate: **582 tests executed, 1 existing hosted-focus skip,
  0 failures**, with Universal build and package checks. A skip is not a pass.
  Local executable SHA-256: `82a21717888915ab8881275e236c6a06ac8d5b194c90b9ee2913b393d8eac275`.
  Local DMG SHA-256: `5ea8f722c6406d62ecb1804be8551ae223daf39d6e4a32d058a34424ac7a2bdc`.
  These were local validation artifacts, not the public release bytes.
- PR [CI 37241341675](https://github.com/DEFY-AN94/codex94/actions/runs/37241341675) and
  [CodeQL 37241339329](https://github.com/DEFY-AN94/codex94/actions/runs/37241339329) passed.
  Final-main [CI 37242985953](https://github.com/DEFY-AN94/codex94/actions/runs/37242985953) and
  [CodeQL 37242985978](https://github.com/DEFY-AN94/codex94/actions/runs/37242985978) passed,
  including all five UI scenarios and main-only DMG attestation.
- Local candidate observation: 610 seconds, 2 successful
  Codex background reads, 0 failures and 0 Claude CLI read starts.
  The CLI preference was off before and after. This records background behavior,
  not manual native interaction or a cloud-usage comparison.
- Synthetic English/Chinese, light/dark card and terminal renders cover history;
  floating expanded detail leaves the current main quota unknown. Automated checks
  are not manual native UI, keyboard, Spaces or fresh-account Gatekeeper acceptance.
- Final CI artifact `11318037262` supplied the two manual assets.
  DMG SHA-256: `05416c94f9df834bcf8955ceff1b84c5cdf30a7ef3fb34fd6325b9e100901a92`.
  Checksum-file SHA-256: `b36b0f4be179a2e3384189a87f58b07b9d91049455ecbf8a56a706f4435739f7`.
  [Attestation](https://github.com/DEFY-AN94/codex94/attestations/52662320) was verified for the frozen source and main workflow.
  Annotated tag object `3dcb2d3aa5dee3da5040b563d648b3ae5f95d756` peels to the release source.
- [Public v4.1.2 Release](https://github.com/DEFY-AN94/codex94/releases/tag/v4.1.2), ID `403257203`,
  was verified as public, stable and latest. Draft and public asset downloads
  matched final CI bytes. Public ZIP and TAR matched the frozen source's
  175 tracked blobs and executable modes.
- The final CI App was installed and its startup verified. Installed executable
  SHA-256: `fa0aedc77ce90cc88c72f3f9e773c7f04f190c35d0dc7b61d6627a35e5368af9`; the installed bundle matches CI.
  This is separate from the local candidate and its observation record above.
  Distribution remains an unsigned, unnotarized DMG with an ad-hoc signed inner App;
  attestation does not establish Apple trust. No automatic installation was added.
  The previous App was preserved for rollback. No quarantine was removed; none
  was present on the installed App. Fresh-account first-launch Gatekeeper
  acceptance remains unverified.

### 4.1.3 shared quota meter release — 2026-10-07

- Version/build: `4.1.3 (27)`. [PR #53](https://github.com/DEFY-AN94/codex94/pull/53).
  Release source: `a1eb34d30b36e31365817c77f90dfda4f96e4a8d`; tree `4e5621a3f016cbd203445f3095ec35cbc76d7eb9`.
  PR head `d5c2903fa4e0011313df7e1e93eebc36a3d6da80` and tested merge `584c24a22167d1d1312b3b36e763909a7fb0eebc`
  are bound to the reviewed evidence; the tested merge and release have the same tree.
- Local full gate: **582 tests executed, 1 existing hosted-focus skip,
  0 failures**, with Universal build and package checks. A skip is not a pass.
  Local executable SHA-256: `b74a2b6084c757f077f18c807f1a0244fa8911cc895f5b56db07b72618a1b2de`.
  Local DMG SHA-256: `a10b99c36eca621fc3e4444745a4cf0f99626569789f492164d58a1681000bc1`.
  These are local validation artifacts, not the public release bytes.
- PR [CI 37474226344](https://github.com/DEFY-AN94/codex94/actions/runs/37474226344) and
  [CodeQL 37474186049](https://github.com/DEFY-AN94/codex94/actions/runs/37474186049) passed.
  Final-main [CI 37477924191](https://github.com/DEFY-AN94/codex94/actions/runs/37477924191) and
  [CodeQL 37477923781](https://github.com/DEFY-AN94/codex94/actions/runs/37477923781) passed,
  including all five UI scenarios and main-only DMG attestation.
- Local candidate observation: 610 seconds, 2 successful
  Codex background reads, 0 failures and 0 Claude CLI read starts.
  The CLI preference was off before and after. This records background behavior,
  not manual native interaction or a cloud-usage comparison.
- The shared `QuotaMeterRow` change is presentation-only. Synthetic checks cover
  bilingual/theme geometry, precise percentages, long names and the unchanged
  original time of historical reports. Dashboard history keeps its text layout;
  native rings, Auto selection and notifications still exclude historical data.
  Existing test methods were extended; no new test count is inferred from them.
- Automated checks are not manual native UI, keyboard, Spaces or fresh-account
  Gatekeeper acceptance. No live `/usage` validation is claimed; the optional
  CLI reader stays default-off and OAuth work remains paused.
- Final CI artifact `11419738051` supplied the two manual assets.
  DMG SHA-256: `4528c745cff87bcad6af4ae717297273f2b71f1520aaac5a06332389230a20c2`.
  Checksum-file SHA-256: `c3f5424f86dbf58f06322737f54ece45330676e9c798d003bc7f61d025f5fd27`.
  [Attestation](https://github.com/DEFY-AN94/codex94/attestations/53209179) was verified for the frozen source and main workflow.
  Annotated tag object `ddf6488ed1f09be7ba127665ad0e615e9e1d6be9` peels to the release source.
- [Public v4.1.3 Release](https://github.com/DEFY-AN94/codex94/releases/tag/v4.1.3), ID `404845580`,
  published `2026-10-06T14:53:53Z`, was verified as public, stable and latest.
  Draft and public asset downloads matched final CI bytes. Public ZIP and TAR
  matched the frozen source's 175 tracked blobs and executable modes.
- The final CI App was installed and its startup verified. Installed executable
  SHA-256: `ff48901c2df031dd3986968b571bd4c74e44331858151d79b64cd57207f42a59`; the installed bundle matches CI.
  This is separate from the local candidate and any observation record above.
  Distribution remains an unsigned, unnotarized DMG with an ad-hoc signed inner App;
  attestation does not establish Apple trust. No automatic installation was added.
  The previous App was preserved for rollback. No quarantine was removed; none
  was present on the installed App. Fresh-account first-launch Gatekeeper
  acceptance remains unverified.
