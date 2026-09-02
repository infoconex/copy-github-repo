---
title: "CopyGitHubRepo Product Contract – GitHub Repository Copy Behavior"
description: "Review the normative CopyGitHubRepo contract for Snapshot and FullHistory, immutable planning, optional releases and GitHub Pages restoration, replacement safety, verification, and recovery."
---

# Product contract

## Purpose

Copy GitHub Repository safely publishes or copies GitHub repositories while preserving the source or archived original and producing evidence that selected content and supported GitHub-side configuration were reproduced correctly.

The default use case is a **clean Snapshot publication**: publish approved current state into a destination whose Git history begins with one unrelated root commit. `FullHistory` is the explicit **history-preserving copy** alternative.

The stable public content-mode values are exactly `Snapshot` and `FullHistory`. GitHub Pages restoration is a separate opt-in GitHub-side state capability governed normatively by the [GitHub Pages migration contract](github-pages-migration-contract.md).

## Defaults

- PowerShell 7.4 or newer
- GitHub.com only in the current release line
- GitHub CLI authentication
- `Snapshot` content mode
- destination visibility inherited from source
- GitHub Release preservation disabled unless explicitly requested
- GitHub Pages restoration disabled unless explicitly requested with `-RestorePages`
- supported ordinary repository settings restored after content/release verification
- requested Pages restoration occurs after ordinary settings and before protection
- transferable repository protection restored last
- guided human experience through `Start-CopyGitHubRepositoryWizard`
- structured automation through `Copy-GitHubRepository`
- Markdown and JSON reporting

## Canonical content terminology

`Snapshot` is clean current-state publication. Without `-IncludeReleases`, approved source default-branch tree becomes one new unrelated destination root commit. Prior commit ancestry, other branches, and tags are not published.

`Snapshot -IncludeReleases` is release-checkpoint history construction. It preserves selected release **states** as a new unrelated linear sequence of checkpoint commits; it does not preserve or rewrite the source commit graph and does not preserve source commit identities.

`FullHistory` is history-preserving copy. Approved ordinary branches, tags, reachable commits, default branch, and reachable Git LFS objects are preserved.

A **GitHub Release** is separate from an ordinary Git tag. FullHistory preserves ordinary Git tags regardless of release selection. `-IncludeReleases` optionally recreates selected GitHub Release objects/assets. In Snapshot mode, selected release tags are recreated against newly constructed checkpoint commits rather than original source commit identities.

**Repository Pages content** and **GitHub-side Pages configuration** are also separate. Site files, `CNAME`, Jekyll configuration, and `.github/workflows/**` are ordinary Git content and may be copied according to Snapshot/FullHistory semantics. Their presence or execution is not proof that GitHub-side Pages configuration was preserved. `-RestorePages` is the explicit opt-in for supported GitHub-side Pages planning/restoration/verification.

Human-facing plans and wizard text use **repository copy plan**, **Snapshot**, **FullHistory**, **archive**, **replacement**, **source**, and **destination** consistently. Internal/debug representations are not user-facing status text.

## Immutable approved source state

Planning is not merely a preview of command parameters. Every executable plan captures immutable source-state evidence and execution is bound to that reviewed evidence.

Snapshot plans capture source repository identity when available, source default branch, exact commit/tree SHA, Snapshot Git LFS evidence, and capture time.

FullHistory plans capture source repository identity when available, source default branch, exact ordinary branch/tag targets, reachable commit count, branch-tip tree identities, reachable Git LFS availability, and capture time.

When `-IncludeReleases` is requested, the plan also stores the exact approved release selection including identity, tag, supported metadata, Latest status where applicable, resolved tag target, and asset evidence. Release filtering occurs during planning; Snapshot checkpoint ordering is still derived from source Git ancestry, not release dates.

When `-RestorePages` is requested, the same immutable reviewed plan captures Pages evidence sufficient to drive later restoration and stale-state detection. That evidence includes explicit configured/not-configured state, build type, exact branch/path source where applicable, custom domain, HTTPS intent, representability, and separately classified external readiness.

Immediately before the first GitHub mutation, execution re-checks Git source state. Drift terminates rather than allowing destination creation/rename from a stale plan. Selected releases are separately revalidated before release restoration.

Pages has an additional capability-specific revalidation immediately before Pages mutation. A material change to reviewed configured state, build type, branch/path, custom domain, or another supported mutation-driving property terminates before Pages mutation rather than applying the new live state. Earlier migration stages may already have completed at this point, so recovery evidence must preserve that distinction.

The copy engine also checks cloned source workspace state against approved evidence before publishing. Verification compares destination with approved/copied evidence rather than rereading moving source state as authority.

Structured results/recovery evidence distinguish approved/planned source state from actual copied evidence and, where requested, approved releases/Pages evidence from restored destination evidence.

## Snapshot release-checkpoint contract

This section is the authoritative product definition of `Snapshot -IncludeReleases`. Architecture and implementation reference this contract rather than maintain a competing definition.

### History model

`Snapshot -IncludeReleases` constructs a **new unrelated linear history of repository-state checkpoints**. It is not a Git squash, rebase, filter, or ancestry rewrite of the source graph.

For a non-empty selected release set:

1. resolve each selected release tag to its **peeled source commit target**;
2. validate that distinct selected commit targets form one deterministic total order under source Git ancestry;
3. create first distinct selected release state as a new unrelated root commit whose tree is equivalent to that selected source release state;
4. create exactly one later checkpoint commit for each later distinct selected source commit target, in ancestry order, whose tree is equivalent to that release state; and
5. after final selected release checkpoint, create at most one final current-state Snapshot commit according to the HEAD rule below.

Destination checkpoint commits are intentionally new commits. Their SHAs, parents, authorship, committer identity, and timestamps are not source identities the product promises to preserve.

### State equivalence

Two reviewed Git states are **state-equivalent** when their complete Git trees are identical. Snapshot Git LFS availability remains separately required; LFS availability does not make two different trees equivalent.

State equivalence is different from commit-SHA preservation. Different commits can be state-equivalent when trees match, while destination checkpoints can match source release state with new commit SHAs because Snapshot creates unrelated history.

### Deterministic release ordering

Checkpoint history order derives only from peeled source commit ancestry. Release publication/creation time, semantic version, release name, and tag lexical order must not invent checkpoint order.

After exact duplicate targets are coalesced, each distinct selected target pair must be ancestry-comparable. Incomparable targets are divergent and fail closed before checkpoint construction. The final selected target must also be on reviewed default-branch HEAD ancestry when followed by current HEAD.

### Edge cases

- **Normal linear ancestry:** distinct selected targets are oldest-to-newest by Git ancestry regardless of release publication order.
- **Multiple selected releases at same source commit:** share one Snapshot checkpoint while keeping distinct tags/releases.
- **Different source commits with equivalent trees:** remain distinct checkpoint boundaries because selected source commit targets differ.
- **Publication order differs from ancestry:** affects selection only where filters/count depend on dates; ancestry controls checkpoint history.
- **Divergent selected tags:** fail closed even if trees happen to be identical.
- **Moved/deleted tags:** selected tag drift fails rather than adopting a new target.
- **Annotated/lightweight tags:** normalize to peeled commit target; tag-object identity/metadata is not preserved Snapshot commit identity.
- **No selected releases:** behaves as normal one-commit Snapshot.
- **Reviewed HEAD equals final selected release state:** no extra current-state commit when complete trees are state-equivalent.
- **Reviewed HEAD differs:** create exactly one final Snapshot current-state commit when topology permits.

Plain Snapshot without `-IncludeReleases` remains one unrelated current-state root. `FullHistory -IncludeReleases` preserves original Git graph/tag targets rather than constructing checkpoints.

### Scope boundary

This contract settles history shape, topology, state equivalence, tag-target normalization, duplicate-target behavior, drift semantics, and final-HEAD rule. Planning, checkpoint construction, tag/release restoration, verification, recovery, and wizard paths consume it.

## Guided wizard

`Start-CopyGitHubRepositoryWizard` owns interactive selection, contextual help, review, cancellation, progress, and final presentation. It uses `Get-GitHubRepository` for discovery and `Copy-GitHubRepository -PlanOnly` for the real review artifact.

For Snapshot, wizard defaults to plain Snapshot without releases. Operator may opt into release preservation and the same filters as deterministic command; review shows real checkpoint plan.

Pages restoration is also explicit and off by default. The wizard consumes the real plan-derived Pages evidence and distinguishes Git content from GitHub-side Pages state. Where available, review surfaces configured state, publishing mode/source, custom domain, HTTPS intent, representability, and external readiness/boundaries. It does not claim external DNS, domain verification, certificate provisioning, or secrets will be copied.

The wizard executes the exact plan object displayed through the approved-plan application boundary; it does not reconstruct equivalent live discovery after review. Plan-driving stale state requires a new plan/review. Same-name custom-domain handoff is surfaced before execution, while deterministic execution retains identity, stale-state, restoration, verification, and recovery authority.

Canonical contextual controls are `[? help]`, `[B back]`, `[C cancel]`, and `[F filter]` where filtering is available. Enter accepts displayed default. Normal cancellation before mutation is structured no-change outcome. `ShouldProcess` remains a real final execution gate.

## Destination and replacement safety

- Source and destination are explicit `owner/name` values.
- A new destination must be unused.
- An existing different destination is never silently overwritten.
- Product does not automatically delete repositories.
- Visibility change requires explicit `-Force` acknowledgement for mutation.
- Non-interactive mutation requires `-Force`.
- `-Force` and `-Confirm:$false` never bypass exact replacement confirmation.

Same-name replacement preserves source under unused archive name before original name is reused. Source state is checked before rename; archive is checked again against approved state before replacement creation. Immutable repository identity continuity is verified where available and replacement must receive distinct identity before content copy.

Existing-destination archive-and-replace similarly verifies preserved destination identity before creating replacement.

Exact confirmations remain case-sensitive and identify all participants:

- same-name: `SOURCE=...;ARCHIVE=...;REPLACEMENT=...`
- existing destination: `DESTINATION=...;ARCHIVE=...;REPLACEMENT=...`

For requested Pages restoration with a reviewed custom domain, domain binding is ownership-sensitive GitHub-side state. Before archive release, execution proves reviewed archive/replacement identities and exact intended recipient/representability. Ambiguous or unrelated ownership fails closed. The exact domain is released only at the defined handoff stage, release is read back, replacement claims the exact reviewed domain, and replacement read-back verifies ownership. A successful handoff must not leave archive and replacement both claiming the production domain.

External DNS is never modified. If handoff fails after release, recovery evidence records release/claim/read-back state and the implementation does not perform destructive automatic rollback when ownership is uncertain.

## GitHub Release preservation

GitHub Release preservation is implemented for both `Snapshot` and `FullHistory`. Snapshot recreates selected release tags against new checkpoint commits whose states match reviewed source releases. FullHistory preserves original Git graph/tag targets and recreates selected GitHub Releases against those preserved tags.

With `-IncludeReleases` and no additional filters, stable non-draft releases are selected. Filters require `-IncludeReleases`.

For Snapshot, exact selected inventory and checkpoint evidence are bound during planning. Construction/restoration/verification consumes reviewed evidence rather than rerunning live selection or inventing topology.

For FullHistory, release restoration occurs after FullHistory content verification. Approved source release metadata/assets/tag targets are revalidated; destination tag must resolve to approved original commit; unrelated pre-existing destination release is not overwritten; supported metadata/assets are recreated/read back.

For Snapshot, destination release tag-target check is against expected newly generated checkpoint commit, whose tree must match reviewed selected release state.

If source release marked Latest at planning time is selected, designation is explicitly preserved/verified. When source Latest is excluded by selection, product does not claim to preserve omitted release.

GitHub-assigned destination release IDs/timestamps are new. Historical IDs/timestamps/download counts, release immutability state, linked release discussions, and other unsupported historical records are not reproduced exactly.

Release-stage failure does not automatically delete earlier restored releases; recovery retains stage/evidence.

## GitHub Pages restoration

The complete normative Pages contract is maintained in [`github-pages-migration-contract.md`](github-pages-migration-contract.md); this section defines its place within the overall product contract.

`-RestorePages` is implemented and opt-in. Without it, Snapshot/FullHistory retain existing Git-content semantics. Site/workflow files may be copied, but CopyGitHubRepo does not claim GitHub-side Pages configuration was preserved/restored and incidental workflow execution is not successful Pages migration.

With `-RestorePages`, supported GitHub-side state includes:

- explicit configured/not-configured state;
- Actions-based `workflow` build type;
- branch/path publishing using exact reviewed branch and supported `/` or `/docs` path when representable;
- custom-domain binding subject to ownership/handoff safety; and
- HTTPS enforcement intent where GitHub permits deterministic mutation/read-back.

Snapshot must not invent a missing branch/path publishing source or silently redirect to another source. Unsupported/unrepresentable publishing state fails closed.

Requested Pages restoration occurs after destination content verification, requested release restoration, and ordinary supported settings. Copied Pages workflow activation is controlled until approved restoration/verification boundary. Pages evidence is revalidated immediately before mutation. Restoration is followed by independent read-back verification. Transferable protection remains last.

External DNS records are not queried as mutation authority, copied, or modified. Account/organization domain verification is not transferred. Certificate issuance/propagation is external/asynchronous. HTTPS intent may be correctly restored while certificate readiness is `PendingCertificate`; that readiness state is not by itself deterministic migration failure.

Secret values, tokens, and environment secrets are never requested/copied/displayed/persisted.

Operator guidance and recovery steps live in [`../user/github-pages-migration.md`](../user/github-pages-migration.md).

## Supported repository configuration

After content verification and requested release restoration, ordinary supported settings are restored differentially/read back. Supported values include description, homepage, Issues/Projects/Wiki/Discussions states, merge options, delete-branch-on-merge, update-branch allowance, web commit signoff, and topics.

Requested Pages restoration follows ordinary settings as described above. Repository protection is a separate final stage and restores transferable repository-level rulesets and legacy default-branch protection. Security semantics are never weakened just to make policy portable; identity/deployment/integration-bound or inherited controls are skipped/reported when not safely transferable.

`-SkipSettings` skips ordinary settings and repository-protection restoration. It does **not** suppress requested GitHub Release or Pages restoration.

See [`protection-restoration.md`](../user/protection-restoration.md) and [`github-pages-migration.md`](../user/github-pages-migration.md) for detailed matrices/guidance.

## Unsupported configuration and external state

The following remain outside implemented restoration:

- general GitHub Actions activation/configuration outside the Pages-specific activation safety boundary
- external DNS mutation
- account/organization domain verification transfer
- certificate issuance/propagation management
- secret values
- webhooks
- deploy keys
- environments/general environment configuration
- collaborator/team access
- packages/deployments
- GitHub Release immutability configuration/state
- linked GitHub Release discussions
- GitHub historical/operational records not explicitly supported

`-EnableActionsAfterMigration` remains reserved/unimplemented for general Actions activation. This does not negate implemented Pages-specific activation control under `-RestorePages`.

## Provenance and recovery

Snapshot intentionally severs Git ancestry, so successful execution exposes publication provenance outside clean Git graph. Plain Snapshot evidence includes approved source commit/tree, copied evidence, destination root/tree, repository identities, time, and verification outcome. Snapshot release evidence adds reviewed/generated checkpoint/tag/release evidence. Replacement results identify original/archive/replacement identities.

FullHistory release results expose approved/restored release counts, source/destination release/tag evidence, Latest preservation where applicable, assets, and verification state.

Pages results/recovery evidence include reviewed configuration, destination restoration/read-back status, activation-guard state, last successful Pages stage, external readiness classification, and custom-domain handoff evidence where applicable. Handoff evidence distinguishes archive release attempted/succeeded, replacement claim attempted/succeeded, and replacement read-back. `DnsMutationAttempted`/equivalent evidence remains false; no automatic destructive ownership rollback is claimed.

This evidence does not add marker files, provenance tags, notes, or source-history parents to destination.

Post-mutation terminating failures write durable recovery evidence when possible. Recovery records failure stage, completed steps, known identities, and available approved/copied/restored evidence. It does not automatically delete repositories/commits/tags/releases/Pages state, rename archives back, or rebind uncertain custom-domain ownership.

## Verification

Plain Snapshot verification proves destination tree matches approved Snapshot tree and branch contains exactly one root commit.

Snapshot release-checkpoint verification independently proves expected generated checkpoint sequence/parentage, tree/state equivalence, selected release tag targets, final reviewed HEAD/current-state rule, selected release metadata/assets, and Latest designation where applicable. Standalone Snapshot release verification consumes approved plan evidence rather than rerunning mutable live selection/topology.

FullHistory verification compares destination branch/tag targets, reachable commit count, branch-tip trees, default branch, and LFS availability with approved FullHistory state. Requested FullHistory releases additionally verify original tag commit identities and supported release metadata/assets/Latest where selected.

Ordinary settings and transferable protection are independently read back after restoration.

Pages verification is read-only and independent of restoration mutation. Where applicable it compares reviewed destination configured state, build type, exact branch/path, custom-domain binding, HTTPS state where deterministic, and after replacement that archive no longer owns the production domain while replacement does. DNS/domain-verification/certificate state is separately reported external readiness and is never proof that it was migrated.

`Test-GitHubRepositoryMigration` remains the standalone read-only content/release comparison command with mode-specific semantics described in its command reference; Pages restoration uses its dedicated independent GitHub-side read-back verification boundary.

## Public command contract

Exported commands are exactly:

- `Copy-GitHubRepository`
- `Get-GitHubRepository`
- `Start-CopyGitHubRepositoryWizard`
- `Test-GitHubRepositoryMigration`

`Get-GitHubRepository` exposes `ByRepository` and `Search` parameter sets and returns immutable `Id`/`NodeId` when GitHub provides them.

All public commands publish complete comment-based help. `Copy-GitHubRepository` preserves `ShouldProcess`, `-WhatIf`, `-Confirm`, `-PlanOnly`, `-NonInteractive`, `-Force`, structured execution output, Plain/Json plan rendering, release-selection parameters, and implemented opt-in `-RestorePages` behavior documented in its command reference. Wizard help/reference describes the matching Pages opt-in/review behavior rather than a separate implementation.

## Host and release contract

The current release line supports only `github.com`, case-insensitively. Other hosts fail closed before mutation.

Stable publication is tag-only. Tag must equal `v<ModuleVersion>` and exact tagged commit must pass reusable Windows, Ubuntu, and macOS quality gate before publication. Stable release assets are not silently replaced.

## Exclusions

- repository deletion
- silent destination overwrite
- automatic migration of secret values
- external DNS mutation or domain-verification transfer
- certificate issuance/propagation management
- GitHub Release immutability state and linked release discussions
- pull requests, issues, discussions, workflow-run history, packages, deployments, stars, watchers, forks, or traffic history
- GitHub Enterprise Server or other non-GitHub.com hosts
