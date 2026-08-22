# Product contract

## Purpose

Copy GitHub Repository safely publishes or copies GitHub repositories while preserving the source or archived original and producing evidence that the selected content and supported configuration were reproduced correctly.

The default use case is a **clean Snapshot publication**: publish the approved current state of a developed repository into a destination whose Git history begins with one unrelated root commit. `FullHistory` is the explicit **history-preserving copy** alternative.

The stable public content-mode values are exactly `Snapshot` and `FullHistory`.

## Defaults

- PowerShell 7.4 or newer
- GitHub.com only in v0.1.0
- GitHub CLI authentication
- `Snapshot` content mode
- destination visibility inherited from the source
- supported repository settings restored after content verification
- transferable repository protection restored last
- guided human experience through `Start-CopyGitHubRepositoryWizard`
- structured automation through `Copy-GitHubRepository`
- Markdown and JSON reporting

## Canonical content terminology

`Snapshot` is clean current-state publication. The approved source default-branch tree becomes one new unrelated destination root commit. Prior commit ancestry, other branches, and tags are not published.

`FullHistory` is history-preserving copy. Approved ordinary branches, tags, reachable commits, the default branch, and reachable Git LFS objects are preserved.

Human-facing plans and wizard text use **repository copy plan**, **Snapshot**, **FullHistory**, **archive**, **replacement**, **source**, and **destination** consistently. Internal/debug representations are not user-facing status text.

## Immutable approved source state

Planning is not merely a preview of command parameters. Every executable plan captures immutable source-state evidence and execution is bound to that reviewed evidence.

Snapshot plans capture:

- source repository name and immutable GitHub ID/node ID when available;
- source default branch;
- exact source commit SHA;
- exact source tree SHA;
- Snapshot Git LFS pointer/object-availability evidence; and
- capture time.

FullHistory plans capture:

- source repository name and immutable GitHub ID/node ID when available;
- source default branch;
- exact ordinary branch/tag ref targets;
- reachable commit count;
- branch-tip tree identities;
- reachable Git LFS availability; and
- capture time.

Immediately before the first GitHub mutation, execution re-checks the source against the approved state. Drift terminates with `SourceStateChangedSincePlanning`; destination creation or rename does not proceed from that stale plan. The user or automation must create and review a new plan.

The copy engine also checks its cloned source workspace against the approved state before publishing destination content. Verification then compares the destination with the approved/copied evidence rather than rereading a source branch or ref set that may have moved after publication.

Structured results and recovery/provenance evidence distinguish the **approved/planned source state** from the **actual copied source evidence**.

## Guided wizard

`Start-CopyGitHubRepositoryWizard` owns interactive selection, contextual help, review, cancellation, progress, and final presentation. It uses `Get-GitHubRepository` for discovery and `Copy-GitHubRepository -PlanOnly` to create the real review artifact.

The wizard executes the exact plan object it displayed through the private approved-plan application boundary; it does not reconstruct an equivalent mutating command after review. If source state changes after review, the wizard explains that the plan is stale, returns to plan generation, and requires the newly captured state to be reviewed before another Execute decision.

The canonical contextual controls are `[? help]`, `[B back]`, `[C cancel]`, and `[F filter]` only where filtering is available. Enter accepts the displayed default. Hidden long-form navigation aliases are not supported.

Normal cancellation before mutation is a structured no-change outcome. `ShouldProcess` remains a real final execution gate.

## Destination and replacement safety

- Source and destination are explicit `owner/name` values.
- A new destination must be unused.
- An existing different destination is never silently overwritten.
- Version 1 does not delete repositories.
- Any visibility change requires explicit `-Force` acknowledgement for mutation.
- Non-interactive mutation requires `-Force`.
- `-Force` and `-Confirm:$false` never bypass exact replacement confirmation.

Same-name replacement preserves the source under an unused archive name before the original name is reused. Source state is checked before rename, then the archive is checked again against the same approved state before replacement creation. Immutable GitHub repository identity continuity is verified when available, and the replacement must receive a distinct immutable ID before content copy.

Existing-destination archive-and-replace checks approved source state before the existing destination is renamed. The archived destination must retain the original destination identity before its replacement is created.

Exact confirmations remain case-sensitive and name the identities involved:

- same-name: `SOURCE=...;ARCHIVE=...;REPLACEMENT=...`
- existing destination: `DESTINATION=...;ARCHIVE=...;REPLACEMENT=...`

## Supported repository configuration

After successful content verification, ordinary supported repository settings are restored differentially and read back. Supported values include description, homepage, Issues/Projects/Wiki/Discussions states, merge options, delete-branch-on-merge, update-branch allowance, web commit signoff, and topics.

Repository protection is a separate final stage. Version 1 restores transferable repository-level rulesets and transferable legacy default-branch protection. Security semantics are never silently weakened to make them portable. Identity-bound, deployment-bound, integration-bound, or inherited organization policy is reported as skipped/unsupported when it cannot be reproduced safely.

`-SkipSettings` skips both ordinary settings and repository-protection restoration.

See [`protection-restoration.md`](../user/protection-restoration.md) for the detailed matrix.

## Unsupported configuration

The following remain outside the implemented v0.1.0 restoration contract:

- GitHub Pages restoration
- GitHub Actions activation/configuration
- secret values
- webhooks
- deploy keys
- environments
- collaborator/team access
- packages/deployments
- GitHub historical/operational records not explicitly supported

`-RestorePages` and `-EnableActionsAfterMigration` may appear in plans, but mutating execution rejects them because those operations are not implemented. Secret values are never requested, copied, displayed, or persisted.

## Provenance and recovery

Snapshot intentionally severs Git ancestry, so successful execution exposes publication provenance outside the clean Git graph. Evidence includes approved source commit/tree state, actual copied source evidence, destination root commit/tree, repository identities when available, UTC time, and verification outcome. Same-name results also record archive identity continuity and distinct replacement identity.

This evidence does not add marker files, tags, notes, parents, or extra commits to the destination.

Post-mutation terminating failures write durable recovery evidence when possible. Recovery records the failure stage, completed steps, known original/archive/replacement identities, and available planned-versus-copied content evidence. Recovery does not automatically delete repositories or rename them back.

## Verification

Snapshot verification proves that the destination tree matches the approved Snapshot tree and that the destination branch contains exactly one root commit. Required LFS transfer must also succeed.

FullHistory verification compares destination branch/tag targets, reachable commit count, branch-tip trees, default branch, and Git LFS availability with the approved FullHistory state.

Ordinary settings and transferable protection are independently read back after restoration.

`Test-GitHubRepositoryMigration` remains the standalone comparison command for callers who explicitly want to compare current source and destination repository state outside an execution plan.

## Public command contract

The exported commands are exactly:

- `Copy-GitHubRepository`
- `Get-GitHubRepository`
- `Start-CopyGitHubRepositoryWizard`
- `Test-GitHubRepositoryMigration`

`Get-GitHubRepository` exposes `ByRepository` and `Search` parameter sets and returns immutable `Id`/`NodeId` when GitHub provides them.

All public commands publish complete comment-based help. `Copy-GitHubRepository` preserves `ShouldProcess`, `-WhatIf`, `-Confirm`, `-PlanOnly`, `-NonInteractive`, `-Force`, structured execution output, and Plain/Json plan rendering.

## Host and release contract

v0.1.0 supports only `github.com`, case-insensitively. Other hosts fail closed before mutation.

Stable publication is tag-only. The tag must equal `v<ModuleVersion>` and the exact tagged commit must pass the reusable Windows, Ubuntu, and macOS quality gate before release publication. Stable release assets are not silently replaced.

## Exclusions from version 1

- repository deletion
- silent destination overwrite
- automatic migration of secret values
- pull requests, issues, discussions, workflow-run history, packages, deployments, stars, watchers, forks, or traffic history
- GitHub Enterprise Server or other non-GitHub.com hosts
