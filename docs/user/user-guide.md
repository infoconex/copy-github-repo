# User guide: capabilities and common scenarios

This guide is the user-facing path for evaluating, planning, running, and verifying Copy GitHub Repository operations.

For normative behavior, safety invariants, and supported scope, see [`product-contract.md`](../product/product-contract.md). For detailed command syntax and parameters, see the [`commands`](../reference/commands/README.md) reference. Stable capability, use-case, and behavioral-scenario IDs are defined in [`product-model.md`](../product/product-model.md).

## Start here

A typical user journey is:

1. **Choose the outcome.** Use `Snapshot` for a clean publication whose Git history begins with one unrelated root commit, or `FullHistory` when ordinary Git history must be preserved.
2. **Install and authenticate.** Install the stable module from PowerShell Gallery, then authenticate GitHub CLI for `github.com`.
3. **Preview before mutation.** Use the guided wizard or `Copy-GitHubRepository -PlanOnly` to review the source, destination, mode, visibility, settings choices, immutable source-state evidence, and any replacement/archive plan.
4. **Execute deliberately.** Replacement operations require the safety acknowledgements and exact confirmation defined by the product contract.
5. **Verify the result.** Successful execution verifies content before reporting success and returns structured evidence. `Test-GitHubRepositoryMigration` is available for a separate current-state comparison.
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
| Preserve commit ancestry | No | **Yes** |
| Preserve ordinary branches | No, only the approved default-branch tree is published | **Yes** |
| Preserve ordinary tags | No | **Yes** |
| Preserve signed historical commits / blame history | No | **Yes, as part of preserved Git history** |
| Preserve required Git LFS content | Yes, for LFS objects required by the approved Snapshot tree | Yes, for reachable LFS objects required by the copied history |
| Restore supported repository settings | Yes, after content verification unless skipped | Yes, after content verification unless skipped |
| Restore transferable repository protection | Yes, as the final restoration stage unless skipped | Yes, as the final restoration stage unless skipped |

If preserving ancestry, branches, or tags matters, choose `FullHistory`. If the goal is to publish the current state without the development history, choose `Snapshot`.

## What gets copied?

This matrix is the user-facing support summary for the current `0.1.x` release line. The product contract remains authoritative if a detail requires normative interpretation.

| GitHub state | Snapshot | FullHistory | Notes |
| --- | --- | --- | --- |
| Default-branch file tree | **Copied** | **Copied** | Snapshot publishes the approved tree as one unrelated root commit; FullHistory preserves its history. |
| Commit ancestry | **Not copied** | **Copied** | Snapshot intentionally severs ancestry. |
| Other ordinary branches | **Not copied** | **Copied** | FullHistory preserves approved ordinary branch refs. |
| Ordinary Git tags | **Not copied** | **Copied** | FullHistory preserves approved ordinary tag refs. |
| Reachable Git LFS objects | **Mode-specific** | **Copied** | Snapshot requires objects referenced by the approved Snapshot content; FullHistory covers reachable copied history. |
| Repository name / destination identity | **Created or replaced as selected** | **Created or replaced as selected** | Existing repositories are preserved through explicit archive-and-replace flows, never silently overwritten. |
| Visibility | **Inherited or explicitly selected** | **Inherited or explicitly selected** | Visibility changes require explicit acknowledgement for mutation. |
| Description and homepage | **Restored** | **Restored** | Restored after content verification unless settings are skipped. |
| Issues feature enabled/disabled | **Restored setting** | **Restored setting** | Issue **content/history is not copied**. |
| Projects / Wiki / Discussions enabled state | **Restored setting** | **Restored setting** | Discussion content/history is not copied. |
| Merge options / delete branch on merge / update-branch allowance / web commit signoff | **Restored** | **Restored** | Supported ordinary repository settings. |
| Topics | **Restored** | **Restored** | Supported ordinary repository setting. |
| Transferable repository-level rulesets | **Restored when safely transferable** | **Restored when safely transferable** | Security semantics are not weakened merely to make policy portable. |
| Transferable legacy default-branch protection | **Restored when safely transferable** | **Restored when safely transferable** | Non-transferable/inherited/identity-bound policy is reported as skipped/unsupported. |
| Pull requests | **Not copied** | **Not copied** | Historical/operational GitHub records are outside the current `0.1.x` scope. |
| Issues and issue history | **Not copied** | **Not copied** | Only the Issues enabled/disabled setting can be restored. |
| Discussion content/history | **Not copied** | **Not copied** | Only the Discussions enabled/disabled setting can be restored. |
| GitHub Releases / release history | **Not copied** | **Not copied** | Git tags may be preserved in FullHistory; GitHub Release objects are separate and not copied. |
| GitHub Actions configuration/activation | **Not restored** | **Not restored** | `-EnableActionsAfterMigration` is not implemented for mutating execution in the current `0.1.x` release line. Workflow files are ordinary repository files when present in copied Git content, but Actions activation/configuration/history is not restored. |
| GitHub Actions workflow-run history | **Not copied** | **Not copied** | Historical operational state is outside scope. |
| GitHub Pages configuration | **Not restored** | **Not restored** | `-RestorePages` is not implemented for mutating execution in the current `0.1.x` release line. |
| Secret values | **Never copied or requested** | **Never copied or requested** | Secret values are deliberately excluded. |
| Webhooks / deploy keys / environments | **Not copied** | **Not copied** | Outside the current `0.1.x` restoration scope. |
| Collaborator/team access | **Not copied** | **Not copied** | Outside the current `0.1.x` restoration scope. |
| Packages / deployments | **Not copied** | **Not copied** | Outside the current `0.1.x` restoration scope. |
| Stars / watchers / forks / traffic history | **Not copied** | **Not copied** | Historical/operational GitHub state is outside scope. |

`-SkipSettings` skips both ordinary settings and repository-protection restoration.

## Common scenarios

### Publish a clean Snapshot to a new destination

Use this when the current default-branch state should become a new repository with no prior Git ancestry. This corresponds primarily to `UC-SNAP-NEW`.

Expected outcome:

- the destination name is unused before mutation;
- execution is bound to the approved Snapshot source state;
- the approved tree becomes exactly one unrelated destination root commit;
- required Snapshot LFS content is transferred and verified;
- supported settings/protection are restored after content verification unless skipped;
- provenance and verification evidence are returned.

Preview first with `-PlanOnly`, or use the wizard to review the actual plan before execution.

### Copy FullHistory to a new destination

Use this when ordinary commit ancestry, branches, tags, and history-related evidence must remain intact. This corresponds primarily to `UC-HIST-NEW`.

Expected outcome:

- the destination name is unused before mutation;
- approved ordinary branches/tags/reachable commits and default branch are copied;
- required reachable Git LFS objects are transferred;
- copied history and branch/tag identities are verified against the approved state;
- supported settings/protection are restored after content verification unless skipped.

### Replace an existing different destination

Use the explicit archive-and-replace flow when the desired destination already exists. This corresponds to `UC-DEST-REPLACE`.

The existing destination is **not overwritten**. The operation requires the replacement safety contract, including exact confirmation. When execution proceeds, the existing destination is first renamed to an unused archive name and its repository identity continuity is checked before the replacement is created.

If a later stage fails, the archive is preserved. The tool does not automatically delete the replacement or rename the archive back.

### Replace a repository under the same name

Use same-name replacement when the source's current `owner/name` must ultimately refer to the new Snapshot or FullHistory copy. This corresponds to `UC-SAME-REPLACE`.

The original repository is first preserved under an unused archive name. Where GitHub immutable repository identity is available, the archived repository must retain the approved original identity and the replacement must receive a distinct identity before content publication proceeds.

This is intentionally a high-friction flow: exact confirmation is required and cannot be bypassed with `-Force` or `-Confirm:$false`.

### Preview without mutation

Use `-PlanOnly` when you want the full repository copy plan and approved source-state evidence without executing it. Use `-WhatIf` to exercise the PowerShell `ShouldProcess` preview boundary. These correspond to `SCN-PLAN-NOOP-01`.

Neither path should create, rename, publish, delete, or restore GitHub resources.

### Run non-interactively

Use `Copy-GitHubRepository` for automation rather than the interactive wizard. This corresponds to `UC-AUTO-01`.

Automation must supply complete inputs and the safety acknowledgements required by the selected operation. `-NonInteractive` does not weaken replacement confirmation, source-state validation, or verification requirements. Successful execution returns structured result/evidence suitable for downstream automation.

### Verify independently

Use `Test-GitHubRepositoryMigration` when you want a read-only comparison of the **current** source and destination repository states outside an execution plan. This corresponds to `UC-VERIFY-01`.

This is different from execution-integrated verification, which compares the destination against the approved/copied evidence captured for the operation rather than assuming the source has remained unchanged afterward.

## What happens when the source changes after planning?

Execution re-checks the source immediately before the first GitHub mutation. If the approved state has drifted, the plan is stale and execution fails closed before destination creation or rename proceeds from that plan. Generate and review a new plan instead of trying to force the old one through.

The wizard follows the same rule: if a reviewed plan becomes stale, it returns to plan generation and requires review of the newly captured state.

## What happens after a partial failure?

A failure after mutation begins is not treated as if nothing happened. Depending on the stage reached, a destination or archive may already exist and content may already have been published.

The product's recovery principle is preservation over automatic rollback:

- repositories are not automatically deleted;
- archives are not automatically renamed back;
- completed and failed stages are captured in durable recovery evidence when possible;
- known original/archive/replacement identities and available planned/copied content evidence are retained for diagnosis.

See the [troubleshooting and recovery guide](troubleshooting-recovery.md) for step-by-step recovery actions.

## Where to go next

- Detailed command syntax: [`docs/reference/commands/`](../reference/commands/README.md)
- Normative product behavior: [`product-contract.md`](../product/product-contract.md)
- Capability/use-case/scenario traceability: [`product-model.md`](../product/product-model.md)
- Installation and bootstrap trust: [`installation-security.md`](../security/installation-security.md)
- Protection support details: [`protection-restoration.md`](protection-restoration.md)
- Architecture and safety boundaries: [`architecture.md`](../product/architecture.md)
