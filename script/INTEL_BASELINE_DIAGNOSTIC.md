# Temporary released-product startup comparison

This branch is a diagnostic experiment only. It is not part of PR #75 or the
4.3.0 product, and must not be merged or released.

The compiled product directories `Codex94/` and `Codex94.xcodeproj/` are restored
exactly from released 4.2.0 (33), revision
`c13f886151b5932518352a3b92caafb71dbbf44f`. The workflow verifies their empty diff
against that immutable revision before building. It builds only the native Intel
Debug App with Xcode 16.4; it does not compile or execute XCTest targets.

The current debug branch's Providers fixture remains synthetic and retains its
strict hosted-runner, existing-data, fake-executable and source-revision checks.
Its manifest `sourceRevision` identifies this diagnostic branch commit, not the
released product revision. `normalProductSourceModified: false` means the fixture
did not instrument the App; the separate Git equality check establishes the
released product's source identity. Recovery is not invoked, so its build-input
allowlist does not need a baseline exception.

The unchanged guarded diagnostic directly launches that exact signed candidate
with `--show-popover`, fake-only provider paths and the prepared synthetic App
preferences. It observes up to five seconds, records only bounded categories and
approved symbolic fields, and cleans up only its own newly launched process.
No raw process output or crash report is uploaded. The final verdict fails if the
diagnostic is blocked or the App does not survive the observation interval.

This experiment compares startup with the 4.3.0 Intel diagnostic run
`43479938964` at `2a7212cf6c1d9ed7e586eaaff7402039e42b274d`. A repeated Metal
category plus SIGABRT would establish that this failure also affects the released
App source on the tested hosted Intel image. It would not establish the exact
faulting stack, behavior on all Intel Macs, successful UI interactions, or release
acceptance. Each hosted job receives a fresh VM, not the same physical machine.
