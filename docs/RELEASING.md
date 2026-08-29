# Source release workflow

Codex94 distributes source only. Local installs are ad-hoc signed and are not
notarized, so they must not be presented as frictionless public binary
downloads. This checklist covers normal source releases and the one-time public
repository transition.

## 1. Prepare the release candidate

1. Start from an up-to-date `main` branch and review all changes since the
   previous source tag.
2. Choose a new semantic version. Update `MARKETING_VERSION` and
   `CURRENT_PROJECT_VERSION` when producing a new app version.
3. During implementation and the initial Draft PR, keep candidate notes under
   **Unreleased** without a date or release claim. Keep stable installation and
   clone instructions on the latest tag that actually exists.
4. Keep `README.md` and `README.zh-CN.md` synchronized for any change to
   installation, behavior, security boundaries, screenshots, or distribution.
5. Review documentation and fixture images for email addresses, account IDs,
   tokens, real quota values, private paths, and machine-specific details.
6. Keep the release source-only. Do not create or attach an App, ZIP, DMG, or
   other binary artifact to a GitHub Release.

A documentation-only commit on `main` does not require moving an existing tag
or changing the installed app version. It can be included naturally in the next
new source version.

## 2. Verify locally

Install contributor tools if needed:

```bash
brew install ripgrep jq
```

Run the complete gate and inspect repository state:

```bash
./script/release_check.sh
git diff --check
git status --short
git log -1 --show-signature
git tag --list --sort=version:refname
```

The release check must pass. Before tagging, `git status --short` must print
nothing. Review the final commit range once more:

```bash
git diff --stat PREVIOUS_TAG..HEAD
git diff --check PREVIOUS_TAG..HEAD
```

Replace `PREVIOUS_TAG` with the latest published source tag.

## 3. Draft PR, exact-head review, Ready, and merge

Create and push a release branch instead of committing directly to `main`:

```bash
RELEASE_BRANCH="codex/vX.Y.Z-focused-change"
git switch -c "$RELEASE_BRANCH"
git push -u origin "$RELEASE_BRANCH"
```

Open the pull request as **Draft**. Record its exact head SHA, version/build,
scope, risk and rollback notes, automated checks, and synthetic UI evidence.
Mark final App acceptance as **Pending**. Creating a Draft does not authorize
Ready for review, merge, tagging, or installation.

For the exact Draft head:

1. Wait for every required test, UI display/recovery, and CodeQL check to finish
   successfully. Pending, skipped, cancelled, or failed checks are not green.
2. Download the synthetic UI artifacts and inspect the actual app-window images
   for layout, clipping, localization, synthetic content, and privacy. A file's
   existence or nonzero size is not visual evidence.
3. Build the exact-head App for maintainer review. Record the reviewed SHA. Any
   later App source, resource, project-setting, or Info.plist change invalidates
   that acceptance and requires a new build and review. A documentation-only
   change does not invalidate App acceptance, but still requires documentation
   checks and CI.
4. After image review and explicit acceptance of the exact-head App, obtain
   separate authorization before marking the pull request **Ready for review**.
5. Ready does not authorize merge. Obtain separate merge authorization, then
   squash-merge and record the resulting `main` commit. Never tag the release
   branch commit.

Before Ready, finalize release-facing documentation on the same Draft. Replace
candidate-only wording only when it remains true before and after tag creation;
for example, say that the new tag is available only after publication. Move the
changelog entry out of **Unreleased** only when the actual source-release date is
known. If the expected date changes, correct it through the reviewed pull-request
flow rather than guessing.

## 4. Verify final main, then create the immutable tag

After merge, fetch the exact remote `main` and wait for every required check on
that commit to complete successfully. Re-audit version/build, bilingual README,
changelog date, privacy, security, contribution guidance, Issue/PR templates,
stable install instructions, and screenshot provenance. If anything is missing
or the release date changed, stop and use a small docs-only Draft PR through the
same Ready/merge/main-CI gates. Do not tag first and repair documentation later.

Only after final `main` and its checks are verified, and after separate tag
authorization, create and inspect one new annotated tag on that exact commit:

```bash
VERSION=X.Y.Z
TAG="v$VERSION"
MAIN_SHA="$(git rev-parse origin/main)"

test -z "$(git tag --list "$TAG")"
test -z "$(git ls-remote --tags origin "refs/tags/$TAG" "refs/tags/$TAG^{}")"
git tag -a "$TAG" "$MAIN_SHA" -m "Codex94 $TAG"
test "$(git cat-file -t "$TAG")" = tag
test "$(git rev-parse "${TAG}^{}")" = "$MAIN_SHA"
git show --stat "$TAG"
git push origin "refs/tags/$TAG:refs/tags/$TAG"
```

Never move, reuse, delete, or recreate a tag that has already been pushed. If a
published tag points to the wrong commit, preserve it and issue a new version
with a clear changelog entry. In particular, the existing `v0.1.3` tag must
remain unchanged. Avoid `git push --tags`; push only the intended new tag.

Re-read the remote tag object and peeled commit, then validate a fresh shallow
clone of the public source:

```bash
git ls-remote --tags origin "refs/tags/$TAG" "refs/tags/$TAG^{}"

VERIFY_ROOT="$(mktemp -d)"
git clone --branch "$TAG" --depth 1 \
  https://github.com/DEFY-AN94/codex94.git "$VERIFY_ROOT/codex94"
test "$(git -C "$VERIFY_ROOT/codex94" rev-parse HEAD)" = "$MAIN_SHA"
rg -n 'MARKETING_VERSION|CURRENT_PROJECT_VERSION' \
  "$VERIFY_ROOT/codex94/Codex94.xcodeproj/project.pbxproj"
```

The remote object must be an annotated tag, its peeled commit and the shallow
clone's `HEAD` must equal the verified final `main`, and both Debug and Release
must report the intended version/build. Also recheck the completed `main` CI and
all release-facing documentation. A source tag does not require a GitHub Release.

## 5. Maintain the GitHub page

Confirm that:

- The README language links, images, and relative documentation links resolve.
- The About description and repository topics still match the project.
- The repository visibility is intentional.
- The new tag points to the CI-verified commit.

A source tag does not require a GitHub Release. If a source-only GitHub Release
is added later, describe it accurately and do not attach an ad-hoc-signed app as
a public binary.

## 6. One-time public repository transition

The maintainer changes repository visibility manually. Before doing so, review
the current tree, every reachable commit and tag, unreachable local Git objects,
documentation screenshots and metadata, and all retained GitHub Actions logs.
Changing a private repository to public also exposes its Actions history.

Immediately after switching visibility to Public:

1. Enable Private Vulnerability Reporting, Secret Scanning, and Push Protection.
2. Enable Swift CodeQL Default Setup with the Extended query suite.
3. Add an active `main` ruleset requiring pull requests, the `test` status check,
   and linear history; block force pushes and deletion, with an owner emergency
   bypass and zero required approvals for the current solo-maintainer workflow.
4. Add a `v*` tag ruleset that blocks tag updates and deletion while permitting
   the owner to create new release tags.
5. Allow squash and rebase merges, disable merge commits, enable auto-merge, and
   delete merged branches automatically.
6. Restrict Actions to GitHub-created actions and require full-length commit
   SHAs.
7. Set the About description to `Unofficial macOS quota monitor compatible with
   OpenAI Codex. Vibe-built with Codex. / 与 OpenAI Codex 兼容的非官方 macOS
   额度监控工具。` and retain the existing topics.
8. Verify the README language links, Issue forms, Security policy, CI result,
   visibility, rulesets, and immutable release tag from a signed-out browser.

## 7. Binary distribution comes later

A public `.app`, ZIP, or DMG requires a reproducible universal archive,
Developer ID Application signing, Apple notarization, stapling, Gatekeeper
validation, and testing on a clean Mac. Document supported architectures and
minimum macOS version, publish checksums, and verify the downloaded artifact
before announcing it.

Until that pipeline exists, direct users to the source installation instructions
in the README.
