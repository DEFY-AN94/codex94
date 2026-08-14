# Contributing

Issues and focused pull requests are welcome. Codex94 targets macOS 14+, Swift 6,
and a zero third-party runtime dependency model.

## Before opening a pull request

1. Keep credential access inside the existing Codex subprocess boundary. Do not
   add browser-cookie, Keychain, token-file, or direct usage-endpoint readers.
2. Do not log or persist account identity, credentials, raw RPC payloads, or
   private filesystem paths.
3. Add focused tests for behavior changes and both English and Simplified Chinese
   strings for visible UI.
4. Keep `README.md` and `README.zh-CN.md` synchronized when installation,
   behavior, security, screenshots, or project status changes.
5. Use sanitized fixture data for documentation screenshots. Never capture a
   real email address, account ID, quota, token, or private filesystem path.
6. Run `./script/release_check.sh`.
7. Explain user-visible behavior, security-boundary changes, and test evidence in
   the pull request.

Use the repository Issue forms for bug reports and feature requests, and follow
the pull request template when submitting a change. AI-assisted contributions
are welcome, but contributors remain responsible for reviewing the complete
diff, tests, security impact, and licensing of their submission.

Use small, scoped commits. Match the existing SwiftUI/AppKit ownership split:
SwiftUI owns views and state presentation; AppKit owns status items, popovers,
application appearance, and window lifecycle.

Do not open a public issue for a suspected vulnerability. Follow
[SECURITY.md](SECURITY.md).
