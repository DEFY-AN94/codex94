# Update checks

This document describes the published stable release
[`v3.1.0 (16)`](https://github.com/DEFY-AN94/codex94/releases/tag/v3.1.0), released
on 2026-09-23 (Australia/Melbourne). README download and source instructions
refer to this release. Update checks are manual; installation remains user-managed.

Version `3.1.0 (16)` retains this manual-only update design. Floating
quota and local Token analysis/image exports add no update polling, download,
installation, relaunch, endpoint, or signing-policy change. Stable discovery
continues to follow the latest published GitHub Release.

## User flow

1. Open Dashboard → About and select **Check for updates**.
2. Codex94 requests the repository's latest public stable GitHub Release and
   compares its version with the running app.
3. A newer version shows its version and plain-text release notes. Select the
   Release-page action to open the validated page in the system browser.
4. Download and verify the published DMG/checksum yourself, quit Codex94, and
   follow the [normal installation instructions](../README.md#install-the-universal-dmg).

The app does not check automatically, download or install an App, or relaunch
itself. Checking does not change the installed version. A candidate ahead of
the public stable release can have no newer stable release available; this
does not make the candidate a published stable version. Network failures,
GitHub rate limits, and invalid responses are errors rather than evidence that
the installed app is up to date.

`0.2.2` has no check command. Its users must manually install `0.3.0` or a
newer published stable version to gain this feature. Subsequent version checks
still lead to browser-based, user-managed installation under this design.

## How the check works

The only metadata endpoint is
[`https://api.github.com/repos/DEFY-AN94/codex94/releases/latest`](https://api.github.com/repos/DEFY-AN94/codex94/releases/latest).
GitHub documents this as the latest published full release and permits public
resource access without authentication. See the
[GitHub Releases REST API](https://docs.github.com/en/rest/releases/releases#get-the-latest-release).

The checker is separate from quota polling and `account/usage/read`. It does
not use the user's GitHub account, Codex credentials, browser cookies, or
Keychain. It sends no quota, token statistics, prompts, or system profile.
GitHub can receive normal HTTP connection metadata, including an IP address
and request headers. Results stay in memory and do not enter the quota cache.

Release metadata is external input. The checker validates the version and
stable-release status and only opens an HTTPS Release URL belonging to this
repository. Notes are plain text, not an embedded web page or executable
markup. The system browser owns subsequent navigation and downloads.

The app does not inspect, download, or verify release binaries during this
metadata check. An available-version notice is not a signature check,
notarization result, malware scan, or guarantee that the installation will
succeed. The existing published package's checksum and provenance verification
instructions remain applicable after downloading it.

## Maintaining stable releases

The existing [release workflow](RELEASING.md) still governs candidates, review,
testing, acceptance, tags, artifacts, and publication. To keep the check useful:

- Publish stable versions with a consistent `vMAJOR.MINOR.PATCH` tag matching
  the packaged app's marketing version. Continue incrementing the build number;
  the GitHub check discovers versions through Release tags, not a separate
  build-number feed.
- Keep candidates as drafts or prereleases until the maintainer authorizes
  stable publication. Mark the intended public stable version as Latest and
  verify GitHub's latest-release API returns that exact release afterward.
- Provide accurate release notes, supported macOS requirements, the verified
  package and checksum, and the actual signing/notarization classification.
  The update UI shows notes as text, so keep the important instructions readable
  without HTML or interactive content.
- Preserve published tags and asset bytes. A correction to the App needs a new
  version rather than replacement under an already published version.
- Check newer/equal/older versions, invalid version strings, drafts/prereleases,
  unexpected URLs, offline/timeouts, rate limits, and malformed responses with
  injected synthetic responses. Automated tests must not trigger real downloads,
  installations, browser navigation, or update polling.
- Before release acceptance, verify the About action and approved Release-page
  navigation with the candidate App. Record this separately from passing parser
  or network-adapter tests.

No update feed, signing keys, update framework, or extra Release asset is
required for this metadata-only checker. Merging its code or documentation
does not publish a release or change GitHub's Latest designation.

## Future automatic installation

In-app replacement remains outside the current release. It needs a separately reviewed
distribution design with appropriate Apple Developer ID signing/notarization,
authenticated update packages, and an end-to-end upgrade test for both supported
Applications locations. Nested code, framework loading, install permissions,
failure recovery, and relaunch behavior must all be validated. The current
Hardened Runtime boundary is not weakened to make an update framework load.

Only after that distribution work is ready should automatic installation,
its dependency/privacy changes, and migration from this manual-check version
be proposed. This document does not claim that path already exists.

## 中文使用说明

[`v3.1.0 (16)`](https://github.com/DEFY-AN94/codex94/releases/tag/v3.1.0) 已于
2026-09-23（Australia/Melbourne）正式发布，现为稳定下载。“关于 → 检查新版本”只在
用户点击后查询本仓库最新公开稳定 Release，显示版本和纯文本说明，并可通过系统
浏览器打开经过验证的发布页面。下载、校验和安装仍由用户完成，不会自动替换或重启
App。`0.2.2` 用户需先手动安装 `0.3.0` 或之后的正式稳定版本，才能使用检查入口。

检查不发送账号或用量数据，结果不落盘；GitHub 仍能看到普通网络连接信息。检查失败
不等于“已是最新”。它也不代表安装包已完成签名、公证或安全审查。未来自动安装需在
Developer ID 分发与完整升级验收准备好后另行设计，不属于当前版本的功能范围。
