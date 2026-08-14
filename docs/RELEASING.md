# Source release workflow

Codex94 distributes source only. Local installs are ad-hoc signed and are not
notarized, so they must not be presented as frictionless public binary
downloads. This checklist covers normal source releases and the one-time public
repository transition.

## 1. Prepare the release

1. Start from an up-to-date `main` branch and review all changes since the
   previous source tag.
2. Choose a new semantic version. Update `MARKETING_VERSION` and
   `CURRENT_PROJECT_VERSION` when producing a new app version.
3. Move the relevant entries from **Unreleased** in `CHANGELOG.md` into the new
   dated version section.
4. Keep `README.md` and `README.zh-CN.md` synchronized for any change to
   installation, behavior, security boundaries, screenshots, or distribution.
5. Review documentation and fixture images for email addresses, account IDs,
   tokens, real quota values, private paths, and machine-specific details.

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

## 3. Open a release pull request and wait for CI

Create and push a release branch instead of committing directly to `main`:

```bash
VERSION=X.Y.Z
git switch -c "release/v$VERSION-public"
git push -u origin "release/v$VERSION-public"
```

Open a pull request to `main`. The `test` job must pass before the maintainer
squash-merges the pull request. Confirm that `main` now points to the verified
merge commit; do not tag the release branch commit.

## 4. Create a new immutable tag

After the pull request is merged and CI succeeds on `main`, create and inspect a
new annotated tag on that merge commit:

```bash
VERSION=X.Y.Z
git tag -a "v$VERSION" -m "Codex94 v$VERSION"
git show --stat "v$VERSION"
git push origin "v$VERSION"
```

Never move, reuse, delete, and recreate a tag that has already been pushed. If a
published tag points to the wrong commit, preserve it and issue a new version
with a clear changelog entry. In particular, the existing `v0.1.3` tag must
remain unchanged.

Avoid `git push --tags`; push only the intended new tag.

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
