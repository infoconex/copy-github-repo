---
title: "CopyGitHubRepo Scale Characterization – Repository Size and Resource Evidence"
description: "Review CopyGitHubRepo repository scale and resource characterization for history, refs, content, Git LFS, temporary storage, performance observations, and release-readiness interpretation."
---

# Repository scale and resource characterization

CopyGitHubRepo does not claim a hard maximum repository size, history depth, branch/tag count, Git LFS volume, memory limit, disk requirement, or completion-time SLA without repeatable evidence. This document defines how scale observations are collected and how they may be used in release decisions.

The characterization process is intentionally separate from deterministic blocking CI. Variable timing and resource observations are evidence, not pass/fail gates, unless a future release explicitly adopts and enforces a threshold.

## Evidence labels

Use these labels consistently:

- **Observed** — measured in one recorded environment and fixture.
- **Characterized** — repeated enough across representative fixtures/environments to support an engineering conclusion.
- **Supported limit** — an intentionally adopted product boundary with documented rationale and enforcement or explicit user-facing validation.
- **Unknown** — not yet measured or not reproducible enough to characterize.

Do not convert an observed value directly into a supported limit.

## Characterization dimensions

Representative fixtures should vary the dimensions that materially affect Snapshot and FullHistory behavior:

| Dimension | Why it matters |
| --- | --- |
| Working-tree/content bytes | Snapshot workspace creation and publication are content-volume sensitive. |
| Commit count/history depth | FullHistory clone, verification, and ref processing can scale with history. |
| Branch count | FullHistory ref discovery, publication, verification, and GitHub API pagination are affected. |
| Tag count | FullHistory ref discovery, publication, verification, and pagination are affected. |
| Git object database size | Better represents compressed repository history than working-tree size alone. |
| Git LFS object count and bytes | LFS introduces separate object transfer, local storage, and failure modes. |
| File count | Many small files can behave differently from fewer large files at the same byte size. |
| GitHub API result count | Repository metadata/settings/ref discovery can cross pagination boundaries independent of Git object size. |

## Recommended fixture families

These profiles are characterization starting points, not product limits. Adjust them when the observed system behavior suggests a more useful boundary.

| Profile | Commits | Branches | Tags | Regular content | LFS | Primary purpose |
| --- | ---: | ---: | ---: | --- | --- | --- |
| Baseline | 100 | 10 | 25 | 20 x 16 KiB | none | Establish a low-cost reference point. |
| History-heavy | 1,000 | 20 | 100 | 20 x 16 KiB | none | Exercise FullHistory history traversal and mirror size. |
| Ref-heavy | 250 | 200 | 250 | 20 x 16 KiB | none | Exercise large branch/tag sets and pagination-sensitive behavior. |
| Content-heavy | 100 | 10 | 25 | 100 x 2 MiB | none | Exercise Snapshot workspace/content-volume behavior. |
| LFS-heavy | 100 | 10 | 25 | 20 x 16 KiB | 50 x 10 MiB | Exercise local LFS storage and transfer-sensitive behavior. |
| Combined | 1,000 | 200 | 250 | 100 x 2 MiB | 50 x 10 MiB | Stress combined dimensions only after smaller profiles are understood. |

The Combined profile should not be the first run. Start with individual dimensions so regressions and resource drivers remain attributable.

## Deterministic fixture generation

`build/New-ScaleCharacterizationFixture.ps1` creates synthetic local Git repositories with configurable:

- commit count;
- branch count;
- tag count;
- tracked file count and size; and
- Git LFS file count and size.

Example baseline fixture:

```powershell
./build/New-ScaleCharacterizationFixture.ps1 `
    -Path ./artifacts/scale/baseline `
    -CommitCount 100 `
    -BranchCount 10 `
    -TagCount 25 `
    -TrackedFileCount 20 `
    -FileSizeKiB 16
```

Example LFS fixture:

```powershell
./build/New-ScaleCharacterizationFixture.ps1 `
    -Path ./artifacts/scale/lfs-heavy `
    -CommitCount 100 `
    -BranchCount 10 `
    -TagCount 25 `
    -TrackedFileCount 20 `
    -FileSizeKiB 16 `
    -LfsFileCount 50 `
    -LfsFileSizeKiB 10240
```

The generator uses deterministic byte patterns so repeated fixtures with the same parameters do not depend on random input. LFS profiles require Git LFS to be installed. Automatic Git maintenance is disabled inside generated fixtures so characterization does not race background object maintenance while creating large synthetic histories.

## Local substrate measurement

`build/Measure-ScaleCharacterization.ps1` measures local Git behavior separately from GitHub/network variability. It records:

- OS, architecture, PowerShell, Git, and Git LFS versions;
- commit, branch, and tag counts;
- working-tree, `.git`, and local LFS object bytes;
- `git count-objects -vH` output;
- elapsed time and workspace bytes for a shallow Snapshot-like local clone;
- elapsed time and workspace bytes for a FullHistory mirror clone; and
- local temporary-workspace/free-space observations.

Example:

```powershell
./build/Measure-ScaleCharacterization.ps1 `
    -FixturePath ./artifacts/scale/baseline `
    -OutputPath ./artifacts/scale/results/baseline.json
```

This measurement deliberately reports `CharacterizationKind = LocalGitSubstrate`, `IsReleaseSla = false`, `IsBlockingCiEvidence = false`, and `IncludesGitHubNetworkOrApiLatency = false`.

## Automated evidence collection

`.github/workflows/scale-characterization.yml` provides a repeatable GitHub-hosted execution environment for the representative local profiles. It is intentionally evidence-producing rather than a release-blocking performance gate.

On relevant changes to the characterization workflow, harness, documentation, or smoke test, the workflow runs these profiles on `ubuntu-latest`:

- Baseline;
- History-heavy;
- Ref-heavy;
- Content-heavy; and
- LFS-heavy.

The workflow records each profile's fixture metadata and local Git substrate measurement as JSON artifacts retained for 30 days, and writes a concise observation table into the GitHub Actions job summary. The artifacts retain the exact environment and raw byte/timing observations needed for later comparison.

The Combined profile is deliberately opt-in through `workflow_dispatch` with `include_combined=true`. A normal push does not execute it. This preserves the documented rule that individual resource dimensions should be understood before combined stress is interpreted.

Workflow results remain **Observed** evidence unless repeated runs and environments justify a stronger **Characterized** conclusion. A passing workflow does not establish a supported maximum or SLA.

## Recorded local observations — 2026-08-18

GitHub Actions run `32097057898` on commit `281b9267ce841cc78176553e1337d89bc691432b` completed all five individual-dimension profiles successfully on Ubuntu 24.04.4 LTS, X64, PowerShell 7.6.4, Git 2.54.0, and Git LFS 3.7.1. The Combined profile remained skipped as designed.

| Profile | Working tree | `.git` | LFS objects | Snapshot-like clone | Snapshot workspace | FullHistory mirror | FullHistory workspace |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Baseline | 329,066 B | 122,410 B | 0 B | 36 ms | 363,033 B | 25 ms | 80,446 B |
| History-heavy | 341,666 B | 1,765,618 B | 0 B | 31 ms | 377,503 B | 42 ms | 1,371,049 B |
| Ref-heavy | 331,166 B | 333,984 B | 0 B | 52 ms | 365,483 B | 54 ms | 208,031 B |
| Content-heavy | 209,716,586 B | 1,768,482 B | 0 B | 1,856 ms | 209,798,903 B | 35 ms | 1,719,481 B |
| LFS-heavy | 524,617,112 B | 524,430,746 B | 524,288,000 B | 1,242 ms | 1,048,954,178 B | 34 ms | 94,693 B |

Observed conclusions from this run:

- content volume is the dominant driver for Snapshot-like workspace size and elapsed local clone time;
- history depth materially increases the FullHistory mirror workspace while remaining small compared with large working-tree/LFS content in this fixture set;
- large branch/tag counts did not establish a local Git resource boundary in the tested ref-heavy fixture;
- the LFS-heavy profile showed the strongest local storage amplification: approximately 500 MiB of LFS objects resulted in approximately 1.05 GB of Snapshot-like workspace; and
- no defensible hard repository-size, history-depth, ref-count, LFS-volume, completion-time, or memory limit was established by these observations.

These are **Observed** values for the recorded hosted runner image, not an SLA or supported maximum.

## End-to-end GitHub characterization

Local measurements do not prove end-to-end CopyGitHubRepo performance. Separate live runs are required for actual Snapshot and FullHistory execution because GitHub API latency, authentication, service throttling, repository creation, Git/LFS transport, settings restoration, and protection restoration are external variables.

For every live characterization run, record at least:

- exact CopyGitHubRepo commit/version;
- source fixture profile and exact generator parameters;
- destination repository and whether it is disposable test infrastructure;
- Snapshot or FullHistory mode;
- OS/architecture/PowerShell/Git/Git LFS/GitHub CLI versions;
- start/end time and total elapsed time;
- stage-level timings where available;
- local temp/workspace disk consumption;
- observable process/memory measurements where the platform makes them practical and repeatable;
- GitHub API/service interruptions, retries, or rate-limit evidence;
- verification result;
- cleanup outcome; and
- any partial-mutation/recovery evidence.

Do not mix failed service/network runs with local algorithmic timing conclusions without labeling the external cause.

`build/Invoke-LiveScaleCharacterization.ps1` wraps the existing authenticated Snapshot and FullHistory E2E harnesses and records a single evidence JSON file. The underlying harnesses require GitHub CLI authentication with repository-create access and `delete_repo` so temporary repositories created under protected run-specific prefixes can be cleaned up automatically.

## Recorded live GitHub observation — 2026-08-18

A live characterization was executed from Windows against GitHub.com on repository commit `6d69a698d1922511336f3019c4f5f781207e3a7f`.

Environment:

- Microsoft Windows 10.0.26200, X64;
- PowerShell 7.6.4;
- Git 2.45.2.windows.1;
- Git LFS 3.5.1;
- GitHub CLI 2.92.0.

Results:

| Mode | Result | Elapsed time | Evidence |
| --- | --- | ---: | --- |
| Snapshot | Success | 41,458 ms | Existing Snapshot E2E harness completed and cleaned its disposable repositories. |
| FullHistory | Success | 74,312 ms | Existing FullHistory E2E harness completed and cleaned its disposable repositories. |

The elapsed times include GitHub service/network activity, repository creation, publication, verification, and cleanup variability. They are **Observed**, not a completion-time SLA. The live wrapper explicitly records `IncludesGitHubNetworkOrApiLatency = true`, `IsReleaseSla = false`, and `IsBlockingCiEvidence = false`.

Memory behavior remains **Unknown** because the current measurement does not reliably capture peak usage across the PowerShell process and child `git`, `git-lfs`, and `gh` processes.

The live run did not establish any additional unsupported or high-risk scale boundary. It did confirm that both supported content modes completed their existing authenticated end-to-end verification and cleanup paths in the recorded environment.

## Pagination characterization

The deterministic test suite already exercises pagination beyond a single 100-item page for relevant GitHub state. Scale characterization should additionally record live or fixture-backed observations for larger branch/tag/result sets when practical.

A pagination test passing establishes correctness for that scenario; it does not establish acceptable latency or resource use for arbitrary result counts.

## Resource and memory observations

Disk use should be recorded in bytes and, where useful, human-readable units. Record both source fixture size and temporary workspace consumption because Snapshot, FullHistory, and LFS can have different local amplification factors.

Memory measurements are only useful when the collection method is documented. Prefer process peak-working-set or equivalent OS-level measurements when available. If the measurement method cannot reliably include child `git`, `gh`, or `git-lfs` processes, label memory behavior **Unknown** rather than reporting PowerShell process memory as whole-operation memory.

## How results affect release readiness

A characterization observation should become a release-blocking limit only when all of the following are true:

1. the boundary is material to safe or predictable user operation;
2. the measurement is reproducible enough to defend;
3. the product can detect or document the boundary meaningfully;
4. the threshold has an explicit release/product decision behind it; and
5. tests or preflight behavior enforce the adopted contract where practical.

Otherwise retain the result as observed/characterized guidance and feed material risks into [`release-readiness.md`](../release/release-readiness.md), [`quality-strategy.md`](quality-strategy.md), and the canonical resilience scenarios in [`product-model.md`](../product/product-model.md).

## Release consequence

No hard repository-size, history-depth, branch/tag-count, LFS-volume, memory, disk, or completion-time limit is adopted from this characterization. The evidence instead supports treating temporary disk capacity as a preflight/resilience concern, especially for Snapshot and Git LFS workloads. The implemented local-resource preflight uses the observed planning workspace as a conservative lower bound and treats additional headroom as advisory rather than a universal capacity rule. Resource exhaustion remains a canonical resilience scenario in the product model.

## Current status

Representative local and live GitHub characterization has been recorded. The five individual local fixture families completed successfully in GitHub Actions, and authenticated Snapshot and FullHistory live E2E baselines both completed successfully against GitHub.com from the documented Windows environment.

**No supported maximum size, history depth, branch/tag count, LFS volume, memory use, disk requirement, or completion-time SLA is adopted from this work.** Memory remains explicitly **Unknown**. The principal actionable finding is local temporary-storage amplification for content-heavy and especially LFS-heavy Snapshot workloads; that consequence is addressed by the documented preflight/resilience model and retained in the canonical resilience scenarios.

## Related documentation

- Non-functional requirements: [`non-functional-requirements.md`](../product/non-functional-requirements.md)
- Local resource preflight: [`local-resource-preflight.md`](../user/local-resource-preflight.md)
- Product resilience scenarios: [`product-model.md`](../product/product-model.md)
- GitHub API retry policy: [`github-api-retry-policy.md`](github-api-retry-policy.md)
- Troubleshooting and recovery: [`troubleshooting-recovery.md`](../user/troubleshooting-recovery.md)
- Quality strategy: [`quality-strategy.md`](quality-strategy.md)
