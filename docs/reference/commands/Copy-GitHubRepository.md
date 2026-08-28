---
title: "Copy-GitHubRepository – Copy or Migrate GitHub Repositories"
description: "Use Copy-GitHubRepository to safely copy or migrate GitHub repositories with clean Snapshot or history-preserving FullHistory modes, planning, verification, and replacement safeguards."
---

# Copy-GitHubRepository

Plans or executes a safe GitHub repository copy/publication. `Snapshot` is the default **clean current-state publication** mode; `FullHistory` is the explicit history-preserving alternative. The command is the deterministic API used directly by scripts and indirectly by the guided wizard.

## Synopsis

```powershell
Copy-GitHubRepository `
    -SourceRepository <owner/name> `
    -DestinationRepository <owner/name> `
    [-ContentMode Snapshot|FullHistory] `
    [-DestinationVisibility public|private|internal] `
    [-ArchiveRepositoryName <name>] `
    [-SameNameConfirmation <text>] `
    [-ExistingDestinationArchiveName <name>] `
    [-ExistingDestinationConfirmation <text>] `
    [-CommitMessage <text>] `
    [-RestorePages] `
    [-EnableActionsAfterMigration] `
    [-SkipSettings] `
    [-PlanOnly] `
    [-NonInteractive] `
    [-OutputMode Interactive|Plain|Json] `
    [-ReportPath <path>] `
    [-HostName <hostname>] `
    [-Force] `
    [-WhatIf] `
    [-Confirm]
```

## When to use it

Use Snapshot when the desired result is a new repository containing the current source default-branch state as one unrelated root commit, without carrying prior Git history, old branches/tags, issues, pull requests, milestones, discussions, or other historical GitHub activity.

Use `FullHistory` when ordinary Git history, branches, and tags must be preserved.

For an interactive guided experience, use [`Start-CopyGitHubRepositoryWizard`](Start-CopyGitHubRepositoryWizard.md).

## Parameters

| Parameter | Type | Required | Default | Accepted values / format | Description |
| --- | --- | --- | --- | --- | --- |
| `SourceRepository` | `String` | Yes | — | `owner/name` | Source repository. It must exist and contain a default branch with content. |
| `DestinationRepository` | `String` | Yes | — | `owner/name` | Destination. A different existing destination requires explicit archive-and-replace parameters; the same name selects same-name replacement. |
| `ContentMode` | `String` | No | `Snapshot` | `Snapshot`, `FullHistory` | Selects clean Snapshot publication or history-preserving Git transfer. |
| `DestinationVisibility` | `String` | No | Source visibility | `public`, `private`, `internal` | Destination visibility. An intentional change requires `-Force` for mutation. |
| `ArchiveRepositoryName` | `String` | Conditionally | — | Repository name only | Required for same-name replacement; must be unused. |
| `SameNameConfirmation` | `String` | Conditionally | — | Exact `SOURCE=...;ARCHIVE=...;REPLACEMENT=...` text | Exact same-name replacement confirmation. `-Force` cannot bypass it. |
| `ExistingDestinationArchiveName` | `String` | Conditionally | — | Repository name only | Enables archive-and-replace for a different existing destination. |
| `ExistingDestinationConfirmation` | `String` | Conditionally | — | Exact `DESTINATION=...;ARCHIVE=...;REPLACEMENT=...` text | Exact existing-destination replacement confirmation. |
| `CommitMessage` | `String` | No | `Initial repository commit` | Non-empty text | Message for the single Snapshot root commit. FullHistory does not rewrite commits. |
| `RestorePages` | `Switch` | No | `$false` | Switch | Reserved in plans; mutating execution rejects it because Pages restoration is not implemented. |
| `EnableActionsAfterMigration` | `Switch` | No | `$false` | Switch | Reserved in plans; mutating execution rejects it because Actions activation is not implemented. |
| `SkipSettings` | `Switch` | No | `$false` | Switch | Skips both ordinary supported repository settings and repository-protection restoration after content verification. |
| `PlanOnly` | `Switch` | No | `$false` | Switch | Returns a validated, non-mutating plan including protection-capture status when available. |
| `NonInteractive` | `Switch` | No | `$false` | Switch | Prevents prompts. Mutating non-interactive execution also requires `-Force`. |
| `OutputMode` | `String` | No | `Interactive` | `Interactive`, `Plain`, `Json` | Controls plan rendering. |
| `ReportPath` | `String` | No | — | File path | Writes plan/execution evidence and is the preferred recovery-report location after mutation begins. |
| `HostName` | `String` | No | `github.com` | `github.com` in `v0.1.0` | GitHub host. Other hosts fail closed. |
| `Force` | `Switch` | No | `$false` | Switch | Acknowledges non-interactive mutation and intentional visibility changes; never bypasses exact replacement confirmations. |

The command supports native `ShouldProcess`, so `-WhatIf` and `-Confirm` are available.

## Default Snapshot behavior

A normal Snapshot publication:

1. validates prerequisites/source/destination safety;
2. captures source and transferable protection evidence during planning when identity is available;
3. creates or preserves/replaces the destination as required;
4. creates one unrelated root commit from the selected source default-branch tree and transfers required Git LFS content;
5. reloads and verifies tree equality and the one-root-commit history shape;
6. restores and verifies ordinary supported repository settings/topics;
7. restores transferable repository protection last and verifies it through API read-back;
8. returns structured verification and publication-provenance evidence.

The destination root commit SHA is expected to differ from the source commit SHA because Snapshot intentionally creates a new parentless Git commit. The tree SHA is the core content invariant.

## Supported ordinary settings

The ordinary settings stage supports description, homepage, Issues/Projects/Wiki/Discussions enabled states, squash/merge-commit/rebase/auto-merge flags, delete-branch-on-merge, update-branch allowance, web commit signoff, and repository topics. Restoration is differential and source-available values are independently read back.

## Repository protection

After content and ordinary settings are verified, the command restores the transferable subset of:

- repository-level rulesets;
- legacy protection for the source default branch.

Identity-bound semantics are never silently removed to make a policy portable. Rulesets with bypass actors, required deployments, or integration-bound checks and legacy protection with user/team/app restrictions or app-bound checks are surfaced as skipped/unsupported. Inherited organization rulesets are not copied.

See [Repository protection restoration](../../user/protection-restoration.md) for the detailed support matrix.

## Snapshot provenance

Successful Snapshot results/reports include publication provenance: source/destination repository identities when available, selected source commit/tree, destination root commit/tree, UTC timestamp, and verification outcome. Same-name replacement additionally records archive identity continuity and replacement identity distinction.

This evidence is external to the clean Git history; no provenance marker file, tag, note, parent, or extra commit is added to the destination.

## FullHistory

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -ContentMode FullHistory
```

FullHistory preserves ordinary branches, tags, reachable history, the default branch, and reachable Git LFS objects. It uses the same configuration ordering: content verification first, ordinary settings next, transferable protection last.

## Replacement safety

Same-name replacement and explicit existing-destination replacement preserve the prior repository under an unused archive name before creating the fresh replacement. Exact typed confirmation is required. Neither `-Force` nor `-Confirm:$false` bypasses replacement identity safeguards.

Failures after mutation begins produce durable recovery information; the command does not automatically delete or roll back repositories.

## Output

Interactive planning returns `CopyGitHubRepo.MigrationPlan`. Plain/JSON planning returns text. Mutating execution returns a structured migration execution result with verification evidence, completed stages, ordinary settings evidence, repository-protection evidence, and Snapshot publication provenance where applicable.

## Important failure conditions

The command fails before mutation when tools/authentication are unavailable, the source is invalid/empty, destination/archive safety requirements are not met, an unsupported host is supplied, a required `-Force` acknowledgement is missing, or exact replacement confirmation is invalid.

After mutation begins, Git/LFS verification failures, ordinary settings read-back mismatches, protection API failures, and protection read-back mismatches are terminating failures with recovery diagnostics.

## Examples

### Preview a clean Snapshot publication

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -PlanOnly
```

### Publish the current state with clean history

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination
```

### Preserve full Git history

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -ContentMode FullHistory
```

### Skip ordinary settings and protection restoration

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -SkipSettings
```

### Perform same-name Snapshot replacement

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/source `
    -ArchiveRepositoryName source-archive `
    -SameNameConfirmation 'SOURCE=infoconex/source;ARCHIVE=infoconex/source-archive;REPLACEMENT=infoconex/source' `
    -NonInteractive `
    -Force
```

### Archive and replace an existing destination

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -ExistingDestinationArchiveName destination-archive-20260813-213700 `
    -ExistingDestinationConfirmation 'DESTINATION=infoconex/destination;ARCHIVE=infoconex/destination-archive-20260813-213700;REPLACEMENT=infoconex/destination' `
    -NonInteractive `
    -Force
```

## Related documentation

- [`Start-CopyGitHubRepositoryWizard`](Start-CopyGitHubRepositoryWizard.md)
- [`Get-GitHubRepository`](Get-GitHubRepository.md)
- [`Test-GitHubRepositoryMigration`](Test-GitHubRepositoryMigration.md)
- [Manual clean Snapshot process](../../user/manual-process.md)
- [Repository protection restoration](../../user/protection-restoration.md)
- [Product contract](../../product/product-contract.md)
- [Command design](../../product/command-design.md)
- [Architecture](../../product/architecture.md)
