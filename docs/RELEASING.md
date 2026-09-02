# Release workflow: source + technical-user DMG

Codex94 `0.2.0 (11)` uses two release tracks from one verified final `main`
commit and one annotated `v0.2.0` tag:

- source installation with `script/install.sh`; and
- a Universal 2, explicitly unnotarized DMG for technical users.

The DMG itself is completely unsigned. It has no Apple Developer ID signature
and is not notarized or stapled. The `Codex94.app` inside is ad-hoc signed with
Hardened Runtime only. SHA-256 and GitHub artifact attestation provide integrity
and workflow provenance; they do not provide Apple trust, malware review, or
Gatekeeper approval.

## 1. Authorization gates

The release is deliberately fail-closed. Each item below requires a separate,
explicit maintainer authorization; an earlier authorization never includes a
later one:

1. commit, push the release branch, and create a Draft pull request;
2. mark the reviewed Draft pull request Ready;
3. merge it;
4. create and narrowly push annotated `v0.2.0`;
5. create a Draft GitHub Release and upload exactly two assets;
6. install/replace the App and let the maintainer complete current-account
   Gatekeeper/Open Anyway acceptance; and
7. publish the same Draft as the public Latest Release.

Before the corresponding gate, do not commit, push, create or update a pull
request, merge, create/push a tag, create/upload a Release, install an App,
operate Privacy & Security/Open Anyway/Login Items, publish, or modify repository
settings.

## 2. Prepare and verify the candidate

Start from a clean, fetched repository and review every commit since the latest
published tag. Confirm that the intended version is `0.2.0 (11)`, the target
branch and tag do not conflict, and the previous annotated tags remain
unchanged. Never stash, reset, clean, force-push, move a tag, or overwrite an
unknown local change as release preparation.

During implementation and the initial Draft PR:

- keep the `0.2.0` changelog entry under **Unreleased**, without a guessed date;
- keep `README.md` and `README.zh-CN.md` synchronized;
- preserve the historical `0.1.9` facts and screenshot provenance;
- keep real identity, quota, credentials, preferences, cache, private paths,
  Finder/system-settings screenshots, and full-screen captures out of fixtures,
  artifacts, and documentation; and
- do not copy external planning or Goal files into Git or an artifact.

Install contributor tools if needed, then run the release gate:

```bash
brew install ripgrep jq
./script/release_check.sh
git diff --check
git status --short
```

`release_check.sh` owns the only Release build. It must produce one exact
Universal 2 App and verify both `arm64` and `x86_64` slices, ad-hoc signing,
Hardened Runtime, no Team ID, and no entitlement keys. `package_dmg.sh` only
packages or verifies that App; it must not build, install, launch, stop a user
App, or read user data.

The formal candidate directory is `.build/Distribution/0.2.0/` and contains
exactly these two regular files:

- `Codex94-0.2.0-macos-universal-unnotarized.dmg`
- `Codex94-0.2.0-SHA256SUMS.txt`

The checksum contains one lowercase SHA-256 line for the DMG. Verify it and the
mounted App with the repository script:

```bash
./script/package_dmg.sh verify \
  .build/Distribution/0.2.0/Codex94-0.2.0-macos-universal-unnotarized.dmg \
  .build/Distribution/0.2.0/Codex94-0.2.0-SHA256SUMS.txt \
  0.2.0 11
```

Damaged-DMG/checksum tests use copies in an isolated run directory; they never
modify the formal candidate. If a formal candidate becomes invalid after an
App, script, resource, project-setting, or Info.plist change, record its SHA and
the invalidation reason, then recoverably archive it under the approved
`.build/DistributionArchive/<UTC YYYYMMDDTHHMMSSZ>-<12-char HEAD>/0.2.0/`
layout before generating a new one. Stop if that exact archive destination
already exists. Do not delete or overwrite it.

## 3. Draft PR, Ready, and merge

Only after gate 1 authorization, commit the reviewed local implementation,
explicitly push the release branch, and create a **Draft** pull request. Record:

- baseline `main`, PR head SHA, exact tested merge SHA, and tested tree;
- `0.2.0 (11)`, scope, risk, rollback, and privacy/signing boundaries;
- the candidate artifact name and SHA;
- test, Display/Recovery UI, CodeQL, artifact, and attestation states; and
- final DMG/install acceptance as **Pending**.

GitHub pull requests test the default merge ref. `${{ github.sha }}` and the
candidate artifact name therefore identify the exact tested merge SHA, not the
PR head. Record both values, and invalidate old evidence whenever the PR head or
merge ref changes.

Wait for the platform-required checks and the additional fail-closed release
checks. UI smoke and CodeQL remain mandatory human release gates even if the
repository ruleset does not mark them required. Pending, skipped, cancelled,
environment-limited, or failed is not passed. Inspect the actual synthetic UI
images; a nonempty file is not visual proof.

Gate 2 authorizes Ready only. Gate 3 separately authorizes merge. After merge,
fetch the exact remote `main`, record its commit and tree, and wait for all
final-main checks. If a release-facing document, version, or date is wrong, use
a small docs-only Draft PR through the same Draft/Ready/merge gates. Do not tag
first and repair the tagged tree later.

## 4. Final-main artifact, attestation, and tag

The final `main` test run must generate the DMG/checksum and the main-only
attestation job must succeed. Download that exact artifact, run the standalone
verify command, and record its workflow run, final-main commit, DMG SHA, checksum
file SHA, and attestation URL. The public Release must use these exact CI bytes;
do not rebuild a local substitute. If the seven-day artifact expires, rerun the
controlled workflow only on the same exact final-main commit and reverify it.

Verify provenance with:

```bash
gh attestation verify Codex94-0.2.0-macos-universal-unnotarized.dmg \
  -R DEFY-AN94/codex94
```

Only after gate 4 authorization, create one annotated tag on the verified final
`main`; the message is exactly `Codex94 v0.2.0`:

```bash
TAG=v0.2.0
MAIN_SHA="$(git rev-parse origin/main)"

test -z "$(git tag --list "$TAG")"
test -z "$(git ls-remote --tags origin "refs/tags/$TAG" "refs/tags/$TAG^{}")"
git tag -a "$TAG" "$MAIN_SHA" -m "Codex94 v0.2.0"
test "$(git cat-file -t "$TAG")" = tag
test "$(git rev-parse "${TAG}^{}")" = "$MAIN_SHA"
git push origin "refs/tags/$TAG:refs/tags/$TAG"
```

Never use `git push --tags`. Re-read the remote tag object and peeled commit,
then shallow-clone `v0.2.0` and prove its `HEAD`, version, and build match final
`main`. Never move, delete, or recreate an existing release tag.

## 5. Draft GitHub Release

Gate 5 authorizes one Draft Release using the already verified tag and exact
final-main CI files. It does not authorize Publish. Prepare a release body from
the template below and create the Draft with all state flags explicit:

```bash
gh release create v0.2.0 \
  Codex94-0.2.0-macos-universal-unnotarized.dmg \
  Codex94-0.2.0-SHA256SUMS.txt \
  --title "Codex94 v0.2.0" \
  --notes-file RELEASE_BODY.md \
  --draft --verify-tag --latest=false --prerelease=false
```

Do not use `--clobber`. The Draft has exactly the two manual assets above;
GitHub's automatic source ZIP/TAR files are not listed in `SHA256SUMS` and are
not claimed to be byte-reproducible.

After upload, query each manual asset through the GitHub Release Assets API.
Its digest must be present and exactly `sha256:<64 lowercase hexadecimal
characters>`. Missing, empty, unknown-algorithm, or mismatched digest values
fail closed. Download both Draft assets again, run `package_dmg.sh verify`,
compare both local hashes/API digests, and rerun `gh attestation verify`.

## 6. Release body template

Replace `ACTUAL_RELEASE_DATE` only after the real release date is known, and
replace `FINAL_DMG_SHA256` only with the lowercase SHA-256 of the exact verified
final-main CI DMG. If the date changes before tagging, correct the changelog and
this release-facing text through a reviewed docs-only Draft PR before creating
the tag. Never guess a date or tag first and amend the tagged tree later.

```markdown
# Codex94 v0.2.0

Release date / 发布日期: ACTUAL_RELEASE_DATE

Codex94 0.2.0 (11) adds a Universal 2 technical-user DMG while retaining
source installation from the annotated v0.2.0 tag. Launch at Login now accepts
both /Applications/Codex94.app and ~/Applications/Codex94.app.

Codex94 0.2.0 (11) 新增面向技术用户的 Universal 2 DMG，同时保留从 annotated
v0.2.0 标签进行源码安装。登录时启动现在同时接受 /Applications/Codex94.app 与
~/Applications/Codex94.app。

## Assets / 资产

- Codex94-0.2.0-macos-universal-unnotarized.dmg
- Codex94-0.2.0-SHA256SUMS.txt
- macOS 14+, Apple Silicon arm64 + Intel x86_64

## Security notice / 安全提示

This DMG itself is completely unsigned, has no Apple Developer ID signature,
and has not been notarized or stapled by Apple. The Codex94.app inside is
ad-hoc signed with Hardened Runtime only. macOS may block the first launch.

此 DMG 外层本身完全未签名，没有 Apple Developer ID 签名，也未经过 Apple 公证
或 stapling。其中的 Codex94.app 只有带 Hardened Runtime 的 ad-hoc 签名；macOS
可能阻止首次启动。

Verify the published SHA-256 first. You may also verify GitHub workflow/commit
provenance with:

    DMG SHA-256: FINAL_DMG_SHA256
    shasum -a 256 -c Codex94-0.2.0-SHA256SUMS.txt
    gh attestation verify Codex94-0.2.0-macos-universal-unnotarized.dmg -R DEFY-AN94/codex94

Attestation is not Apple signing, notarization, a security audit, or Gatekeeper
approval. If you trust the exact verified release, drag Codex94.app to
Applications and use Apple's official
[Privacy & Security → Open Anyway](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/26/mac/26)
flow if macOS blocks it. Do not disable Gatekeeper or remove quarantine
attributes.

请先验证发布的 SHA-256；也可以使用上面的命令核验 GitHub workflow/commit 来源。
Attestation 不是 Apple 签名、公证、安全审计或 Gatekeeper 放行。若你信任已精确
核验的版本，请把 Codex94.app 拖到 Applications；如被 macOS 阻止，只使用 Apple
官方[“隐私与安全性 → 仍要打开”](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/26/mac/26)
流程。不要关闭 Gatekeeper，也不要删除 quarantine。

Source installation remains available from annotated v0.2.0 through
script/install.sh. Quit the old App before installing, do not run copies from
both Applications locations at once, and note that Codex94 has no automatic
updater. This DMG is intended for technical users who accept these limitations.

源码安装仍可从 annotated v0.2.0 标签通过 script/install.sh 完成。安装前请退出旧
App，不要同时运行两个 Applications 位置的副本。Codex94 没有自动更新功能；此 DMG
面向理解并接受上述边界的技术用户。
```

## 7. Current-account Gatekeeper acceptance

Only gate 6 authorizes installation/replacement and the maintainer-led manual
acceptance. From the Draft Release page, download the assets in a browser,
verify SHA/attestation first, and read (do not remove) the DMG's quarantine
xattr. Mount it and confirm the only top-level items are `Codex94.app` and the
`Applications` shortcut.

Quit every old Codex94 process before the maintainer drags the App to
`/Applications`. Do not automatically delete a source-installed
`~/Applications/Codex94.app`; do not run both copies. Record the copied App's
quarantine xattr, launch the exact `/Applications/Codex94.app`, and, if blocked,
let the maintainer use Apple's official Privacy & Security → Open Anyway flow.
Automation must not enter a password, remove quarantine, disable Gatekeeper,
operate System Settings, or change the real Login Item.

Confirm `0.2.0 (11)`, basic Dashboard/Popover behavior, and that Launch at Login
is no longer disabled by the stable-install gate at `/Applications`. If either
quarantine xattr is missing or the current account opens the App directly, mark
first-launch Gatekeeper evidence insufficient/uncertain. Never describe direct
opening as proof that an unnotarized App is automatically trusted. The
maintainer decides whether to accept this constrained evidence.

## 8. Publish and post-release verification

Only gate 7 authorizes publishing the existing Draft. Do not create a second
Release:

```bash
gh release edit v0.2.0 \
  --draft=false --latest --prerelease=false --verify-tag
```

From a public/signed-out view, redownload both assets and recheck:

- exact filenames and exactly two manual assets;
- `SHA256SUMS`, local DMG/checksum hashes, and each asset's
  `sha256:<hex>` Release Assets API digest;
- DMG structure, Universal slices, per-architecture signing/empty entitlements,
  outer-DMG unsigned state, and attestation;
- annotated tag object/peeled commit, final `main`, and a shallow clone;
- `0.2.0 (11)`, bilingual README/security warnings, and public Latest/non-
  prerelease state; and
- the automatically generated source ZIP/TAR, without treating them as the two
  manual assets or claiming byte reproducibility.

Codex94 does not enable GitHub Immutable Releases for `v0.2.0`. Published assets
must not be replaced, deleted, or silently repaired as a manual release policy;
SHA-256, API digests, and attestation can detect drift, but the platform does
not prevent an authorized maintainer from replacing an asset. If App/DMG bytes
must change, preserve `v0.2.0`, stop, and prepare a patch release such as
`v0.2.1`.
