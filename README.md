# Codex94

**English** | [简体中文](README.zh-CN.md)

## Overview

Codex94 is an unofficial macOS menu bar utility for monitoring the quota of the
currently signed-in Codex account. A compact ring shows the selected percentage
remaining; clicking it opens a CLI-style quota popover. The app has no Dock icon,
and its Dashboard is focused on connection and display settings.

Codex94 is currently an MIT-licensed source preview in a private repository. It
uses the Codex executable already installed on the Mac and has no third-party
runtime dependencies.

> Codex94 is not affiliated with or endorsed by OpenAI. Codex `app-server` is
> an experimental interface and may change in future Codex releases.

## Screenshots

The values below come from an isolated documentation fixture. They are
illustrative and do not contain a real account, identity, or quota.

<p align="center">
  <img src="docs/images/readme/menu-bar.png" alt="Codex94 menu bar ring showing 79 percent remaining" width="144">
</p>
<p align="center"><strong>Compact menu bar status</strong></p>

<p align="center">
  <img src="docs/images/readme/popover-en.png" alt="Codex94 English CLI-style quota popover" width="500">
</p>
<p align="center"><strong>CLI-style quota popover</strong></p>

<p align="center">
  <img src="docs/images/readme/dashboard-en.png" alt="Codex94 English Connection Dashboard in Terminal Dark" width="900">
</p>
<p align="center"><strong>Connection Dashboard</strong></p>

## Distribution status

- The current stable source tag is `v0.1.3`.
- The repository is currently private, so only invited collaborators can clone
  it.
- There is no GitHub Release, DMG, notarized binary, or automatic updater.
- `script/install.sh` builds a local Release app, applies an ad-hoc Hardened
  Runtime signature, and installs it at `~/Applications/Codex94.app`.
- Re-running the installer replaces that one app in place; it does not retain a
  separate copy for each version.

Do not present a locally ad-hoc-signed build as a publicly notarized download.

## Requirements

- macOS 14 or later.
- Full Xcode 16.4 or later. Command Line Tools alone are insufficient.
- `ripgrep` (`rg`) for the installer's static security check.
- A compatible Codex executable and a current Codex login for live quota data.

Codex94 can use the Codex executable bundled inside the ChatGPT app, so a
standalone Codex CLI installation is not required when that bundled executable
is compatible. It can also detect Homebrew and standard CLI locations or use an
executable selected manually.

## Install from source

While the repository is private, authenticate with a GitHub account that has
collaborator access. The commands below use GitHub CLI for authentication and
install the stable `v0.1.3` source:

```bash
brew install gh ripgrep
gh auth login --web
gh auth setup-git
git clone --branch v0.1.3 --depth 1 https://github.com/DEFY-AN94/codex94.git
cd codex94

sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch

./script/install.sh
```

The installer builds, signs, installs, and opens
`~/Applications/Codex94.app`. Pass `--no-launch` to install without opening
it:

```bash
./script/install.sh --no-launch
```

On first launch, choose whether Codex94 may request **Quota + account** or
**Quota only**. Launch at login can be enabled only after the app is installed
at the stable path above.

## Main behavior

- Refreshes at launch, whenever the popover opens, and every 1, 5, 15, or 30
  minutes according to the selected setting.
- Uses `account/rateLimits/read` for live quota data. In **Quota + account**
  mode it also uses `account/read` with `refreshToken: false`.
- Displays remaining percentage. `Auto` chooses the available window with the
  lowest remaining percentage.
- Hides the 5-hour row and selector whenever Codex does not return that window;
  Weekly remains available when supplied.
- Keeps the last successful value after a refresh failure and marks it stale.
- Closes the transient popover when the user clicks elsewhere without consuming
  the original click or requesting Accessibility permission.
- Locates Codex in this order: manually selected path, ChatGPT app bundle,
  Homebrew, `/usr/local/bin`, `~/.local/bin`, then absolute `PATH` entries.
- Offers Dashboard window presets at 900x600, 1280x720, 1440x810, and 1920x1080
  logical points, with proportional fitting to the current display.
- Supports system, Terminal Dark, and Terminal Light themes plus English and
  Simplified Chinese.
- Uses only the current Codex login. It does not manage multiple accounts or
  alternate `CODEX_HOME` directories.

## Security and privacy

```mermaid
flowchart LR
    A["Codex94"] <-->|"local stdio JSON-RPC"| B["Codex app-server"]
    B -->|"Codex-owned login"| C["OpenAI account service"]
    A --> D["quota-only local cache"]
```

Codex94 starts the validated executable with fixed arguments:

```text
codex -s read-only -a untrusted app-server --stdio
```

Codex itself owns authentication and may contact OpenAI services. Codex94 does
not receive an access or refresh token, make a direct quota HTTP request, or
read authentication files, browser cookies, Keychain entries, Codex session
logs, or SQLite databases.

The local cache stores only quota window type, percentage, reset time, plan type,
and fetch time with owner-only permissions. Email is memory-only in **Quota +
account** mode and is removed from the in-memory snapshot after switching to
**Quota only**. UserDefaults stores interface choices and an optional manually
selected executable path. Codex94 has no analytics, advertising, telemetry
upload, crash-reporting SDK, update checker, or project-operated server.

App Sandbox is intentionally disabled because the Codex child process must
access its own login state. Hardened Runtime remains enabled; subprocess
arguments are fixed, the environment is minimized, output is bounded, requests
time out, and the process group is terminated after each refresh. Version
validation checks protocol compatibility, not publisher identity, so users must
trust the ChatGPT/Codex installation and any executable they select.

See [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md) for the complete
boundaries.

## Development and build

Contributor and release checks also require `jq`:

```bash
brew install ripgrep jq
```

Build and run a Debug app:

```bash
./script/build_and_run.sh
```

Run the static security check, build, launch, and verify the process:

```bash
./script/build_and_run.sh --verify
```

Run the unit and fake app-server integration tests:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Codex94.xcodeproj -scheme Codex94 \
  -destination 'platform=macOS' -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO test
```

Run the complete local release gate:

```bash
./script/release_check.sh
```

SwiftUI owns views and state presentation; AppKit owns the status item, popover,
application appearance, and Dashboard window lifecycle. See
[CONTRIBUTING.md](CONTRIBUTING.md) and
[docs/RELEASING.md](docs/RELEASING.md).

## Uninstall

First disable **Launch at login** in Dashboard and quit Codex94. Then remove the
installed app, local cache, and preferences:

```bash
rm -rf "$HOME/Applications/Codex94.app"
rm -rf "$HOME/Library/Application Support/Codex94"
defaults delete com.defyan94.codex94
```

## License

Codex94 is licensed under the [MIT License](LICENSE). See
[ATTRIBUTIONS.md](ATTRIBUTIONS.md) for design and implementation references.

Codex and ChatGPT are trademarks of OpenAI. Codex94 is an independent,
unofficial project and does not use the OpenAI logo.
