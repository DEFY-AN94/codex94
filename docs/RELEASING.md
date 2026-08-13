# Source release workflow

Codex94 currently distributes source only. Local installs are ad-hoc signed and
are not notarized, so they must not be presented as frictionless public binary
downloads. This checklist applies to each future source version after the
repository has already been created.

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

## 3. Push and wait for CI

Push the release commit to `main` using the repository's normal review policy:

```bash
git push origin main
```

Wait for the GitHub Actions CI workflow on that exact commit to pass. Do not tag
a different or unverified commit.

## 4. Create a new immutable tag

After CI succeeds, create and inspect a new annotated tag:

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

## 6. Binary distribution comes later

A public `.app`, ZIP, or DMG requires a reproducible universal archive,
Developer ID Application signing, Apple notarization, stapling, Gatekeeper
validation, and testing on a clean Mac. Document supported architectures and
minimum macOS version, publish checksums, and verify the downloaded artifact
before announcing it.

Until that pipeline exists, direct users to the source installation instructions
in the README.
