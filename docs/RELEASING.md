# Publishing Codex94 for the first time

This checklist assumes the repository has never been published. The first public
version should be source-only. The current local app uses an ad-hoc signature and
is not notarized, so it should not be presented as a frictionless downloadable
binary.

## 1. Verify locally

```bash
./script/release_check.sh
git status --short
git log -1 --show-signature
git tag --list --sort=version:refname
```

The release check must pass, and `git status --short` must print nothing. Review
the public diff and history one last time for names, email addresses, tokens, and
machine-specific paths.

## 2. Create the GitHub repository

1. On GitHub, choose **New repository**.
2. Use `Codex94` as the repository name and choose public or private visibility.
3. Do not initialize it with a README, `.gitignore`, or license; all three already
   exist locally.
4. Enable Issues and private vulnerability reporting under **Settings > Security**.

## 3. Connect and push

Replace `YOUR-ACCOUNT` with the GitHub owner shown in the new repository. For a
first setup, HTTPS with GitHub CLI authentication avoids managing SSH keys:

```bash
gh auth login --web
gh auth setup-git
git remote add origin https://github.com/YOUR-ACCOUNT/Codex94.git
git push -u origin main
```

If `gh` is not installed, install [GitHub CLI](https://cli.github.com/) or
configure an SSH key, verify it with `ssh -T git@github.com`, and use the SSH
remote instead.

Open the repository's **Actions** tab and wait for CI to pass on `main`. Only
then publish the intended source tag:

```bash
git push origin v0.1.3
```

Do not use `git push --tags` for the first publication; the older local milestone
tags do not need to become releases. Then add repository topics such as `macos`,
`swift`, `swiftui`, `menu-bar-app`, and `codex` and use the first paragraph of the
README as the repository description.

## 4. Protect the main branch

In **Settings > Branches**, add a rule for `main` that requires the CI check and
prevents force pushes. Keep pull-request review optional while there is only one
maintainer, then require it when collaborators join.

## 5. Binary releases come later

A public `.app`, ZIP, or DMG should be built as a universal binary, signed with a
Developer ID Application certificate, notarized by Apple, stapled, and tested on
a clean Mac. Do not upload the local ad-hoc build as if it were notarized. Source
tags can be published now without creating a GitHub Release asset.
