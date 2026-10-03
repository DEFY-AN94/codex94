# Release workflow: source + technical-user DMG

The published stable version is [`v3.1.4 (20)`](https://github.com/DEFY-AN94/codex94/releases/tag/v3.1.4),
released on 2026-09-28 (Australia/Melbourne). Its tag and DMG remain bound to
release commit `0aae38d7eff9c910ce25778c60ccf429b67cd22a`; later docs-only commits do not move
that tag or regenerate its assets. Keep public download and source-clone
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

The current target is `4.0.1 (22)`, dated 2026-10-03 (Australia/Melbourne), still
unpublished. It carries forward dual-provider monitoring and fixes delayed
`/usage` submission when the Claude input footer has right-aligned hints.
The maintainer chose to retain `v4.0.0` unchanged and removed its Draft Release;
do not move or reuse that tag. The 4.0.0 candidate's test and native-observation
records do not establish validation of this fix. Keep public stable links at
3.1.4 until the new release is verified and published.

For this release, the maintainer approved a ten-minute live-observation scope.
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
instructions point to `v3.1.4`. This maintenance release isolates quota request contexts, shares strict
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
Actions/Python/Swift CodeQL on the actual tested revision. The `4.0.1` gate
includes five UI scenarios: Display, Recovery, Token usage, Floating, and
Providers. Providers uses only synthetic CLI data; its success does not replace
separate acceptance of the installed Claude Code version and authenticated profile.
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
