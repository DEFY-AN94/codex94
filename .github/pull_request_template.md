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

For a source-release candidate:

- [ ] I opened this PR as Draft and recorded the exact candidate SHA,
  version/build, risks, rollback, checks, and final App acceptance status.
- [ ] I reviewed the actual synthetic UI images for layout and privacy; I did not
  treat a nonempty artifact as visual evidence.
- [ ] I kept release notes under Unreleased and stable install instructions on
  the latest published tag until the final release-documentation step.
- [ ] I obtained separate authorization for Ready; I understand that Ready does
  not authorize merge, tagging, or installation.
