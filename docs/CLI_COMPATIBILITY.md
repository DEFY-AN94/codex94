# CLI compatibility evidence

This document separates synthetic format coverage from real CLI acceptance.
The initial catalog was prepared against the 4.1.8 candidate in
[PR #71](https://github.com/DEFY-AN94/codex94/pull/71), head
`0c2343981c9b5858e575048d213f51f6230fd1e4`. It does not expand the supported
CLI version range or change any production parser, request deadline, input,
configuration, or process-cleanup rule.

## What the catalog tests

The test-only catalog is
[`Codex94Tests/Fixtures/CLICompatibility/catalog.json`](../Codex94Tests/Fixtures/CLICompatibility/catalog.json).
Its 13 explicitly listed Claude fixtures contain only authored synthetic data.
The source-test references identify the earlier regression scenario that
informed each fixture; a newly added expectation can be stricter or more focused
than that source test. No fixture is a captured account session.

[`CLICompatibilityReplayTests.swift`](../Codex94Tests/CLICompatibilityReplayTests.swift)
passes the bytes to the existing production `ClaudeUsageScreen` and
`ClaudeTerminalQueries` implementations:

| Fixture | Production behavior checked |
| --- | --- |
| `shortcut-ready` | The existing shortcut hint is recognized as a ready prompt. |
| `framed-ready` | The complete framed prompt accepts the known separated footer hint. |
| `unknown-prompt` | A version banner and selection marker alone do not establish readiness. |
| `weekly-only` | A weekly report retains its exact percentage and fixed UTC reset without inventing a five-hour window. |
| `fractional-shared-windows` | Fractional shared windows and reset dates are retained; a model-scoped heading does not create another shared window. |
| `cleared-stale-window` | Clear-screen output removes an older quota window before the replacement is parsed. |
| `refreshing-panel` | The refreshing predicate remains true even when the raw report parser can decode visible cached percentages. |
| `synchronized-frame` | A screen stays incomplete until its synchronized update ends. |
| `utf8-boundary` | Partial UTF-8 bytes mark the screen incomplete and the completed character restores completeness. |
| `control-string-boundary` | An OSC sequence remains incomplete until its full terminator arrives. |
| `open-synchronized-update` | A later open update cannot reuse an earlier frame's completeness. |
| `invalid-shared-values` | Out-of-range and nonnumeric percentages yield no shared report. |
| `terminal-query-boundaries` | Every two-chunk split, bytewise delivery and fixed-seed delivery preserve the exact reply multiplicities; later empty or ordinary text does not repeat replies. |

Declared incomplete checkpoints are also replayed after an already recognized
prompt. Earlier readiness must not make an unfinished encoding or terminal frame
complete. Query replies are compared by multiplicity, because the production
responder groups query types within a received batch; this test does not impose
a new reply-ordering contract.

Screen fixtures also run with fixed interior cuts and three deterministic
SplitMix64 seeds (`0x94`, `0x418`, `0x420`), producing chunks of 1–31 bytes.
Screen delivery retains every declared event boundary so its completeness
checkpoint is still asserted, including checkpoints inside UTF-8 and terminal
control sequences. Each accumulated prefix reaches the production snapshot
parser; the final report must retain the exact expected windows. Query replay
also allows seeded chunks to cross declared event boundaries and checks that
reply multiplicities remain unchanged. Failures identify the fixture and seed
or cut strategy; neither replay uses system randomness. These are finite
partitions of the authored output, not exhaustive arbitrary-stream coverage.

The refreshing fixture intentionally checks both raw percentage decoding and
the refreshing marker. It does **not** claim those percentages are an accepted
fresh report. The client's acceptance, input and settling gates remain in
[`ClaudeQuotaBackendTests.swift`](../Codex94Tests/ClaudeQuotaBackendTests.swift),
including the existing fake CLI/PTY, continuous redraw, trust, cancellation,
timeout and process-group cleanup tests. This catalog does not launch a CLI or
simulate their timing.

The named backend tests remain the production client evidence for
those boundaries; record their actual macOS result rather than treating this
table as a passing result:

| Boundary | `ClaudeQuotaBackendTests` test |
| --- | --- |
| Terminal handshake before recognized input | `testCLIHandshakeGatesReadyOnDeviceAttributesVersionAndCursorReplies` |
| Continuous repaint with a stable single-window report | `testContinuousReadyAndUsageRedrawsReturnSingleWeeklyWindow` and `testContinuousUsageRedrawsReturnStableWeeklyWindow` |
| Refreshing cached values do not complete the read | `testRefreshingUsageFramesWaitForUpdatedWindows` and `testContinuouslyRefreshingUsagePanelTimesOutWithoutReturningCachedWindows` |
| Continuous refreshing retains the original deadline | `testContinuouslyRedrawnRefreshingPanelKeepsOriginalDeadline` |
| Unknown startup does not authorize input | `testContinuouslyRedrawnUnknownStartupNeverReceivesInput` |
| Partial synchronized frames cannot authorize input or return interim quota | `testIncompleteSynchronizedFramesNeitherSendUsageNorReturnInterimQuota` |
| Login, onboarding and unowned trust do not receive usage/confirmation | `testOnboardingLoginAndUnownedTrustNeverReceiveUsageOrConfirmation` |
| Exact owned trust path and selected option | `testTrustNeedsExactOwnedDirectoryAndAnExplicitSelectedOption` |
| Cancellation cleans the owned process group | `testCancellingCLIReadStopsItsOwnedProcessGroup` |
| Cancellation after the fake process receives `/usage` cleans its parent and child | `testCancellingAfterUsageWasSentStopsTheOwnedProcessGroup` |
| Cancellation before invocation launches neither the version command nor usage session | `testCancellationBeforeFetchStartsNeverLaunchesVersionOrUsage` |
| More than 1 MiB of actual PTY output is rejected and the owned process group is cleaned up | `testCLIOutputAboveOneMiBIsRejectedAndItsProcessGroupIsCleanedUp` |
| A fake process exiting before a report yields `unavailable` | `testCLIExitingBeforeAReportIsAnUnavailableRead` |
| Silent process respects the injected deadline and cleanup | `testSilentCLIHonorsInjectedShortDeadlineAndCleansUp` |

The output-cap test generates 17 × 64 KiB of synthetic bytes in a fake process;
it does not enlarge the fixture catalog or production cap. The cancellation
tests use an invocation gate or an observed process marker written after
`/usage` was received. They do not guess the cancellation phase using a fixed
delay. Started reads assert one final diagnostic with the expected result; a
task cancelled before `fetch` starts has no CLI read and emits no diagnostic.
Process-marker and cleanup checks use bounded condition polling. These tests
exercise the production reader and lifecycle with temporary shell scripts,
without invoking an installed Claude CLI or touching an account.

Exact timing boundaries have a separate production path:
[`ClaudeUsageReadTiming.swift`](../Codex94/Support/ClaudeUsageReadTiming.swift)
is called by the real `ClaudeCLIUsageClient` reader, and
[`ClaudeUsageReadTimingTests.swift`](../Codex94Tests/ClaudeUsageReadTimingTests.swift)
supplies explicit monotonic `Duration` values without sleeping. The tests cover
the 100 ms evaluation cadence, 200 ms unchanged-action interval, 1 second
unchanged-window interval, candidate resets, and the exclusive 20 second
default usage deadline. Repainting cannot move that deadline. At its exact
boundary neither a newly stable action nor a report may complete.

The usage clock begins after the PTY launches; the separate version-check and
cleanup budgets are unchanged. This helper does not parse frames, choose input,
or replace real I/O. The existing fake CLI tests still exercise its integration
with the actual reader and process lifecycle. The split-frame reset-date test
also injects a fixed wall clock into the reader; production defaults to `Date()`
while the usage deadline continues to use `ContinuousClock`.

Codex JSON-RPC and executable discovery are not yet represented in this catalog.
Their existing production-path coverage remains in
[`AppServerClientTests.swift`](../Codex94Tests/AppServerClientTests.swift) and
[`ExecutableLocatorTests.swift`](../Codex94Tests/ExecutableLocatorTests.swift).
There is no common interpreter combining JSON-RPC with the Claude terminal.

## Fixture schema v1

`catalog.json` contains `schemaVersion: 1` and the ordered relative paths of all
fixtures. Each path must match `claude/<lowercase-slug>.json`. Unlisted JSON files,
duplicate paths/IDs, symlinks, path escapes, unknown keys, duplicate JSON keys and
non-finite numbers are rejected by the standard-library validator.

Every fixture has:

| Field | Meaning |
| --- | --- |
| `schemaVersion`, `id`, `provider`, `kind`, `scenario` | Version, stable names, `claude`, and either `screen` or `queries`. |
| `provenance` | `kind: synthetic`, source-test references and a short explanation of the authored data. |
| `fixtureDeclaredVersion` | A simulated version string; it is not a measured executable version. |
| `referenceTime`, `locale`, `timezone` | Fixed UTC wall time, `en_US`, and `UTC`. All reset strings in this catalog state UTC explicitly. |
| `events` | Ordered `output` events, each containing exactly one UTF-8 `text` string or a `bytes` array of integers from 0 to 255. Screen events may assert `expectedComplete`. |
| `expected` | For a complete screen: readiness, refreshing and exact shared windows. For an incomplete screen: only `complete: false`. For queries: exact expected replies. |

An empty expected window list means production report parsing must throw
`ClaudeQuotaIssue.noData`; it never means zero usage. Each expected reset is a
strict UTC timestamp or `null`. The parser receives the fixture's reference
date explicitly, without changing the system clock or global time zone.

Version 1 intentionally has no executable script, arbitrary command, virtual
timer, input action, cancellation or process-result event. Those are outside this
parser-only catalog. Future coverage should add a separately reviewed schema
change rather than pretend output replay establishes process or timing behavior.

Bounds are 64 fixture files, 256 events per fixture, 256 KiB per JSON file,
1 MiB for the catalog and all fixture JSON bytes together, and 64 KiB of decoded
output per fixture. These are test-asset limits and do not alter the production
reader's 1 MiB output cap. The backend output-cap test generates its own
synthetic bytes instead of storing oversized transcripts in this catalog.

## Validation and resource isolation

Run the portable schema checks from the repository root:

```sh
python3 -I script/cli_compatibility_fixtures.py
python3 -I script/tests/test_cli_compatibility_fixtures.py
```

The Python helper validates data and metadata only. It does not reimplement the
Swift parser, execute fixture text, read account configuration, or prove runtime
compatibility. Its errors use fixed categories without echoing fixture payloads.

The `CLICompatibility` directory is a folder resource of `Codex94Tests` only.
The Swift loader uses `Bundle(for: CLICompatibilityReplayTests.self)` and expects
`CLICompatibility/catalog.json` plus the exact listed child paths. Resources
must not be copied into the production App. Recovery's disposable build input
allowlist must enumerate any required tracked fixture files; no directory-wide
copy or relaxed environment guard is needed. Fixtures are not release assets or
UI artifact attachments.

The hosted XCTest suite checks the test-bundle catalog lookup and the absence
of both the fixture directory and a flattened catalog in `Bundle.main` App
resources. It checks those exact paths without recursively scanning the App.

On macOS, run `CLICompatibilityReplayTests`, `ClaudeUsageReadTimingTests`, and
the affected existing backend and lifecycle suites, then the repository release
gate. A successful Python run does
not establish that Swift compiled, XCTest passed, or the UI behaved correctly.
The catalog itself supplies no timing, process-cleanup, screenshot, installation
or real-account acceptance evidence.

## Recording evidence

Keep these evidence categories separate in the PR and release record:

| Evidence | Required identity | Meaning |
| --- | --- | --- |
| Synthetic schema check | Source revision, command and result | Fixture data conforms to the declared schema. |
| Production parser replay | Source revision, Xcode/macOS and XCTest result | The compiled production parsing paths accepted/rejected these synthetic cases. |
| Production timing helper | Source revision, Xcode/macOS and XCTest result | Exact elapsed-time boundaries and candidate resets passed without relying on OS scheduling. |
| Fake CLI integration | Source revision, Xcode/macOS and focused/release test result | The identified synthetic process and timing cases passed. |
| Isolated UI smoke | Tested revision, scenario, App version/build and reviewed screenshots | The recorded fake-provider UI interaction passed within that fixture's limits. |
| Real CLI acceptance | Actual CLI version, macOS, candidate identity, date and performed operations | Only the explicitly recorded real-client operations were accepted. |

No real CLI acceptance was performed to author this catalog. Its declared
`2.1.286 (Claude Code)` strings, like the UI fixture's `2.1.999`, do not prove
compatibility with those actual releases. A later single-version acceptance
must not be generalized to an untested version range. Record pending macOS
tests and absent real-client acceptance explicitly; never infer them from the
presence of these files.
