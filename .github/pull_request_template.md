## Summary

Describe the focused change and why it is needed.

## Validation

- [ ] I reviewed the complete diff, including any AI-assisted changes.
- [ ] I ran `./script/release_check.sh` successfully.
- [ ] I added or updated focused tests for behavior changes.
- [ ] I did not add credentials, account identity, raw RPC payloads, or private paths.
- [ ] I documented any new preference/cache field, entitlement, permission, or
  network boundary—or confirmed none was added.
- [ ] I kept `README.md` and `README.zh-CN.md` synchronized when applicable.
- [ ] I documented any user-visible or security-boundary change.

For a `0.2.0` source + DMG release candidate:

- [ ] I opened this PR as Draft and recorded baseline `main`, the PR head SHA,
  exact tested merge SHA/tree, `0.2.0 (11)`, risks, rollback, checks, and final
  DMG/App acceptance as Pending.
- [ ] I verified the candidate allowlist contains only the Universal,
  unnotarized DMG and its checksum, recorded the exact SHA, and classified the
  outer DMG as unsigned and the inner App as ad-hoc signed only.
- [ ] I recorded artifact/attestation status without describing provenance as
  Apple signing, notarization, malware review, or Gatekeeper approval.
- [ ] I reviewed the actual synthetic UI images for layout and privacy; I did not
  treat a nonempty artifact as visual evidence.
- [ ] I kept release notes under Unreleased and stable install instructions on
  the latest published tag until the actual release date is known. I will use a
  reviewed docs-only Draft PR before tagging if the date or text changes.
- [ ] I documented both `/Applications/Codex94.app` and
  `~/Applications/Codex94.app`, the no-double-run/uninstall boundary, SHA and
  attestation checks, and Apple's official Open Anyway flow without suggesting
  removal of quarantine or disabling Gatekeeper.

Release authorization gates (record each separately; an earlier gate never
authorizes a later one):

- [ ] 1. Commit, push, and create this Draft PR were explicitly authorized.
- [ ] 2. Marking the reviewed Draft Ready was explicitly authorized.
- [ ] 3. Merge was explicitly authorized.
- [ ] 4. Creating and narrowly pushing annotated `v0.2.0` was explicitly
  authorized.
- [ ] 5. Creating the Draft Release and uploading exactly two assets was
  explicitly authorized.
- [ ] 6. App installation/replacement and maintainer-led Open Anyway acceptance
  were explicitly authorized.
- [ ] 7. Publishing the same Draft as Latest was explicitly authorized.

Published assets follow a manual non-replacement policy. SHA/API digests and
attestation detect drift; without Immutable Releases, GitHub does not prevent an
authorized maintainer from replacing an asset.
