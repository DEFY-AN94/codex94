# README screenshot provenance

## Token statistics captures

These images are unedited copies of reviewed synthetic UI artifacts. They show
the `0.3.0 (14)` candidate and do not contain real account or usage data.

- CI run: [35521556558](https://github.com/DEFY-AN94/codex94/actions/runs/35521556558),
  usage scenario on a fresh GitHub-hosted macOS runner.
- Pull request: [#21](https://github.com/DEFY-AN94/codex94/pull/21).
- PR head: `6e499eb733f8a88053d263e0878f2ce89914aba3`.
- Tested merge / artifact `sourceRevision`:
  `13fb4730efb1131a64d312a27a877759b7c752df`.
- Artifact version/build: `0.3.0` / `14`.
- Artifact App binary SHA-256:
  `88a7df1ea873e7ee13bdbf08df91c04a7faa576638cf3617fc5d00e3184f9fb9`.
- The artifact reports `instrumentedAUT: false`,
  `sourceData: fixed-synthetic-account-aggregates`, and
  `identityRequestsAllowed: false`.

| Repository file | Original CI filename | Content |
| --- | --- | --- |
| `token-usage-bar-0.3.0-en.png` | `usage-seven-days-en.png` | English, dark appearance, seven-day bar-chart viewport |
| `token-usage-line-0.3.0-en.png` | `usage-line-seven-days-en.png` | English, dark appearance, the same seven days as a line chart |
| `token-usage-overview-0.3.0-zh-Hans.png` | `usage-complete-zh-Hans.png` | Simplified Chinese, light appearance, summary-card viewport |

The fixture supplies 35 daily records dated **2033-04-14 through 2033-05-18**.
The seven-day screenshots show **2033-05-12 through 2033-05-18**. May 15 is an
explicit reported zero, so the line correctly touches the baseline on that
day. It is not an omitted record or a demonstration of filling missing dates.
Any visible update timestamp records the CI fetch time, not the date of usage.
The screenshots capture scrolled app viewports, not the entire statistics page.

Byte identity with the downloaded CI originals was checked after copying:

```text
164254b2a6ee74e06018faa6ad9633e7f1d014abcfee5723854afad2859c3c2e  token-usage-bar-0.3.0-en.png
d75f1cae57d92f25e3a5506f9d4706a467e4e245adb0874745246b3a889d3da8  token-usage-line-0.3.0-en.png
c44028ec46909807edbefaa18788eef57faab145e056f37c2ef2103c543c5da5  token-usage-overview-0.3.0-zh-Hans.png
```

The PR head, tested merge, and any later release/documentation commit are
different identities. Retaining these images in a later docs-only commit does
not change their capture provenance or certify a newly built binary. Updated
application code requires its own UI evidence; release and signing acceptance
remain separate from this screenshot record.

## Retained historical quota captures

The pre-existing files below were not replaced or edited in this update. Their
version labels preserve the provenance previously recorded in both READMEs:

| Files | Original documented version |
| --- | --- |
| `menu-bar.png` | `v0.1.7` default menu-bar sample |
| `popover-en.png`, `popover-zh-Hans.png` | Reviewed synthetic `0.1.8` popover captures |
| `dashboard-en.png`, `dashboard-zh-Hans.png` | Reviewed synthetic `0.1.9` Overview captures from GitHub-hosted CI |

These historical files do not demonstrate the `0.2.2` controls or `0.3.0`
statistics/update features. Their original exact run identifiers are not
reconstructed or inferred here.
