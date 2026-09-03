---
title: "How to Copy or Migrate a GitHub Repository"
description: "Learn how to copy or migrate a GitHub repository with PowerShell using Snapshot or FullHistory, optional release preservation, and opt-in GitHub Pages restoration with reviewed evidence and recovery safeguards."
---

# User guide: capabilities and common scenarios

This guide is the user-facing path for evaluating, planning, running, and verifying Copy GitHub Repository operations.

For normative behavior, safety invariants, and supported scope, see [`product-contract.md`](../product/product-contract.md) and the [GitHub Pages migration contract](../product/github-pages-migration-contract.md). For detailed command syntax and parameters, see the [`commands`](../reference/commands/README.md) reference. Stable capability, use-case, and behavioral-scenario IDs are defined in [`product-model.md`](../product/product-model.md).

## Start here

A typical user journey is:

1. **Choose the outcome.** Use `Snapshot` for a clean publication with newly created Git history. Plain Snapshot creates one unrelated current-state root commit; `Snapshot -IncludeReleases` creates a new unrelated checkpoint history from selected release states. Use `FullHistory` when original ordinary Git history must be preserved.
2. **Choose GitHub-side state deliberately.** Add `-RestorePages` only when supported GitHub-side Pages configuration should be restored. Site/workflow files are ordinary Git content and are distinct from the Pages service configuration.
3. **Install and authenticate.** Install the stable module from PowerShell Gallery, then authenticate GitHub CLI for `github.com`.
4. **Preview before mutation.** Use the guided wizard or `Copy-GitHubRepository -PlanOnly` to review source/destination, content mode, visibility, settings choices, immutable source-state evidence, selected releases/checkpoints, reviewed Pages evidence when requested, and any replacement/archive plan.
5. **Execute deliberately.** Replacement operations require the safety acknowledgements and exact confirmation defined by the product contract. Custom-domain handoff also depends on verified archive/replacement identity and reviewed ownership evidence.
6. **Verify the result.** Successful execution verifies content before reporting success. Requested release and Pages restoration are independently read back against reviewed evidence. External DNS, domain verification, and certificate readiness remain separate external state.
7. **Preserve evidence if something fails.** If mutation has started, do not assume rollback occurred. The tool preserves repositories and writes recovery evidence when possible; use the [troubleshooting and recovery guide](troubleshooting-recovery.md) and [Pages migration and recovery guide](github-pages-migration.md).

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
| Preserve commit ancestry | No | **Yes** |
| Preserve ordinary branches | No, only the approved default-branch/release checkpoint states are published | **Yes** |
| Preserve ordinary tags | No; only selected release tags are recreated with `-IncludeReleases` | **Yes** |
| Preserve signed historical commits / blame history | No | **Yes, as part of preserved Git history** |
| Preserve required Git LFS content | Yes, for LFS objects required by the approved Snapshot states | Yes, for reachable LFS objects required by the copied history |
| Preserve selected GitHub Releases and assets | **Yes, with `-IncludeReleases`** | **Yes, with `-IncludeReleases`** |
| Preserve original tag commit targets for selected releases | No; tags point to new Snapshot checkpoint commits | **Yes** |
| Restore supported GitHub-side Pages configuration | **Yes, with `-RestorePages`, when representable** | **Yes, with `-RestorePages`** |
| Restore supported repository settings | Yes, after content/release verification unless skipped | Yes, after content/release verification unless skipped |
| Restore transferable repository protection | Yes, as the final restoration stage unless skipped | Yes, as the final restoration stage unless skipped |

If preserving original ancestry, branches, tag targets, signed historical commits, or blame history matters, choose `FullHistory`. If the goal is a clean new history, choose `Snapshot`; opt into `-IncludeReleases` only when selected release checkpoints should be represented in that new history. Pages restoration is orthogonal to content mode, but branch/path-based Pages must be representable by the selected destination Git state.

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

This matrix is the user-facing support summary for the current release line. The product contracts remain authoritative if a detail requires normative interpretation.

| GitHub state | Snapshot | FullHistory | Notes |
| --- | --- | --- | --- |
| Default-branch file tree | **Copied** | **Copied** | Plain Snapshot publishes reviewed HEAD as one unrelated root; Snapshot with releases may add selected checkpoints plus an optional final HEAD state. FullHistory preserves history. |
| Commit ancestry | **Not copied** | **Copied** | Snapshot intentionally creates new unrelated history. |
| Other ordinary branches | **Not copied** | **Copied** | FullHistory preserves approved ordinary branch refs. |
| Ordinary Git tags | **Not copied generally** | **Copied** | Snapshot recreates only selected release tags when `-IncludeReleases` is used; FullHistory preserves approved ordinary tag refs. |
| Selected release tag targets | **New checkpoint commits** | **Original preserved commit targets** | Snapshot preserves selected release state, not source commit identity. |
| Reachable Git LFS objects | **Mode-specific** | **Copied** | Snapshot requires objects referenced by approved Snapshot states; FullHistory covers reachable copied history. |
| Repository name / destination identity | **Created or replaced as selected** | **Created or replaced as selected** | Existing repositories are preserved through explicit archive-and-replace flows, never silently overwritten. |
| Visibility | **Inherited or explicitly selected** | **Inherited or explicitly selected** | Visibility changes require explicit acknowledgement for mutation. |
| Description and homepage | **Restored** | **Restored** | Restored after content/release verification unless settings are skipped. |
| Issues feature enabled/disabled | **Restored setting** | **Restored setting** | Issue **content/history is not copied**. |
| Projects / Wiki / Discussions enabled state | **Restored setting** | **Restored setting** | Discussion content/history is not copied. |
| Merge options / delete branch on merge / update-branch allowance / web commit signoff | **Restored** | **Restored** | Supported ordinary repository settings. |
| Topics | **Restored** | **Restored** | Supported ordinary repository setting. |
| Transferable repository-level rulesets | **Restored when safely transferable** | **Restored when safely transferable** | Security semantics are not weakened merely to make policy portable. |
| Transferable legacy default-branch protection | **Restored when safely transferable** | **Restored when safely transferable** | Non-transferable/inherited/identity-bound policy is reported as skipped/unsupported. |
| Pull requests | **Not copied** | **Not copied** | Historical/operational GitHub records remain outside current scope. |
| Issues and issue history | **Not copied** | **Not copied** | Only the Issues enabled/disabled setting can be restored. |
| Discussion content/history | **Not copied** | **Not copied** | Only the Discussions enabled/disabled setting can be restored. |
| GitHub Releases / release history | **Optional** | **Optional** | `-IncludeReleases` recreates the exact approved selection and assets. Snapshot tags target new checkpoint commits; FullHistory tags retain original targets. |
| GitHub Release immutability state | **Not recreated** | **Not recreated** | Unsupported release property. |
| Linked GitHub Release discussions | **Not recreated** | **Not recreated** | Unsupported release property. |
| Original release IDs/timestamps/download counts | **Not preserved exactly** | **Not preserved exactly** | GitHub assigns new release IDs/timestamps; historical download counts are not recreated. |
| Site files, `CNAME`, Jekyll config, Pages workflow files | **Copied when part of approved Git state** | **Copied when part of approved Git state** | These are ordinary Git content, not proof of GitHub-side Pages preservation. |
| GitHub Actions configuration/activation generally | **Not restored** | **Not restored** | Pages activation is controlled only as required by the Pages migration safety contract; general Actions policy/config/history remains outside scope. |
| GitHub Actions workflow-run history | **Not copied** | **Not copied** | Historical operational state is outside scope. |
| GitHub Pages configured state and publishing mode | **Optional with `-RestorePages`** | **Optional with `-RestorePages`** | Captured in reviewed evidence, restored where supported, and independently verified. |
| Pages branch/path source | **Conditional** | **Conditional** | Exact reviewed source is restored only when representable; Snapshot does not invent a missing publishing branch or redirect to a substitute. |
| Pages custom-domain binding | **Optional with `-RestorePages`** | **Optional with `-RestorePages`** | GitHub-side binding is restored when ownership is safe; replacement uses explicit archive-to-replacement handoff. |
| Pages HTTPS enforcement intent | **Conditional** | **Conditional** | Restored/read back where deterministic; certificate readiness may remain externally pending. |
| External DNS records | **Not copied or modified** | **Not copied or modified** | External state, never migration authority. |
| Account/organization domain verification | **Not transferred** | **Not transferred** | External identity/policy prerequisite. |
| Certificate issuance/propagation | **Not migrated** | **Not migrated** | Reported as external readiness; pending provisioning is not by itself deterministic migration failure. |
| Secret values | **Never copied or requested** | **Never copied or requested** | Includes Actions/environment secret values. |
| Webhooks / deploy keys / environments | **Not copied** | **Not copied** | Outside current restoration scope. |
| Collaborator/team access | **Not copied** | **Not copied** | Outside current restoration scope. |
| Packages / deployments | **Not copied** | **Not copied** | Outside current restoration scope. |
| Stars / watchers / forks / traffic history | **Not copied** | **Not copied** | Historical/operational GitHub state is outside scope. |

`-SkipSettings` skips ordinary settings and repository-protection restoration. It does not suppress requested GitHub Release or Pages restoration.

For the detailed Pages support boundary, see [GitHub Pages migration and recovery](github-pages-migration.md).

## GitHub Release selection

GitHub Releases are separate from ordinary Git tags. `-IncludeReleases` controls which GitHub Release objects/assets participate in release preservation. In Snapshot mode, selected release tags are recreated against new checkpoint commits representing reviewed release states. In FullHistory mode, ordinary Git tags and original history are preserved first, and selected release objects/assets are recreated against those preserved tags.

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

Planning enumerates source releases and records the exact selected release inventory, metadata, tag targets, Latest status, and assets. Snapshot plans additionally bind checkpoint topology/tree evidence. Execution does not rerun the filter as a live query. A release published after planning does not silently join the migration. If a selected release or its tag/state changes after planning, execution fails closed and requires a new plan.

Release names, bodies, draft/prerelease state, and assets are recreated where GitHub permits it; destination metadata and assets are read back and verified. If the source Latest release is selected, that Latest designation is also preserved and verified. GitHub-assigned release IDs, original creation/publication timestamps, historical download counts, release immutability state, and linked release discussions are not recreated exactly.

## GitHub Pages restoration

`-RestorePages` is an explicit opt-in for supported GitHub-side Pages state. It is independent of whether site/workflow files are copied as Git content.

```powershell
Copy-GitHubRepository `
    -SourceRepository owner/source `
    -DestinationRepository owner/destination `
    -RestorePages
```

Planning captures immutable Pages evidence. Execution revalidates it immediately before Pages mutation; material drift fails closed. Actions-based Pages restores the reviewed `workflow` build type. Branch/path-based Pages restores the exact reviewed branch and `/` or `/docs` source only when the destination Git state can represent it safely.

The Pages stage occurs after Git/LFS content verification, requested release restoration, and ordinary supported settings, but before repository/branch protection. Copied Pages workflow activation is controlled until the approved restoration/verification boundary so workflow presence is not mistaken for successful Pages migration.

For custom domains, only the GitHub-side binding is in scope. External DNS is not queried as migration authority or mutated. Domain-verification ownership and certificate issuance/propagation remain external. HTTPS intent is restored where GitHub allows deterministic mutation/read-back; pending certificate provisioning may be reported as external readiness rather than a migration failure.

Secrets are never copied.

See [GitHub Pages migration and recovery](github-pages-migration.md) for detailed replacement handoff, verification, and recovery behavior.

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

### Restore Pages to a new destination

Use `-RestorePages` when GitHub-side Pages configuration must accompany either Snapshot or FullHistory.

Expected outcome:

- the reviewed plan explicitly shows source Pages configuration and representability;
- destination Git content is verified before Pages restoration;
- Actions-based or representable branch/path Pages is restored from reviewed evidence;
- supported destination Pages state is independently read back;
- external DNS/domain-verification/certificate state is reported separately and not claimed as migrated; and
- repository/branch protection is restored after Pages.

If the source publishing branch/path cannot exist under the selected content mode, the operation fails closed instead of redirecting Pages to another source.

### Replace an existing different destination

Use the explicit archive-and-replace flow when the desired destination already exists. This corresponds to `UC-DEST-REPLACE`.

The existing destination is **not overwritten**. The operation requires the replacement safety contract, including exact confirmation. When execution proceeds, the existing destination is first renamed to an unused archive name and its repository identity continuity is checked before the replacement is created.

If `-RestorePages` is requested with a reviewed custom domain, the domain is treated as ownership-sensitive. The archive/replacement identities and handoff prerequisites are verified before any domain release/claim. External DNS remains untouched.

If a later stage fails, the archive is preserved. The tool does not automatically delete the replacement, rename the archive back, or destructively roll back uncertain custom-domain ownership.

### Replace a repository under the same name

Use same-name replacement when the source's current `owner/name` must ultimately refer to the new Snapshot or FullHistory copy. This corresponds to `UC-SAME-REPLACE`.

The original repository is first preserved under an unused archive name. Where GitHub immutable repository identity is available, the archived repository must retain the approved original identity and the replacement must receive a distinct identity before content publication proceeds.

For release preservation, the archived original remains the approved source after rename and its selected release/tag state must still match the reviewed plan before restoration proceeds. Snapshot release replacement still constructs new checkpoint commits in the replacement repository; FullHistory release replacement preserves original history/tag targets.

For reviewed Pages custom domains, same-name replacement verifies that the preserved archive still has the approved identity and exact reviewed domain binding before releasing it. The exact domain is then claimed by the replacement and independently read back. Recovery evidence records archive release and replacement claim/read-back state so a partial handoff can be diagnosed without guessing. No external DNS mutation or automatic destructive rollback is performed.

This is intentionally a high-friction flow: exact confirmation is required and cannot be bypassed with `-Force` or `-Confirm:$false`.

### Preview without mutation

Use `-PlanOnly` when you want the full repository copy plan and approved source-state evidence without executing it. Use `-WhatIf` to exercise the PowerShell `ShouldProcess` preview boundary. These correspond to `SCN-PLAN-NOOP-01`.

Neither path should create, rename, publish, delete, restore releases, restore Pages, or restore other GitHub resources.

### Run non-interactively

Use `Copy-GitHubRepository` for automation rather than the interactive wizard. This corresponds to `UC-AUTO-01`.

Automation must supply complete inputs and the safety acknowledgements required by the selected operation. `-NonInteractive` does not weaken replacement confirmation, source-state validation, release/Pages-state validation, topology/representability validation, identity checks, or verification requirements. Successful execution returns structured result/evidence suitable for downstream automation.

### Verify independently

Use `Test-GitHubRepositoryMigration` when you want a read-only comparison outside an execution plan. This corresponds to `UC-VERIFY-01`.

For Snapshot migrations that used `-IncludeReleases`, standalone verification can verify the expected checkpoint sequence, selected release tag targets, checkpoint tree/state equivalence, final destination state, and release metadata/assets using the reviewed Snapshot release evidence expected by that verification path. For FullHistory release migrations, release verification preserves the stricter original tag commit-identity comparison appropriate to FullHistory.

Pages verification is separately read-only and compares supported destination GitHub-side Pages state with reviewed Pages evidence where applicable. DNS records, account/organization domain verification, and certificate issuance/propagation are external readiness, not proof of migrated state.

Execution-integrated verification remains bound to the immutable approved/copied evidence captured for the operation. Standalone current-state verification does not redefine the original migration's planning evidence.

## What happens when the source changes after planning?

Execution re-checks the source immediately before the first GitHub mutation. If approved Git state has drifted, the plan is stale and execution fails closed before destination creation or rename proceeds from that plan. Generate and review a new plan instead of trying to force the old one through.

Selected GitHub Releases/tags/checkpoint states are also bound to approved plan evidence. If a selected release or tag changed after planning, release/checkpoint execution fails closed and recovery evidence identifies the failure stage. A newly published release that was never selected by the approved plan is ignored rather than silently added.

When `-RestorePages` is requested, relevant source Pages configuration is revalidated again immediately before Pages mutation. Changes to configured state, build type, publishing source, custom domain, or other supported mutation-driving Pages state fail closed before Pages mutation. Execution does not silently adopt the newer live state.

The wizard follows the same reviewed-plan authority: stale plan-affecting state returns the user to plan generation/review rather than mutating from an unreviewed replacement plan.

## What happens after a partial failure?

A failure after mutation begins is not treated as if nothing happened. Depending on the stage reached, a destination or archive may already exist and checkpoint commits, tags, content, releases, or Pages configuration may already have been published/restored.

The product's recovery principle is preservation over automatic rollback:

- repositories are not automatically deleted;
- archives are not automatically renamed back;
- created Snapshot checkpoint commits/tags and destination releases already restored before a later failure are not automatically deleted;
- a partial custom-domain handoff is not destructively rolled back when current ownership is uncertain;
- Pages recovery evidence identifies the reviewed configuration, activation-guard state, last successful Pages stage, and custom-domain release/claim/read-back state where applicable;
- external DNS/domain-verification/certificate readiness is recorded/reported separately from migrated GitHub-side state; and
- completed and failed stages plus known repository identities and available approved evidence are retained for diagnosis.

See the [troubleshooting and recovery guide](troubleshooting-recovery.md) and [GitHub Pages migration and recovery](github-pages-migration.md) for step-by-step recovery actions.

## Where to go next

- Detailed command syntax: [`docs/reference/commands/`](../reference/commands/README.md)
- GitHub Pages operation and recovery: [`github-pages-migration.md`](github-pages-migration.md)
- Normative product behavior: [`product-contract.md`](../product/product-contract.md)
- Normative Pages behavior: [`github-pages-migration-contract.md`](../product/github-pages-migration-contract.md)
- Capability/use-case/scenario traceability: [`product-model.md`](../product/product-model.md)
- Installation and bootstrap trust: [`installation-security.md`](../security/installation-security.md)
- Protection support details: [`protection-restoration.md`](protection-restoration.md)
- Architecture and safety boundaries: [`architecture.md`](../product/architecture.md)