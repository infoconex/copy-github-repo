---
title: "GitHub Repository Copy Disk-Space Preflight | CopyGitHubRepo"
description: "Understand CopyGitHubRepo's temporary disk-space preflight, observed workspace lower bound, advisory headroom, failure behavior, and retry semantics before GitHub mutation."
---

# Local temporary-storage preflight

CopyGitHubRepo performs a local temporary-storage preflight before an approved repository-copy plan is allowed to mutate GitHub.

The check is deliberately conservative about what it claims. Repository copy workspace usage depends on Git object packing, working-tree content, Git LFS, filesystem behavior, and operations performed by Git and GitHub CLI. The product therefore does not claim an exact future disk requirement or a universal repository-size limit.

## Planning evidence

While capturing the approved source state, CopyGitHubRepo measures a disposable workspace that mirrors the content mode:

- **Snapshot** uses a depth-1 clone of the approved default branch and includes referenced Git LFS objects when the approved Snapshot uses LFS.
- **FullHistory** uses a bare clone and fetches all reachable Git LFS objects.

The resulting byte count is stored on the approved source state as `PlanningWorkspaceBytes` with evidence kind `ObservedPlanningWorkspaceLowerBound`.

This measurement is an observed lower bound for the approved source state, not a prediction of exact peak disk usage during execution.

## Execution behavior

Immediately after approved source-state revalidation and before repository archive/create mutation, CopyGitHubRepo checks the free space reported for the operating system temporary-storage volume.

The outcomes are:

| Condition | Behavior |
| --- | --- |
| Free space is below `PlanningWorkspaceBytes` | Hard failure with `LocalTempSpaceInsufficient`; no GitHub mutation is started. |
| Free space is at least the observed lower bound but below 2x that value | Advisory warning; execution may continue. |
| Free space is at least 2x the observed lower bound | Preflight passes without a disk-headroom warning. |
| Free-space reporting is unavailable | Advisory/unknown warning; execution may continue. |
| Older/malformed plan has no observed workspace value | Advisory/unknown warning; execution may continue. |

The 2x value is **advisory headroom only**. It is not a supported capacity requirement, SLA, or proof that the operation will fit. Repository characterization shows that Snapshot and especially Git LFS workflows can amplify temporary local storage, which is why the product warns before the observed lower bound becomes tight.

## Privacy and diagnostics

Errors and warnings report byte counts and refer to the local temporary-storage volume generically. They do not include the user's full temporary directory path.

## Failure and retry semantics

`LocalTempSpaceInsufficient` is a pre-mutation failure. The operator may free local temporary storage and retry with a fresh reviewed plan. No archive, destination creation, publication, settings restoration, or protection restoration has started when this error is raised.

If disk exhaustion occurs later despite a successful/advisory preflight, normal preservation-first recovery semantics apply. A successful preflight is not a rollback guarantee and cannot account for unrelated disk consumption that occurs after the check.

## Limitations

The preflight cannot guarantee exact peak disk use because:

- Git packing/compression and filesystem allocation vary;
- Snapshot working-tree and Git LFS operations can require temporary duplication;
- FullHistory object transfer can change with repository state and Git behavior;
- free space can change between the check and later stages;
- other processes can consume the same volume concurrently.

For this reason only a known deficiency below the measured planning workspace is a hard failure. Higher thresholds remain advisory unless future repeatable characterization justifies a supported limit.

## Related material

- [Repository scale and resource characterization](../engineering/scale-characterization.md)
- [Non-functional requirements](../product/non-functional-requirements.md)
- [Troubleshooting and recovery](troubleshooting-recovery.md)
