# Component ownership and reuse

This describes application ownership and reuse constraints maintained in the
published [`3.0.1 (15)` release](https://github.com/DEFY-AN94/codex94/releases/tag/v3.0.1).
Test results and final package acceptance are separate evidence; this document
defines component responsibilities, not a substitute for those records.

| Owner | Responsibility |
| --- | --- |
| `AppDelegate` | Compose the running app, own the status item and popover, retain the Dashboard controller, route mouse/hotkey actions, and register/remove platform observers. Forward wake and clock events to the store. |
| `DashboardWindowController` / `DashboardWindowState` | Own the reusable window lifecycle, size/restoration behavior, visibility, and selected page. Opening a page must not recreate application services. |
| `AppStore` | Own quota state, cache writes, selection reconciliation, notification observations, and the existing single-flight/background/Reset coordination. Coordinate source-context changes with child features. |
| `TokenUsageStore` | Own on-demand aggregate statistics and their request lifetime. Replace snapshots, reject obsolete results, and manage retired clients without coupling statistics failures to quota status. |
| `AppUpdateController` | Own the explicit GitHub metadata check and its UI state. It does not poll, download, install, or share quota authentication. |
| Platform and transport services | Own Codex subprocesses, notification delivery, hotkey registration, and the fixed update HTTP request. Keep bounded process-group termination in its existing service. |
| Pure models and support types | Own parsing, date/count rules, selection projections, chart preparation, formatting inputs, and scheduling decisions without starting I/O. |

## Rules for focused reuse

- Reuse a function when the field semantics match. `SourceDay` and
  `StrictJSONInteger` belong in `Support/ServiceValues.swift`, not in a
  Token-specific model imported by the quota parser. Missing is not zero;
  do not impose nonnegative-count rules on quota percentages that intentionally
  preserve extreme inputs before display clamping.
- A request's single-flight status and its source context are separate facts.
  Results from an obsolete executable/identity context must not update state,
  cache, preferences, notifications, or another feature's snapshot. Preserve
  queue completion so the current preference-triggered request can still run.
- Keep quota, Token usage, and update-check lifecycles separate. Their triggers,
  persistence, errors, and cancellation rules differ; shared task syntax alone
  is not a reason to replace them with one generic store.
- Project chart dates and aggregates from a snapshot/range once, then reuse
  them for marks, selection, tables, and CSV. Reuse formatting within an explicit
  locale/calendar/time-zone context; do not share mutable formatter state across
  unrelated actors or silently change the service's date interpretation.
- Views receive state and narrow actions. Rendering relative time, changing
  style/range, or navigating recovery pages must not start quota requests or
  write its cache. AppKit window/input ownership stays at the platform boundary.
- Make the dependencies needed by a test injectable. Use controlled fetchers to
  pause old and new responses independently, and fake notification/update/input
  services instead of real accounts, system registration, or browser actions.
- Reset may retire a Token client in the background, but application shutdown
  must still drain owned clients with the existing bounded termination policy.
  Moving ownership must not weaken process-group cleanup or ignore old results.

## Validation seams

`AppStoreTests` covers quota ordering, cache/selection effects, wake/Reset
coordination, and shutdown. `TokenUsageStoreTests` covers request generations
and retired clients. Parser and presentation tests cover strict values, dates,
gaps, chart projections, and CSV. External synthetic UI tests cover actual
window/navigation interactions separately from these model tests.

The release gate builds the Universal App once; the DMG packager verifies its
complete payload and signing boundary. The source installer owns its lock,
staging, and rollback. Share small validation helpers where appropriate rather
than duplicating those ownership boundaries. See [CONTRIBUTING.md](../CONTRIBUTING.md)
and [the release workflow](RELEASING.md) for required evidence and distribution rules.
