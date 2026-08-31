---
title: "How to Copy or Migrate a GitHub Repository"
description: "Learn how to copy or migrate a GitHub repository with PowerShell using Snapshot for a clean history that can optionally preserve selected release checkpoints, or FullHistory to preserve original commits, branches, tags, Git LFS, and selected GitHub Releases."
---

# User guide: capabilities and common scenarios

This guide is the user-facing path for evaluating, planning, running, and verifying Copy GitHub Repository operations.

For normative behavior, safety invariants, and supported scope, see [`product-contract.md`](../product/product-contract.md). For detailed command syntax and parameters, see the [`commands`](../reference/commands/README.md) reference. Stable capability, use-case, and behavioral-scenario IDs are defined in [`product-model.md`](../product/product-model.md).

## Start here

A typical user journey is:

1. **Choose the outcome.** Use `Snapshot` for a clean publication with newly created Git history. Plain Snapshot creates one unrelated current-state root commit; `Snapshot -IncludeReleases` creates a new unrelated checkpoint history from selected release states. Use `FullHistory` when original ordinary Git history must be preserved.
2. **Install and authenticate.** Install the stable module from PowerShell Gallery, then authenticate GitHub CLI for `github.com`.
3. **Preview before mutation.** Use the guided wizard or `Copy-GitHubRepository -PlanOnly` to review the source, destination, mode, visibility, settings choices, immutable source-state evidence, selected GitHub Releases/checkpoints when requested, and any replacement/archive plan.
4. **Execute deliberately.** Replacement operations require the safety acknowledgements and exact confirmation defined by the product contract.
5. **Verify the result.** Successful execution verifies content before reporting success and returns structured evidence. Requested release restoration also verifies the selected release/tag/asset state. `Test-GitHubRepositoryMigration` is available for a separate read-only current-state comparison.
6. **Preserve evidence if something fails.** If mutation has started, do not assume rollback occurred. The tool preserves repositories and writes recovery evidence when possible; use the [troubleshooting and recovery guide](troubleshooting-recovery.md) for diagnosis and recovery.

For normal stable installation, use PowerShell Gallery:

```powershell
Install-PSResource CopyGitHubRepo
Import-Module CopyGitHubRepo
gh auth login --hostname github.com
```

`Install-PSResource` installs the latest stable Gallery version by default. To deliberately pin the initial stable release, use `Install-PSResource CopyGitHubRepo -Version 0.1.0`. Environments using the older PowerShellGet commands can use `Install-Module CopyGitHubRepo -Scope CurrentUser` instead. For repository-hosted, provenance-verified, pinned-artifact, and prerelease alternatives, see [Installation security](../security/installation-security.md).

For interactive use, start with:

```powershell
Start-CopyGitHubRepositoryWizard
```

For scripted planning, start with:

```powershell
Copy-GitHubRepository `
    -SourceRepository owner/source `
    -DestinationRepository owner/destination `
    -PlanOnly
```

## Choose Snapshot or FullHistory

| Need | Snapshot | FullHistory |
| --- | --- | --- |
| Publish the current default-branch contents as a clean repository | **Yes — intended default** | No |
| Preserve selected release states without retaining detailed development history | **Yes, with `-IncludeReleases`** | No; FullHistory preserves the original history instead |
| Preserve original commit ancestry | No | **Yes** |
| Preserve ordinary branches | No, only the approved default-branch/release checkpoint states are published | **Yes** |
| Preserve ordinary tags | No; only selected release tags are recreated with `-IncludeReleases` | **Yes** |
| Preserve signed historical commits / blame history | No | **Yes, as part of preserved Git history** |
| Preserve required Git LFS content | Yes, for LFS objects required by the approved Snapshot states | Yes, for reachable LFS objects required by the copied history |
| Preserve selected GitHub Releases and assets | **Yes, with `-IncludeReleases`** | **Yes, with `-IncludeReleases`** |
| Preserve original tag commit targets for selected releases | No; tags point to new Snapshot checkpoint commits | **Yes** |
| Restore supported repository settings | Yes, after content/release verification unless skipped | Yes, after content/release verification unless skipped |
| Restore transferable repository protection | Yes, as the final restoration stage unless skipped | Yes, as the final restoration stage unless skipped |

If preserving original ancestry, branches, tag targets, signed historical commits, or blame history matters, choose `FullHistory`. If the goal is a clean new history, choose `Snapshot`; opt into `-IncludeReleases` only when selected release checkpoints should be represented in that new history.

## Snapshot release checkpoints

The detailed normative rules live in the [Snapshot release-checkpoint contract](../product/product-contract.md#snapshot-release-checkpoint-contract). The user-facing distinction is:

- **Plain Snapshot** — creates one unrelated root commit representing reviewed current source HEAD.
- **`Snapshot -IncludeReleases`** — creates a new unrelated linear checkpoint history from the selected release states. Original source commit SHAs and detailed ancestry are intentionally not preserved.
- Each recreated selected release tag points to the new Snapshot checkpoint commit whose repository tree matches that reviewed source release state.
- Multiple selected releases that resolve to the same source commit share one checkpoint while retaining their separate tag/release identities.
- Checkpoint order comes from source Git ancestry, not GitHub Release publication dates. Incompatible/divergent selected release topology fails closed rather than inventing an order.
- After the last selected release checkpoint, a final current-state commit is created only when reviewed source HEAD is not state-equivalent to that latest selected release state.
- **`FullHistory -IncludeReleases`** remains different: it preserves the original Git history and original tag targets rather than constructing new checkpoint commits.

By default, `-IncludeReleases` selects stable, non-draft releases. The same release filters are available for Snapshot and FullHistory: include/exclude tag wildcard patterns, prerelease/draft opt-in, and newest-N limiting.

A Snapshot migration preserving selected releases is:

```powershell
Copy-GitHubRepository `
    -SourceRepository owner/source `
    -DestinationRepository owner/destination `
    -ContentMode Snapshot `
    -IncludeReleases
```

To narrow the selection:

```powershell
Copy-GitHubRepository `
    -SourceRepository owner/source `
    -DestinationRepository owner/destination `
    -ContentMode Snapshot `
    -IncludeReleases `
    -ReleaseTag 'v2.*' `
    -ReleaseCount 3
```

The wizard exposes the same Snapshot release opt-in and filters. It explains before selection that checkpoint commits are newly created and do not preserve original commit identities or ancestry, then uses the resulting real `Copy-GitHubRepository -PlanOnly` plan for review.

## What gets copied?

This matrix is the user-facing support summary for the current release line. The product contract remains authoritative if a detail requires normative interpretation.

| GitHub state | Snapshot | FullHistory | Notes |
| --- | --- | --- | --- |
| Default-branch file tree | **Copied** | **Copied** | Plain Snapshot publishes reviewed HEAD as one unrelated root; Snapshot with releases may add selected checkpoints plus an optional final HEAD state. FullHistory preserves history. |
| Commit ancestry | **Not copied** | **Copied** | Snapshot intentionally creates new unrelated history. |
| Other ordinary branches | **Not copied** | **Copied** | FullHistory preserves approved ordinary branch refs. |
| Ordinary Git tags | **Not copied generally** | **Copied** | Snapshot recreates only selected release tags when `-IncludeReleases` is used; FullHistory preserves approved ordinary tag refs. |
| Selected release tag targets | **New checkpoint commits** | **Original preserved commit targets** | Snapshot preserves selected release state, not source commit identity. |
| Reachable Git LFS objects | **Mode-specific** | **Copied** | Snapshot requires objects referenced by the approved Snapshot states; FullHistory covers reachable copied history. |
| Repository name / destination identity | **Created or replaced as selected** | **Created or replaced as selected** | Existing repositories are preserved through explicit archive-and-replace flows, never silently overwritten. |
| Visibility | **Inherited or explicitly selected** | **Inherited or explicitly selected** | Visibility changes require explicit acknowledgement for mutation. |
| Description and homepage | **Restored** | **Restored** | Restored after content/release verification unless settings are skipped. |
| Issues feature enabled/disabled | **Restored setting** | **Restored setting** | Issue **content/history is not copied**. |
| Projects / Wiki / Discussions enabled state | **Restored setting** | **Restored setting** | Discussion content/history is not copied. |
| Merge options / delete branch on merge / update-branch allowance / web commit signoff | **Restored** | **Restored** | Supported ordinary repository settings. |
| Topics | **Restored** | **Restored** | Supported ordinary repository setting. |
| Transferable repository-level rulesets | **Restored when safely transferable** | **Restored when safely transferable** | Security semantics are not weakened merely to make policy portable. |
| Transferable legacy default-branch protection | **Restored when safely transferable** | **Restored when safely transferable** | Non-transferable/inherited/identity-bound policy is reported as skipped/unsupported. |
| Pull requests | **Not copied** | **Not copied** | Historical/operational GitHub records remain outside the current scope. |
| Issues and issue history | **Not copied** | **Not copied** | Only the Issues enabled/disabled setting can be restored. |
| Discussion content/history | **Not copied** | **Not copied** | Only the Discussions enabled/disabled setting can be restored. |
| GitHub Releases / release history | **Optional** | **Optional** | `-IncludeReleases` recreates the exact approved selection and assets. Snapshot tags target new checkpoint commits; FullHistory tags retain original targets. |
| GitHub Release immutability state | **Not recreated** | **Not recreated** | Unsupported release property. |
| Linked GitHub Release discussions | **Not recreated** | **Not recreated** | Unsupported release property. |
| Original release IDs/timestamps/download counts | **Not preserved exactly** | **Not preserved exactly** | GitHub assigns new release IDs/timestamps; historical download counts are not recreated. |
| GitHub Actions configuration/activation | **Not restored** | **Not restored** | Workflow files are ordinary repository files when present in copied Git content, but Actions activation/configuration/history is not restored. |
| GitHub Actions workflow-run history | **Not copied** | **Not copied** | Historical operational state is outside scope. |
| GitHub Pages configuration | **Not restored** | **Not restored** | `-RestorePages` remains reserved and mutating execution rejects it. |
| Secret values | **Never copied or requested** | **Never copied or requested** | Secret values are deliberately excluded. |
| Webhooks / deploy keys / environments | **Not copied** | **Not copied** | Outside the current restoration scope. |
| Collaborator/team access | **Not copied** | **Not copied** | Outside the current restoration scope. |
| Packages / deployments | **Not copied** | **Not copied** | Outside the current restoration scope. |
| Stars / watchers / forks / traffic history | **Not copied** | **Not copied** | Historical/operational GitHub state is outside scope. |

`-SkipSettings` skips ordinary settings and repository-protection restoration. It does not suppress requested GitHub Release restoration.

## GitHub Release selection

GitHub Releases are separate from ordinary Git tags. `-IncludeReleases` controls which GitHub Release objects/assets participate in release preservation. In Snapshot mode, the selected release tags are recreated against new checkpoint commits representing the reviewed release states. In FullHistory mode, ordinary Git tags and original history are preserved first, and selected release objects/assets are recreated against those preserved tags.

A FullHistory migration with all stable, non-draft releases is:

```powershell
Copy-GitHubRepository `
    -SourceRepository owner/source `
    -DestinationRepository owner/destination `
    -ContentMode FullHistory `
    -IncludeReleases
```

Useful filters in either mode include:

```powershell
# Only v2 releases
-ReleaseTag 'v2.*'

# Specific releases
-ReleaseTag 'v1.5.0','v2.0.0'

# Exclude matching tags
-ReleaseExcludeTag '*-legacy'

# Include prereleases and drafts
-IncludePrerelease -IncludeDraftReleases

# Keep only the newest three after filtering
-ReleaseCount 3
```

Planning enumerates the source releases and records the exact selected release inventory, release metadata, tag target commit SHAs, whether a selected release is the source repository's Latest full release, and asset metadata. Snapshot plans additionally bind checkpoint topology/tree evidence derived from the reviewed selection. Execution does not rerun the filter as a live query. A release published after planning does not silently join the migration. If a selected release or its tag/state changes after planning, execution fails closed and requires a new plan.

Release names, bodies, draft/prerelease state, and assets are recreated where GitHub permits it; destination metadata and assets are read back and verified. If the source Latest release is selected, that Latest designation is also preserved and verified. GitHub-assigned release IDs, original creation/publication timestamps, historical download counts, release immutability state, and linked release discussions are not recreated exactly.

## Common scenarios

### Publish a clean Snapshot to a new destination

Use this when the current default-branch state should become a new repository with no prior Git ancestry. This corresponds primarily to `UC-SNAP-NEW`.

Expected outcome:

- the destination name is unused before mutation;
- execution is bound to the approved Snapshot source state;
- the approved current tree becomes exactly one unrelated destination root commit;
- required Snapshot LFS content is transferred and verified;
- supported settings/protection are restored after content verification unless skipped;
- provenance and verification evidence are returned.

Preview first with `-PlanOnly`, or use the wizard to review the actual plan before execution.

### Publish Snapshot with selected release checkpoints

Use this when you want clean new Git history but still want selected release states, tags, release metadata, and assets represented. This is not a substitute for FullHistory when original commit identity or ancestry matters.

Expected outcome:

- planning selects and binds the exact reviewed release set and checkpoint evidence;
- selected release states become new unrelated Snapshot checkpoint commits ordered by source Git ancestry;
- selected release tags point to those new checkpoint commits;
- original source commit SHAs/detailed ancestry are not preserved;
- an extra current-state commit appears only when reviewed HEAD differs in state from the latest selected release checkpoint;
- incompatible/divergent topology or selected source drift fails closed;
- selected release metadata/assets and Latest designation where applicable are restored and independently verified;
- supported settings/protection are restored after content/release verification unless skipped.

### Copy FullHistory to a new destination

Use this when ordinary commit ancestry, branches, tags, and history-related evidence must remain intact. This corresponds primarily to `UC-HIST-NEW`.

Expected outcome:

- the destination name is unused before mutation;
- approved ordinary branches/tags/reachable commits and default branch are copied;
- required reachable Git LFS objects are transferred;
- copied history and branch/tag identities are verified against the approved state;
- when `-IncludeReleases` is requested, the exact approved GitHub Release selection and assets are restored against preserved original tag targets;
- supported settings/protection are restored after content/release verification unless skipped.

### Replace an existing different destination

Use the explicit archive-and-replace flow when the desired destination already exists. This corresponds to `UC-DEST-REPLACE`.

The existing destination is **not overwritten**. The operation requires the replacement safety contract, including exact confirmation. When execution proceeds, the existing destination is first renamed to an unused archive name and its repository identity continuity is checked before the replacement is created.

If a later stage fails, the archive is preserved. The tool does not automatically delete the replacement or rename the archive back.

### Replace a repository under the same name

Use same-name replacement when the source's current `owner/name` must ultimately refer to the new Snapshot or FullHistory copy. This corresponds to `UC-SAME-REPLACE`.

The original repository is first preserved under an unused archive name. Where GitHub immutable repository identity is available, the archived repository must retain the approved original identity and the replacement must receive a distinct identity before content publication proceeds.

For release preservation, the archived original remains the approved source after rename and its selected release/tag state must still match the reviewed plan before restoration proceeds. Snapshot release replacement still constructs new checkpoint commits in the replacement repository; FullHistory release replacement preserves original history/tag targets.

This is intentionally a high-friction flow: exact confirmation is required and cannot be bypassed with `-Force` or `-Confirm:$false`.

### Preview without mutation

Use `-PlanOnly` when you want the full repository copy plan and approved source-state evidence without executing it. Use `-WhatIf` to exercise the PowerShell `ShouldProcess` preview boundary. These correspond to `SCN-PLAN-NOOP-01`.

Neither path should create, rename, publish, delete, restore releases, or restore GitHub resources.

### Run non-interactively

Use `Copy-GitHubRepository` for automation rather than the interactive wizard. This corresponds to `UC-AUTO-01`.

Automation must supply complete inputs and the safety acknowledgements required by the selected operation. `-NonInteractive` does not weaken replacement confirmation, source-state validation, release-state validation, topology validation, or verification requirements. Successful execution returns structured result/evidence suitable for downstream automation.

### Verify independently

Use `Test-GitHubRepositoryMigration` when you want a read-only comparison outside an execution plan. This corresponds to `UC-VERIFY-01`.

For Snapshot migrations that used `-IncludeReleases`, standalone verification can verify the expected checkpoint sequence, selected release tag targets, checkpoint tree/state equivalence, final destination state, and release metadata/assets using the reviewed Snapshot release evidence expected by that verification path. For FullHistory release migrations, release verification preserves the stricter original tag commit-identity comparison appropriate to FullHistory.

Execution-integrated verification remains bound to the immutable approved/copied evidence captured for the operation. Standalone current-state verification does not redefine the original migration's planning evidence.

## What happens when the source changes after planning?

Execution re-checks the source immediately before the first GitHub mutation. If the approved Git state has drifted, the plan is stale and execution fails closed before destination creation or rename proceeds from that plan. Generate and review a new plan instead of trying to force the old one through.

Selected GitHub Releases/tags/checkpoint states are also bound to their approved plan evidence. If a selected release or tag changed after planning, release/checkpoint execution fails closed and recovery evidence identifies the failure stage. A newly published release that was never selected by the approved plan is ignored rather than silently added.

The wizard follows the same rule: if a reviewed plan becomes stale, it returns to plan generation and requires review of the newly captured state.

## What happens after a partial failure?

A failure after mutation begins is not treated as if nothing happened. Depending on the stage reached, a destination or archive may already exist and checkpoint commits, tags, content, or releases may already have been published.

The product's recovery principle is preservation over automatic rollback:

- repositories are not automatically deleted;
- archives are not automatically renamed back;
- created Snapshot checkpoint commits/tags and destination releases already restored before a later failure are not automatically deleted;
- completed and failed stages are captured in durable recovery evidence when possible;
- known original/archive/replacement identities and available planned/copied content/release evidence are retained for diagnosis.

See the [troubleshooting and recovery guide](troubleshooting-recovery.md) for step-by-step recovery actions.

## Where to go next

- Detailed command syntax: [`docs/reference/commands/`](../reference/commands/README.md)
- Normative product behavior: [`product-contract.md`](../product/product-contract.md)
- Capability/use-case/scenario traceability: [`product-model.md`](../product/product-model.md)
- Installation and bootstrap trust: [`installation-security.md`](../security/installation-security.md)
- Protection support details: [`protection-restoration.md`](protection-restoration.md)
- Architecture and safety boundaries: [`architecture.md`](../product/architecture.md)