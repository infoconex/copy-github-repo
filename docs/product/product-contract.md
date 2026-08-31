---
title: "CopyGitHubRepo Product Contract – GitHub Repository Copy Behavior"
description: "Review the normative CopyGitHubRepo contract for Snapshot and FullHistory modes, immutable source-state planning, optional GitHub Release preservation, replacement safety, configuration restoration, verification, provenance, and recovery."
---

# Product contract

## Purpose

Copy GitHub Repository safely publishes or copies GitHub repositories while preserving the source or archived original and producing evidence that the selected content and supported configuration were reproduced correctly.

The default use case is a **clean Snapshot publication**: publish the approved current state of a developed repository into a destination whose Git history begins with one unrelated root commit. `FullHistory` is the explicit **history-preserving copy** alternative.

The stable public content-mode values are exactly `Snapshot` and `FullHistory`.

## Defaults

- PowerShell 7.4 or newer
- GitHub.com only in the current release line
- GitHub CLI authentication
- `Snapshot` content mode
- destination visibility inherited from the source
- GitHub Release preservation disabled unless explicitly requested
- supported repository settings restored after content verification
- transferable repository protection restored last
- guided human experience through `Start-CopyGitHubRepositoryWizard`
- structured automation through `Copy-GitHubRepository`
- Markdown and JSON reporting

## Canonical content terminology

`Snapshot` is clean current-state publication. The approved source default-branch tree becomes one new unrelated destination root commit. Prior commit ancestry, other branches, and tags are not published.

`FullHistory` is history-preserving copy. Approved ordinary branches, tags, reachable commits, the default branch, and reachable Git LFS objects are preserved.

A **GitHub Release** is separate from an ordinary Git tag. FullHistory preserves ordinary Git tags regardless of release selection. `-IncludeReleases` optionally recreates selected GitHub Release objects and assets against those preserved tags.

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

When `-IncludeReleases` is requested, the plan additionally enumerates source GitHub Releases and stores the exact approved selection. The selection records release identity, tag name, name/body, draft/prerelease state, whether the selected release was the source repository's Latest full release at planning time, resolved tag commit SHA, and asset metadata including name, label, size, content type, and digest when GitHub provides one.

Release filtering is applied during planning in this order:

1. exclude drafts unless `-IncludeDraftReleases` is supplied;
2. exclude prereleases unless `-IncludePrerelease` is supplied;
3. apply `-ReleaseTag` include wildcard patterns when supplied;
4. apply `-ReleaseExcludeTag` wildcard patterns when supplied;
5. order by publication time, falling back to creation time;
6. apply `-ReleaseCount` to the newest remaining releases when supplied.

Immediately before the first GitHub mutation, execution re-checks the Git source against the approved state. Drift terminates with `SourceStateChangedSincePlanning`; destination creation or rename does not proceed from that stale plan.

Selected releases are revalidated immediately before release restoration. A selected release that is missing or whose approved metadata, tag target, or asset evidence changed terminates with `SourceReleaseStateChangedSincePlanning`. A newly created source release that was not part of the approved selection is ignored rather than silently added to the migration.

The source Latest designation is intentionally bound to the approved plan rather than re-evaluated as live selection criteria during execution. Publishing a new unselected source release after planning does not silently add that release or invalidate an otherwise unchanged approved release set.

The copy engine also checks its cloned source workspace against the approved state before publishing destination content. Verification then compares the destination with the approved/copied evidence rather than rereading a source branch or ref set that may have moved after publication.

Structured results and recovery/provenance evidence distinguish the **approved/planned source state** from the **actual copied source evidence** and, when requested, the **approved release selection** from restored destination release evidence.

## Guided wizard

`Start-CopyGitHubRepositoryWizard` owns interactive selection, contextual help, review, cancellation, progress, and final presentation. It uses `Get-GitHubRepository` for discovery and `Copy-GitHubRepository -PlanOnly` to create the real review artifact.

The wizard executes the exact plan object it displayed through the private approved-plan application boundary; it does not reconstruct an equivalent mutating command after review. If source state changes after review, the wizard explains that the plan is stale, returns to plan generation, and requires the newly captured state to be reviewed before another Execute decision.

The canonical contextual controls are `[? help]`, `[B back]`, `[C cancel]`, and `[F filter]` only where filtering is available. Enter accepts the displayed default. Hidden long-form navigation aliases are not supported.

Normal cancellation before mutation is a structured no-change outcome. `ShouldProcess` remains a real final execution gate.

## Destination and replacement safety

- Source and destination are explicit `owner/name` values.
- A new destination must be unused.
- An existing different destination is never silently overwritten.
- The product does not automatically delete repositories.
- Any visibility change requires explicit `-Force` acknowledgement for mutation.
- Non-interactive mutation requires `-Force`.
- `-Force` and `-Confirm:$false` never bypass exact replacement confirmation.

Same-name replacement preserves the source under an unused archive name before the original name is reused. Source state is checked before rename, then the archive is checked again against the same approved state before replacement creation. Immutable GitHub repository identity continuity is verified when available, and the replacement must receive a distinct immutable ID before content copy.

When same-name FullHistory release migration is requested, the archived original is the source of approved release metadata and assets after rename. The archived release state must still match the approved plan before destination releases are created.

Existing-destination archive-and-replace checks approved source state before the existing destination is renamed. The archived destination must retain the original destination identity before its replacement is created.

Exact confirmations remain case-sensitive and name the identities involved:

- same-name: `SOURCE=...;ARCHIVE=...;REPLACEMENT=...`
- existing destination: `DESTINATION=...;ARCHIVE=...;REPLACEMENT=...`

## GitHub Release preservation

GitHub Release preservation is implemented only for `FullHistory`. `-IncludeReleases` with Snapshot fails closed because Snapshot release-history synthesis is a separate future capability.

With `-IncludeReleases` and no additional release filters, all stable, non-draft releases are selected. Release filter parameters require `-IncludeReleases`.

Release restoration occurs only after FullHistory content verification succeeds. For each approved release:

- the source release is reloaded and checked against approved metadata/asset evidence;
- the source release tag must resolve to the approved commit SHA;
- the destination tag must resolve to that same approved commit SHA;
- an unrelated pre-existing destination GitHub Release for the tag is never overwritten;
- release name/body and draft/prerelease state are recreated where GitHub permits;
- approved release assets are downloaded from the source and uploaded to the destination; and
- the destination release is read back and metadata plus asset name, label, size, content type, and available digest evidence are verified.

If the source release marked Latest at planning time is part of the approved selection, execution explicitly preserves that designation and verifies the destination Latest release resolves to the same selected tag. When filtering excludes the source Latest release, the product does not claim to preserve an omitted release; GitHub determines Latest among the releases that actually exist at the destination.

GitHub-assigned destination release IDs and creation/publication timestamps are new values. Original release IDs, historical creation/publication timestamps, release download counts, per-release immutability state, and linked release discussions are provenance/unsupported metadata rather than values the product claims to preserve exactly.

A release-stage failure after earlier releases were restored does not automatically delete those destination releases. Recovery evidence records the release failure stage and available approved/restored release evidence.

## Supported repository configuration

After successful content verification and requested release restoration, ordinary supported repository settings are restored differentially and read back. Supported values include description, homepage, Issues/Projects/Wiki/Discussions states, merge options, delete-branch-on-merge, update-branch allowance, web commit signoff, and topics.

Repository protection is a separate final stage. The product restores transferable repository-level rulesets and transferable legacy default-branch protection. Security semantics are never silently weakened to make them portable. Identity-bound, deployment-bound, integration-bound, or inherited organization policy is reported as skipped/unsupported when it cannot be reproduced safely.

`-SkipSettings` skips both ordinary settings and repository-protection restoration. It does not suppress requested GitHub Release restoration.

See [`protection-restoration.md`](../user/protection-restoration.md) for the detailed matrix.

## Unsupported configuration

The following remain outside the implemented restoration contract:

- GitHub Pages restoration
- GitHub Actions activation/configuration
- secret values
- webhooks
- deploy keys
- environments
- collaborator/team access
- packages/deployments
- GitHub Release immutability configuration/state
- linked GitHub Release discussions
- GitHub historical/operational records not explicitly supported

`-RestorePages` and `-EnableActionsAfterMigration` may appear in plans, but mutating execution rejects them because those operations are not implemented. Secret values are never requested, copied, displayed, or persisted.

## Provenance and recovery

Snapshot intentionally severs Git ancestry, so successful execution exposes publication provenance outside the clean Git graph. Evidence includes approved source commit/tree state, actual copied source evidence, destination root commit/tree, repository identities when available, UTC time, and verification outcome. Same-name results also record archive identity continuity and distinct replacement identity.

FullHistory release results expose the approved/restored release count, per-release source/destination release IDs, source/destination commit SHAs, latest-release preservation evidence when applicable, asset counts, and verification state. Recovery evidence includes the approved release selection and any available release restoration result when failure occurs during or after that stage.

This evidence does not add marker files, tags, notes, parents, or extra commits to the destination.

Post-mutation terminating failures write durable recovery evidence when possible. Recovery records the failure stage, completed steps, known original/archive/replacement identities, and available planned-versus-copied content/release evidence. Recovery does not automatically delete repositories, releases, or rename repositories back.

## Verification

Snapshot verification proves that the destination tree matches the approved Snapshot tree and that the destination branch contains exactly one root commit. Required LFS transfer must also succeed.

FullHistory verification compares destination branch/tag targets, reachable commit count, branch-tip trees, default branch, and Git LFS availability with the approved FullHistory state.

When `-IncludeReleases` is requested during migration, execution-integrated release restoration additionally verifies that destination release tags resolve to approved FullHistory commit identities and that supported release metadata/assets match the approved release selection. When the approved source Latest release is selected, the destination Latest designation is also verified.

Ordinary settings and transferable protection are independently read back after restoration.

`Test-GitHubRepositoryMigration` is the standalone read-only comparison command. With `FullHistory -IncludeReleases`, it applies the same release-selection parameters to the **current** source release state and compares the selected releases with the destination, including tag commit identity, supported release metadata/assets, and the Latest designation when selected. Because standalone verification does not receive the original immutable migration plan, it verifies current source-versus-destination equivalence rather than proving that the source release state has remained unchanged since the migration. Extra destination releases outside the selected current source set do not cause standalone verification failure.

## Public command contract

The exported commands are exactly:

- `Copy-GitHubRepository`
- `Get-GitHubRepository`
- `Start-CopyGitHubRepositoryWizard`
- `Test-GitHubRepositoryMigration`

`Get-GitHubRepository` exposes `ByRepository` and `Search` parameter sets and returns immutable `Id`/`NodeId` when GitHub provides them.

All public commands publish complete comment-based help. `Copy-GitHubRepository` preserves `ShouldProcess`, `-WhatIf`, `-Confirm`, `-PlanOnly`, `-NonInteractive`, `-Force`, structured execution output, Plain/Json plan rendering, and the FullHistory-only release-selection parameters documented in its command reference. `Test-GitHubRepositoryMigration` exposes the same release-selection surface for read-only FullHistory release verification.

## Host and release contract

The current release line supports only `github.com`, case-insensitively. Other hosts fail closed before mutation.

Stable publication is tag-only. The tag must equal `v<ModuleVersion>` and the exact tagged commit must pass the reusable Windows, Ubuntu, and macOS quality gate before release publication. Stable release assets are not silently replaced.

## Exclusions

- repository deletion
- silent destination overwrite
- automatic migration of secret values
- Snapshot GitHub Release preservation
- GitHub Release immutability state and linked release discussions
- pull requests, issues, discussions, workflow-run history, packages, deployments, stars, watchers, forks, or traffic history
- GitHub Enterprise Server or other non-GitHub.com hosts
