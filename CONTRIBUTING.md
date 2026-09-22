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
6. Run `./script/release_check.sh` and report its result. If it has not been run,
   mark it as pending rather than passed.
7. Explain user-visible behavior, security-boundary changes, and test evidence in
   the pull request.

Use the repository Issue forms for bug reports and feature requests, and follow
the pull request template when submitting a change. AI-assisted contributions
are welcome, but contributors remain responsible for reviewing the complete
diff, tests, security impact, and licensing of their submission.

Use small, scoped commits. Match the existing SwiftUI/AppKit ownership split:
SwiftUI owns views and state presentation; AppKit owns status items, popovers,
application appearance, and window lifecycle.

`AppDelegate` owns registration and removal of macOS workspace and system-clock
notification observers and only forwards those events to the main-actor
`AppStore`. `AppStore` owns refresh and single-flight coordination, while the
pure `RefreshPolicy` owns wake freshness and Reset-target decisions. SwiftUI
views must not observe those notifications, schedule Reset requests, or start
requests from relative-time rendering.

`AppStore` keeps the consumed Reset watermark for the current run and changes
a missing pinned selection to Auto only after a fresh successful snapshot.
Cached snapshots and failures preserve preferences. Quota parsing supports
returned 5-hour/Weekly windows, including weekly-only data; do not add plan-name
gates, hard-coded model retirement dates, or an additional dynamic-window schema
as part of this patch. Empty default buckets fall back to available buckets.

`LaunchAtLoginController` owns the stable-install decision. Keep its pure path
helper independent of `SMAppService`: the only accepted App locations are exact
`/Applications/Codex94.app` and `~/Applications/Codex94.app` after the documented
root/leaf symlink handling. Add synthetic-URL tests for every accepted and
rejected path. The settings section observes this controller directly; app
activation refreshes its status. Registration failures use localized feedback,
not raw system errors. Tests inject the narrow service adapter and must not
read or change real Login Items.

### Version 0.2.2 behavior

Version `0.2.2 (13)` was published on 2026-09-20. Its historical download and
source references identify `v0.2.2`; current stable instructions point to the
latest published release. Retain each release's original source and
asset provenance when making later documentation changes. Test and acceptance
evidence remains specific to the revision and artifacts actually checked.

Keep the fourth dual-window layout's bucket preference separate from the
original three layouts' quota selection. Mouse left-click, mouse right-click,
and the configured global shortcut toggle the same popover; opening uses the
existing refresh path. The shortcut is unset by default and must include
Control or Option; Command and Shift may be added. New persistent preferences
are limited to
`dualWindowBucketSelection.v1`, `globalHotKey.v1`, and `notifications.v1`.

Notification policy operates on fresh successful snapshots with an in-memory
baseline and per-window-cycle deduplication. Notifications default off; only an
explicit enable action requests permission. Default remaining thresholds are
20% and 10%, and each can be adjusted or disabled. Extra buckets and recovery
alerts are optional. Do not include email, account IDs, credentials,
raw RPC, or paths in messages. Notification Center retention is system-owned
local storage and must be documented separately from app-owned memory state.

Parse only the authoritative nonnegative integer
`rateLimitResetCredits.availableCount` from the existing quota response.
Missing/null is unavailable, not zero; credit-list length is not a substitute.
Keep the count in memory, preserve it when removing account information, and
exclude it and credit details from cache v2. Do not add a consume operation,
auth/session-file access, history collection, updater, or multi-account work.

### Version 3.1.0 behavior

Keep the floating panel under AppKit ownership with the existing `AppStore`.
Showing, dragging, pinning, hiding, and expanding must not fetch quota or write
its cache; explicit refresh uses the existing manual path. Only pin state and
position receive new preferences. Preserve the existing popover shortcut and
read-only reset-credit behavior. Do not claim cross-Space/fullscreen behavior
from NSPanel flags without native testing.

Custom Token ranges, reported averages/peaks, coverage, and prior-interval
comparison reuse the same prepared snapshot as the chart, table, and exports.
Keep source-day coordinates explicit, missing days distinct from zero, and
percentage comparison unavailable for incomplete intervals or zero baselines.
PNG exports use a dedicated noninteractive chart surface with no identity.
Save/copy actions are user-triggered; tests use only synthetic data and isolated
named pasteboards and must never touch the user's general pasteboard. Check
actual image contents and clipping, not only nonempty data or dimensions.

Version `3.1.0` adds **Floating** as a fourth external UI scenario alongside
Display, Recovery, and Token usage; usage also covers the new date/export
controls without additional RPCs. New runs and visual acceptance are required
before reporting these features as verified. See [architecture rules](docs/ARCHITECTURE.md).

## Development and validation

Use synthetic data for automated tests and published screenshots, and keep
test preferences, caches, and output paths separate from daily app data.

- Use fixed dates and an injected fetcher or explicit fake app-server for
  repeatable tests. Do not import real account credentials into fixtures or
  CI, or publish account identity, real quota, tokens, raw RPC payloads, or
  private paths.
- Test Reset scheduling through injected dates and internal wake/clock handlers;
  do not wait for a real Reset or change system time. Cover the strict
  `resetsAt + 5` boundary, deduplication, earliest target, single-flight
  adjacency, failure consumption, clock rollback after consuming an older Reset,
  wake/clock reconciliation, and shutdown.
- Do not clear or rewrite daily preferences, cache, or authentication data as
  test setup. Fixture cleanup should target only exact test-created resources.
- Use injected hotkey and notification adapters to cover registration failure,
  permission denial, threshold/recovery transitions, baseline suppression, and
  per-cycle deduplication. Automated checks must not register real global
  shortcuts, request system notification permission, or deliver notifications.
  Cover cold/unavailable/zero/cached reset-credit states and absence of credit
  data in saved cache; use only synthetic app-server responses.
- Understand script side effects before running them: `release_check.sh` runs
  hosted tests, owns the single Universal Release build, verifies both
  architecture slices, and drives DMG packaging; `build_and_run.sh` stops named
  Codex94 processes and launches a Debug app; `install.sh` requires running
  copies to be quit, replaces the source App at `~/Applications/Codex94.app`,
  and may launch it. These scripts are not read-only source checks.
- `package_dmg.sh` has the narrow `create` and `verify` interface. It packages
  the exact App supplied by `release_check.sh`; it must not build, call
  `install.sh`, stop/launch a user App, read the home directory, alter
  quarantine, or change system security settings. Use isolated run directories
  for negative tests and never damage or overwrite the formal candidate.
- `package_dmg.sh` owns the complete App verifier; `release_check.sh` compares
  built version/build with the shared project metadata and invokes `create`.
  Preserve source-App and mounted-App verification, not a second verifier or
  another Release build.
- `script/release_metadata.py` owns strict App-target Debug/Release version
  parsing. Local release checks read worktree metadata; CI uses `--revision`
  and requires that commit to equal HEAD. CI outputs drive artifact paths and
  verification parameters. There is no second VERSION file or shell `eval`.
- The source installer holds its destination lock across build/replacement,
  verifies unique staging, and uses inode-checked backup/recovery. Two renames
  permit rollback but are not crash-atomic. Never delete a stale lock, unknown
  destination, or failed-recovery backup automatically. Installer tests source
  its guarded helpers in temporary directories and never run its real entry
  point, install, stop/launch Apps, or change the user's home environment.
- Local `release_check.sh` runs respect the caller's `DEVELOPER_DIR`, or the
  current `xcode-select` choice when it is unset. CI explicitly selects and
  verifies Xcode 16.4; do not hide a toolchain mismatch by overriding it inside
  the script.
- GitHub CI runs the release gate on a macOS runner. Report source
  review, compiled tests, GUI smoke, and screenshot review separately; passing
  CI or producing a nonempty image is not evidence of GUI correctness.

The `Codex94` scheme retains the unit/release gate. The separate `Codex94UI`
scheme uses an external UI test runner. Display, Token usage, and Floating
exercise the unmodified app;
Recovery exercises a temporary instrumented App copy with a read-only focus
probe, marked `instrumentedAUT` and `readOnlyFocusDiagnostic` in the fixture
manifest. Recovery click success applies to that diagnostic copy and does not
replace keyboard activation, AXPress, or hosted tooltip acceptance of the
production binary. The scenarios run on separate fresh GitHub-hosted Macs. The
fixture preparer refuses existing app data and seeds quota-only preferences
and an explicit synthetic executable before any app initialization. It must
not be run on a daily-use desktop; local UI testing needs a separately reviewed
isolation setup, not overridden CI guard variables.

The external runner keeps Xcode's test sandbox. Its extra write access is
limited to the current scenario's synthetic control and artifact directories;
its shared-preference access is read-only for the preseeded app domain. These
permissions are generated before the build and applied only to the UI test
target. The tests verify the signed runner and app permissions before launching
the app; the production app receives no test-only permissions.

Fixture preparation must bind `HEAD` to `GITHUB_SHA`, read the committed app
target's unique Debug/Release version and build from that same revision, and
copy only the explicit build-input allowlist. Do not hard-code an app release
version in runner metadata or temporary-path names; a fixture-schema version is
separate from the app version.

The fixture loads the shared metadata helper by explicit path after validating
its regular tracked blob against the tested commit. It executes those checked
bytes without changing `sys.path`; Python `-I` remains enabled. The helper is
not an App build input and must not broaden the disposable-source allowlist.

Status-item GUI checks distinguish the requested AppKit length from its public
accessibility bounds. A temporary native reference owned by the test process is
measured and removed before app launch; it must distinguish all three legacy
lengths. Validate the additional dual-window layout separately, including
missing windows, cached state, and independence from the legacy quota choice.
No constant padding adjustment or widened tolerance is used to pass a failure.

UI jobs do not enable VoiceOver, change system settings, use real Codex
credentials, or install the app. They upload only explicitly captured app-window
PNGs and curated synthetic summaries with a seven-day retention period. Raw
test result bundles, preferences, caches, environment dumps, and full-screen
captures are not uploaded. Review the images themselves before replacing
documentation screenshots.

Cover fixed and live layout metrics, independent color roles and restoration,
Reset locale/calendar/time-zone behavior and scheduling, all recovery routes,
Overview routing/rendering, button accessibility, and no-fetch/no-cache-write
behavior. About and chart-image copy tests must use isolated named pasteboards and must not
read, clear, or overwrite the user's general pasteboard. Preserve the existing
multi-bucket, freshness, wake, and subprocess regressions. Shared Reset labels
must include the countdown and absolute time; public test data and screenshots
must remain synthetic or redacted.

Report source/static checks, compiled tests, GUI smoke, screenshots, and release
status separately, tied to the actual candidate tree and artifacts. For pull
requests, record the PR head SHA and the exact tested merge SHA/tree separately;
the default merge-ref artifact identifies the tested merge SHA, not the head.
The README
popover images are reviewed synthetic `0.1.8` captures; the Dashboard images
are reviewed synthetic `0.1.9` Overview captures from GitHub-hosted CI, and the
unchanged default menu-bar example remains from `v0.1.7`.
Version 0.1.8 passed the full test/release job, synthetic Display and
click-functional Recovery UI jobs, CodeQL, and separate synthetic A/B GUI
smokes. For `0.1.9 (10)`, PR #11 remains the historical exact-head test,
Display/Recovery UI, Actions/Python/Swift CodeQL, and final App acceptance
record; the README images establish only the reviewed captures they display.
Keyboard activation, AXPress, and hosted tooltip exposure are not claimed as
passed. Keep release-candidate notes under Unreleased without a guessed date.
Before tagging, the maintainer confirms the release date and a reviewed docs
change replaces Unreleased; final-main CI and the DMG must include that change.
Keep stable links on the currently published release until a later release is
public; only then update current stable links and candidate wording. A later
docs-only PR uses the normal authorization/check gates, verifies the changelog
date, and never moves a tag.

A release pull request begins as Draft. Platform-required CI and the additional
fail-closed UI smoke/CodeQL gates must be complete and reviewed. The Universal
candidate needs an exact SHA, two-file allowlist, and signing/attestation
classification; attestation is provenance, not Apple trust. The maintainer must
accept the candidate App built from the exact PR head before Ready; changed
App bytes invalidate that acceptance. Final CI DMG/install acceptance remains
a separate later gate. Ready does not authorize merge. Follow all seven
separate authorization gates in
[docs/RELEASING.md](docs/RELEASING.md): commit/push/Draft PR, Ready, merge,
annotated tag, Draft Release/two assets, maintainer-led install/Open Anyway
acceptance, and Publish. Never infer a later gate from an earlier one.

The outer DMG is unsigned and unnotarized; only the App inside is ad-hoc signed.
Do not recommend deleting quarantine or disabling Gatekeeper. Published assets
follow a manual non-replacement policy, not a platform-enforced guarantee:
hashes, API digests, and attestation detect drift, while GitHub does not prevent
an authorized maintainer from replacing an asset when Immutable Releases is not
enabled.

Do not open a public issue for a suspected vulnerability. Follow
[SECURITY.md](SECURITY.md).


For `3.1.1` behavior, keep the 5-hour column conditional on actual window
availability, not account-plan strings or whether its percentage is zero.
Weekly-only/cold layouts target 480 points, reported dual layouts 680 points;
normal typography, 90/132 heights and screen fitting remain intact. Test cache,
legacy/dual/Auto selection and same-bucket shape changes after deferred store
publication, without adding requests or persisted width preferences.
