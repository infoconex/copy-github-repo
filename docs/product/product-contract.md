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

`Snapshot` is clean current-state publication. Without `-IncludeReleases`, the approved source default-branch tree becomes one new unrelated destination root commit. Prior commit ancestry, other branches, and tags are not published.

`Snapshot -IncludeReleases` is release-checkpoint history construction. It preserves selected release **states** as a new unrelated linear sequence of checkpoint commits; it does not preserve or rewrite the source commit graph and does not preserve source commit identities.

`FullHistory` is history-preserving copy. Approved ordinary branches, tags, reachable commits, the default branch, and reachable Git LFS objects are preserved.

A **GitHub Release** is separate from an ordinary Git tag. FullHistory preserves ordinary Git tags regardless of release selection. `-IncludeReleases` optionally recreates selected GitHub Release objects and assets. In Snapshot mode, selected release tags are recreated against newly constructed checkpoint commits rather than their original source commit identities.

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

The release-filter ordering above determines which releases are selected; it does **not** define Snapshot checkpoint history ordering. Snapshot checkpoint ordering is defined independently by the Git-topology contract below.

Immediately before the first GitHub mutation, execution re-checks the Git source against the approved state. Drift terminates with `SourceStateChangedSincePlanning`; destination creation or rename does not proceed from that stale plan.

Selected releases are revalidated immediately before release restoration. A selected release that is missing or whose approved metadata, tag target, or asset evidence changed terminates with `SourceReleaseStateChangedSincePlanning`. A newly created source release that was not part of the approved selection is ignored rather than silently added to the migration.

The source Latest designation is intentionally bound to the approved plan rather than re-evaluated as live selection criteria during execution. Publishing a new unselected source release after planning does not silently add that release or invalidate an otherwise unchanged approved release set.

The copy engine also checks its cloned source workspace against the approved state before publishing destination content. Verification then compares the destination with the approved/copied evidence rather than rereading a source branch or ref set that may have moved after publication.

Structured results and recovery/provenance evidence distinguish the **approved/planned source state** from the **actual copied source evidence** and, when requested, the **approved release selection** from restored destination release evidence.

## Snapshot release-checkpoint contract

This section is the authoritative product definition of `Snapshot -IncludeReleases`. Architecture and implementation must reference this contract rather than maintain a competing definition.

### History model

`Snapshot -IncludeReleases` constructs a **new unrelated linear history of repository-state checkpoints**. It is not a Git squash, rebase, filter, or ancestry rewrite of the source graph.

For a non-empty selected release set:

1. resolve each selected release tag to its **peeled source commit target**;
2. validate that the distinct selected commit targets form one deterministic total order under source Git ancestry;
3. create the first distinct selected release state as a new unrelated root commit whose resulting Git tree is equivalent to that selected source release state;
4. create exactly one later checkpoint commit for each later distinct selected source commit target, in ancestry order, whose resulting tree is equivalent to that release state; and
5. after the final selected release checkpoint, create at most one final current-state Snapshot commit according to the HEAD rule below.

Destination checkpoint commits are intentionally new commits. Their SHAs, parents, authorship, committer identity, and commit timestamps are not source identities the product promises to preserve.

### State equivalence

For this contract, two reviewed Git states are **state-equivalent** when their complete Git trees are identical: the tree identity and therefore all recursively represented paths, blob contents, executable bits, symlink entries, submodule entries, and directory structure are the same. Snapshot Git LFS object availability remains separately required by the existing Snapshot content contract; LFS availability does not make two different Git trees equivalent.

State equivalence is deliberately different from commit-SHA preservation. Two different commits may be state-equivalent if they have the same complete tree. Conversely, a destination checkpoint may be state-equivalent to a selected source release while having a different commit SHA because Snapshot creates a new unrelated history.

### Deterministic release ordering

Checkpoint history order is derived only from peeled source commit ancestry. Release publication time, creation time, semantic-version ordering, release name, and tag-name lexical order must not be used to invent checkpoint history order.

After exact duplicate targets are coalesced, every pair of distinct selected release commit targets must be comparable by ancestry: for any pair `A` and `B`, exactly one must be an ancestor of the other. That produces one oldest-to-newest total order. If any pair is incomparable, the selected topology is divergent and Snapshot release preservation fails closed before checkpoint construction.

The final selected release target must also be on the reviewed default-branch HEAD ancestry when its state will be followed by current HEAD. A selected release line that diverges from reviewed HEAD must fail closed rather than fabricate a release-to-current-state progression.

### Edge cases

- **Normal linear ancestry:** distinct selected release targets are ordered oldest to newest by Git ancestry, regardless of GitHub Release publication order.
- **Multiple selected releases at the same source commit:** all such releases share one Snapshot checkpoint. Their tag names and GitHub Release objects remain distinct, but no redundant checkpoint commit is created solely because multiple releases resolve to the same source commit.
- **Different source commits with equivalent trees:** ancestry still controls ordering and each distinct selected commit target remains a distinct checkpoint boundary. Tree equivalence alone does not erase an explicitly selected release boundary.
- **Publication order differs from ancestry:** publication/creation timestamps may affect filtering selection but must not affect checkpoint construction order; Git ancestry wins.
- **Divergent selected tags:** if distinct peeled targets are not totally ordered by ancestry, fail closed. Identical trees on divergent commits do not make the topology safe to linearize.
- **Moved or deleted tags:** planning binds each selected release to its reviewed peeled commit target. If a selected tag is deleted, retargeted, or otherwise resolves differently before execution/restoration, fail with source-release drift rather than using the new target.
- **Annotated and lightweight tags:** where the existing GitHub/Git read boundary supports them, both are normalized by peeling the tag reference to the underlying commit before topology comparison. Tag-object identity, tag-object SHA, tagger metadata, and annotated-tag message are not commit identities preserved by Snapshot. A selected tag that cannot be resolved unambiguously to a commit fails closed.
- **No selected releases:** `Snapshot -IncludeReleases` with an approved empty selection produces the normal one-commit unrelated Snapshot of reviewed current HEAD. It does not create an empty history and does not invent release checkpoints.
- **Reviewed HEAD equals the final selected release state:** when the reviewed default-branch HEAD tree is state-equivalent to the final selected release checkpoint tree, do not create an additional current-state commit. This rule compares state, not commit SHA.
- **Reviewed HEAD differs from the final selected release state:** when the final selected release target is on the reviewed HEAD ancestry and the reviewed HEAD tree is not state-equivalent to the final selected release tree, create exactly one final Snapshot commit representing reviewed current HEAD.

Plain `Snapshot` without `-IncludeReleases` remains unchanged: it creates one unrelated root commit representing reviewed current HEAD. `FullHistory -IncludeReleases` remains unchanged: it preserves the original Git graph and original tag commit targets rather than constructing checkpoint history.

### Scope boundary

This contract settles history shape, topology, state equivalence, tag-target normalization, duplicate-target behavior, drift semantics, and the final-HEAD rule. The implemented planning, checkpoint construction, tag/release restoration, verification, recovery, and wizard paths consume this contract rather than redefining it.

## Guided wizard

`Start-CopyGitHubRepositoryWizard` owns interactive selection, contextual help, review, cancellation, progress, and final presentation. It uses `Get-GitHubRepository` for discovery and `Copy-GitHubRepository -PlanOnly` to create the real review artifact.

For Snapshot, the wizard defaults to plain Snapshot without releases. The operator may opt into release preservation, use the same include/exclude tag, prerelease, draft, and release-count selection controls as the deterministic command, and review the resulting real checkpoint plan before execution. The wizard explains that selected release states become newly created Snapshot checkpoint commits and that source commit identities and ancestry are not preserved.

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

When same-name release migration is requested, the archived original is the source of approved release metadata and assets after rename. Snapshot still constructs new checkpoint commits in the replacement repository; FullHistory preserves the archived original's Git history and tag targets. The archived release state must still match the approved plan before destination releases are created.

Existing-destination archive-and-replace checks approved source state before the existing destination is renamed. The archived destination must retain the original destination identity before its replacement is created.

Exact confirmations remain case-sensitive and name the identities involved:

- same-name: `SOURCE=...;ARCHIVE=...;REPLACEMENT=...`
- existing destination: `DESTINATION=...;ARCHIVE=...;REPLACEMENT=...`

## GitHub Release preservation

GitHub Release preservation is implemented for both `Snapshot` and `FullHistory`. Snapshot follows the release-checkpoint contract above and recreates selected release tags against new checkpoint commits whose repository states correspond to the reviewed source releases. FullHistory preserves the original Git graph and tag commit targets and recreates selected GitHub Releases against those preserved tags.

With `-IncludeReleases` and no additional release filters, all stable, non-draft releases are selected. Release filter parameters require `-IncludeReleases`.

For Snapshot, the exact selected release inventory and checkpoint evidence are bound during planning. Checkpoint construction, tag recreation, release restoration, and independent verification consume that reviewed evidence rather than rerunning live release selection or inventing topology.

For `FullHistory`, release restoration occurs only after FullHistory content verification succeeds. For each approved release:

- the source release is reloaded and checked against approved metadata/asset evidence;
- the source release tag must resolve to the approved commit SHA;
- the destination tag must resolve to that same approved commit SHA;
- an unrelated pre-existing destination GitHub Release for the tag is never overwritten;
- release name/body and draft/prerelease state are recreated where GitHub permits;
- approved release assets are downloaded from the source and uploaded to the destination; and
- the destination release is read back and metadata plus asset name, label, size, content type, and available digest evidence are verified.

For Snapshot, the corresponding destination tag-target check is against the expected newly generated checkpoint commit from the reviewed checkpoint plan, not against the original source commit SHA. The checkpoint tree must be state-equivalent to the reviewed selected release state before the release is considered correctly represented.

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

Snapshot intentionally severs Git ancestry, so successful execution exposes publication provenance outside the clean Git graph. Plain Snapshot evidence includes approved source commit/tree state, actual copied source evidence, destination root commit/tree, repository identities when available, UTC time, and verification outcome. Snapshot release-preservation evidence additionally records the reviewed checkpoint plan and available created checkpoint commits, recreated tag targets, restored releases/assets, and verification state. Same-name results also record archive identity continuity and distinct replacement identity.

FullHistory release results expose the approved/restored release count, per-release source/destination release IDs, source/destination commit SHAs, latest-release preservation evidence when applicable, asset counts, and verification state. Recovery evidence includes the approved release selection and any available release restoration result when failure occurs during or after that stage.

This evidence does not add marker files, provenance tags, notes, or source-history parents to the destination.

Post-mutation terminating failures write durable recovery evidence when possible. Recovery records the failure stage, completed steps, known original/archive/replacement identities, and available planned-versus-copied content/release evidence. Snapshot release recovery can identify created checkpoint commits and recreated release tags in addition to restored releases/assets. Recovery does not automatically delete repositories, commits, tags, releases, or rename repositories back.

## Verification

Plain Snapshot verification proves that the destination tree matches the approved Snapshot tree and that the destination branch contains exactly one root commit.

Snapshot release-checkpoint verification is implemented against the authoritative checkpoint contract and immutable reviewed checkpoint evidence. It independently proves the expected generated checkpoint count/sequence and parentage, tree/state equivalence for each checkpoint, selected release-tag targets, the final reviewed HEAD state and optional final current-state commit rule, selected release metadata/assets, and Latest designation where applicable. `Test-GitHubRepositoryMigration -ContentMode Snapshot -IncludeReleases` requires the approved plan so standalone verification cannot rerun live selection or topology discovery and redefine the expected state.

FullHistory verification compares destination branch/tag targets, reachable commit count, branch-tip trees, default branch, and LFS availability with the approved FullHistory state.

When `-IncludeReleases` is requested during FullHistory migration, execution-integrated release restoration additionally verifies that destination release tags resolve to approved FullHistory commit identities and that supported release metadata/assets match the approved release selection. When the approved source Latest release is selected, the destination Latest designation is also verified.

Ordinary settings and transferable protection are independently read back after restoration.

`Test-GitHubRepositoryMigration` is the standalone read-only comparison command. With `Snapshot -IncludeReleases`, it consumes the immutable approved plan and verifies the generated destination checkpoints, recreated tags/releases, final reviewed HEAD state, metadata/assets, and Latest designation without rerunning live release filtering. With `FullHistory -IncludeReleases`, it applies the same release-selection parameters to the **current** source release state and compares the selected releases with the destination, including original tag commit identity, supported release metadata/assets, and the Latest designation when selected. Because the FullHistory standalone path does not receive the original immutable migration plan, it verifies current source-versus-destination equivalence rather than proving that the source release state has remained unchanged since the migration. Extra destination releases outside the selected current source set do not cause FullHistory standalone verification failure.

## Public command contract

The exported commands are exactly:

- `Copy-GitHubRepository`
- `Get-GitHubRepository`
- `Start-CopyGitHubRepositoryWizard`
- `Test-GitHubRepositoryMigration`

`Get-GitHubRepository` exposes `ByRepository` and `Search` parameter sets and returns immutable `Id`/`NodeId` when GitHub provides them.

All public commands publish complete comment-based help. `Copy-GitHubRepository` preserves `ShouldProcess`, `-WhatIf`, `-Confirm`, `-PlanOnly`, `-NonInteractive`, `-Force`, structured execution output, Plain/Json plan rendering, and the release-selection parameters documented in its command reference. `Test-GitHubRepositoryMigration` exposes Snapshot approved-plan release verification and the supported FullHistory live release-selection surface documented in its command reference.

## Host and release contract

The current release line supports only `github.com`, case-insensitively. Other hosts fail closed before mutation.

Stable publication is tag-only. The tag must equal `v<ModuleVersion>` and the exact tagged commit must pass the reusable Windows, Ubuntu, and macOS quality gate before release publication. Stable release assets are not silently replaced.

## Exclusions

- repository deletion
- silent destination overwrite
- automatic migration of secret values
- GitHub Release immutability state and linked release discussions
- pull requests, issues, discussions, workflow-run history, packages, deployments, stars, watchers, forks, or traffic history
- GitHub Enterprise Server or other non-GitHub.com hosts