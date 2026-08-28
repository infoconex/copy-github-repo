---
title: "CopyGitHubRepo Command Design – PowerShell API and Safety Contracts"
description: "Review CopyGitHubRepo public command design, immutable planning, Snapshot and FullHistory execution, settings and protection restoration, replacement safety, wizard delegation, and output contracts."
---

# Command design

## Public commands

### `Copy-GitHubRepository`

Plans and executes a safe GitHub repository copy/publication. `Snapshot` is the default and means **clean current-state publication**: the current source default-branch tree becomes one unrelated root commit in the destination. `FullHistory` is the explicit history-preserving alternative.

Primary parameters:

```text
-SourceRepository owner/name
-DestinationRepository owner/name
-ContentMode Snapshot|FullHistory
-DestinationVisibility public|private|internal
-ArchiveRepositoryName name
-SameNameConfirmation text
-ExistingDestinationArchiveName name
-ExistingDestinationConfirmation text
-CommitMessage text
-RestorePages
-EnableActionsAfterMigration
-SkipSettings
-PlanOnly
-NonInteractive
-OutputMode Interactive|Plain|Json
-ReportPath path
-HostName hostname
-Force
-WhatIf
-Confirm
-Verbose
```

`-HostName` is retained for future extensibility, but `v0.1.0` supports only `github.com`, case-insensitively.

### Planning

Planning is read-only:

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -PlanOnly
```

`-PlanOnly` discovers the source, rejects an empty source, validates destination/archive availability, captures supported repository configuration/protection evidence, captures immutable source-state evidence for the selected content mode, and returns a `CopyGitHubRepo.MigrationPlan` without mutation.

Snapshot source-state evidence includes the approved default branch, commit SHA, tree SHA, repository identity when available, and required Git LFS evidence. FullHistory source-state evidence includes the approved default branch, ordinary branch/tag ref targets, reachable commit count, branch-tip trees, repository identity when available, and Git LFS availability.

Mutating execution is bound to the exact reviewed plan. Immediately before the first mutation, the source is checked against the plan; a mismatch fails closed with `SourceStateChangedSincePlanning` and requires a new plan to be generated and reviewed. The cloned source workspace is also checked before publication so source movement between preflight and clone cannot silently substitute unreviewed content.

The plan describes ordered execution. For Snapshot, the normal high-level order is:

1. create/preserve the destination as required;
2. copy the clean Snapshot and required Git LFS content;
3. reload and verify the destination content/history shape against the approved/copied evidence;
4. restore and verify ordinary supported settings;
5. restore and verify transferable repository protection last.

Protection is intentionally not activated before the initial content copy because doing so could block the repository copy itself.

### Snapshot execution

Without `-ContentMode`, Snapshot is used:

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination
```

The command creates a fresh destination when required, copies the approved source default-branch tree into one unrelated root commit, transfers required Git LFS objects, verifies tree equality and the one-root-commit history shape against the approved/copied evidence, then restores configuration.

The new Snapshot commit SHA is expected to differ from the source commit SHA because the destination commit has no parent and is a new Git object. Tree identity is the clean-publication content invariant.

Successful Snapshot execution also records publication provenance in the structured result and Markdown/JSON report: approved source state, actual copied source evidence, source/destination identities when available, destination root commit/tree, UTC timestamp, and verification outcome. Same-name Snapshot results additionally record archive identity continuity and replacement identity distinction. Provenance does not add any file, tag, note, parent, or extra commit to the destination.

### FullHistory execution

FullHistory is explicit:

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -ContentMode FullHistory
```

FullHistory preserves the approved ordinary branches, tags, reachable history, source default branch, and reachable Git LFS objects. Verification compares the destination branch/tag targets, reachable commit counts, branch-tip trees, default branch, and Git LFS availability with the approved/copy evidence rather than rereading a moving source ref set.

### Ordinary settings restoration

Supported settings are description, homepage, Issues/Projects/Wiki/Discussions enabled states, squash/merge-commit/rebase/auto-merge flags, delete-branch-on-merge, update-branch allowance, web commit signoff, and repository topics.

Restoration is differential, and every source-available supported value is read back from GitHub and verified. There is no legacy description-only compatibility path.

### Repository protection restoration

Repository protection is a separate final stage after content verification and ordinary settings. `v0.1.0` restores:

- transferable repository-level rulesets;
- transferable legacy protection for the source default branch.

A ruleset or legacy protection configuration is not silently weakened to remove source-specific identities. Bypass actors, deployment dependencies, integration-bound checks, user/team/app push restrictions, and identity-bound review-dismissal restrictions are surfaced as skipped/unsupported semantics. Inherited organization rulesets are not copied.

After restoration, destination protection is reloaded and compared with the normalized source configuration. See [`protection-restoration.md`](../user/protection-restoration.md) for the detailed support matrix.

`-SkipSettings` skips both ordinary settings restoration and protection restoration.

### Replacement flows

Same-name replacement is implemented for both content modes. It requires an unused archive name plus exact confirmation naming source, archive, and replacement:

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/source `
    -ArchiveRepositoryName source-archive `
    -SameNameConfirmation 'SOURCE=infoconex/source;ARCHIVE=infoconex/source-archive;REPLACEMENT=infoconex/source' `
    -NonInteractive `
    -Force
```

`-Force` and `-Confirm:$false` do not bypass exact replacement confirmation.

Same-name safety uses immutable GitHub repository identity plus the same approved source-state evidence used by normal execution. The source/archive immutable ID must remain the same after rename, the archived source must still match the approved content evidence, and the replacement repository must receive a distinct immutable ID before content copy proceeds. Snapshot verifies the approved default-branch content evidence; FullHistory verifies approved branch/tag targets, reachable commit count, branch-tip trees, default branch, and reachable Git LFS availability.

A different existing destination can also be archived and replaced only through the explicit existing-destination archive and confirmation parameters. Approved source state is checked before the existing destination is renamed. Existing repositories are preserved, not silently deleted.

### Mutation and recovery

- `-WhatIf` returns the execution plan and does not create or rename repositories.
- Any destination visibility that differs from the source requires `-Force` for mutation.
- Non-interactive mutation requires `-Force`.
- `-RestorePages` and `-EnableActionsAfterMigration` are reserved plan switches; mutating execution rejects them because those operations are not implemented.
- `-ReportPath` writes Markdown by default or JSON for `.json`.
- Post-mutation terminating failures write durable recovery evidence before the original error is rethrown.
- Recovery retains planned source state and actual copied source evidence when available and never automatically deletes or renames repositories.

### `Start-CopyGitHubRepositoryWizard`

Provides the interactive human-facing orchestration layer while keeping `Copy-GitHubRepository` as the deterministic public planning/execution API.

```powershell
Start-CopyGitHubRepositoryWizard
```

The wizard uses `Get-GitHubRepository` for discovery and native PowerShell interaction helpers for source selection, filtering, destination, content mode, visibility, supported-settings behavior, navigation, and final confirmation. Snapshot, source visibility, and configuration restoration are the defaults.

Before mutation the wizard calls the real `Copy-GitHubRepository -PlanOnly` path, displays the **Repository copy plan**, and requires an explicit Execute decision. Back is available while configuration is editable; changing plan-affecting state invalidates the old plan. Cancel is a normal no-change result before mutation.

After Execute, the wizard sends that exact reviewed plan object to the private approved-plan application boundary. It does not reconstruct a second equivalent-looking request. If the source no longer matches the approved state, the wizard presents the expected application-level stale-plan message, regenerates the plan for review, and performs no mutation from the stale plan.

The wizard does not duplicate repository copy, verification, provenance, settings/protection restoration, or recovery engines; it owns interactive presentation and orchestration around the shared application boundary.

### `Get-GitHubRepository`

Returns structured repository objects through two explicit parameter sets. `Search` is the default parameter set.

```text
ByRepository:
-Repository owner/name
-HostName hostname

Search:
-Owner owner
-Name text
-Visibility public|private|internal
-Archived true|false
-HostName hostname
```

`-Repository` cannot be mixed with search filters. The command is read-only and returns structured objects including immutable `Id` and `NodeId` when available.

### `Test-GitHubRepositoryMigration`

Keeps its compatibility-sensitive public name and compares source and destination Git evidence according to Snapshot or FullHistory verification contracts.

Snapshot verification compares default-branch Git trees and verifies that the destination has exactly one reachable root commit. FullHistory verification compares ordinary branch/tag target IDs, reachable commit counts, branch-tip trees, default branch, and Git LFS availability.

Execution-time verification is stricter about temporal consistency: it compares the destination with the source evidence approved/copied by the execution plan instead of redefining success from a newly read source state.

## Native help contract

All four exported commands include complete comment-based help for declared public parameters, normal examples, outputs, and relevant links. Snapshot help consistently describes the operation as clean current-state publication rather than conventional history-preserving migration.

PowerShell's native help system is intended to be sufficient for routine usage:

```powershell
Get-Help Copy-GitHubRepository -Full
Get-Help Get-GitHubRepository -Examples
Get-Help Start-CopyGitHubRepositoryWizard -Full
Get-Help Test-GitHubRepositoryMigration -Full
```

## Output contract

The success pipeline contains typed objects unless a caller explicitly requests plain or JSON rendering. Warnings and errors use their corresponding PowerShell streams.

Planning returns the compatibility-sensitive `CopyGitHubRepo.MigrationPlan` type. Mutating execution returns `CopyGitHubRepo.MigrationExecutionResult` or the applicable replacement/history result. Human-facing headings and descriptions use repository-copy terminology. Snapshot execution includes publication provenance. Configuration restoration results include ordinary settings evidence and repository-protection evidence where applicable.

## Release and installation contract

Release publication is tag-only. The tag must exactly match `v<ModuleVersion>`. The exact tagged commit first passes the reusable Windows, Ubuntu, and macOS quality gate. Normal publication never replaces an existing stable release.

The one-line convenience installer executes a bootstrap fetched from mutable `main`, so that bootstrap is part of the trust boundary. Stable release installation verifies the selected release ZIP checksum before extraction and execution.

## Exit behavior

Module functions use structured errors instead of terminating the host process. The launcher remains responsible for any future mapping from module outcomes to process exit codes.
