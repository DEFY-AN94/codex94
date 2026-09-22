# Release workflow: source + technical-user DMG

The published stable version is [`v3.0.1 (15)`](https://github.com/DEFY-AN94/codex94/releases/tag/v3.0.1),
released on 2026-09-21 (Australia/Melbourne). Its tag and DMG remain bound to
release commit `ab6d48e5011eba2c10e9f31f51e4ef1f3c166307`; later docs-only commits do not move
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

Start from a clean, freshly fetched baseline. Review changes since the published
tag and any branch/tag/Release name conflicts. Preserve unknown worktree
changes and existing tags; do not stash/reset/clean or force-push as preparation.
Keep candidate changelog notes under Unreleased without inventing a date.
Historical release entries and the existing synthetic screenshot provenance
remain unchanged. Planning and Goal files stay outside the Git repository.

The current candidate is `3.1.0 (16)`, with its date kept under **Unreleased**
until release preparation is complete. In addition to the retained regression
checks below, verify:

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

Candidate validation includes a fourth **Floating** UI scenario and expanded
Token usage coverage. Report their results only after the exact candidate has
run; historical test counts and screenshots do not validate these additions.

Version `3.0.1 (15)` was published on 2026-09-21 (Australia/Melbourne).
Published download and source-clone instructions now point to `v3.0.1`.
This maintenance release isolates quota request contexts, shares strict
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
buttons using the same popover toggle and normal refresh-on-open path. Check
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

Wait for CI and, for `3.1.0`, all four synthetic UI smokes
(Display, Recovery, Token usage, and Floating),
and Actions/Python/Swift CodeQL on the actual tested revision.
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
