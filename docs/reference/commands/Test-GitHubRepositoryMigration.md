---
title: "Test-GitHubRepositoryMigration – Verify GitHub Repository Migrations"
description: "Verify Snapshot or FullHistory GitHub repository migrations with PowerShell using read-only destination evidence, including approved Snapshot release checkpoints and GitHub Release assets."
---

# Test-GitHubRepositoryMigration

Performs read-only verification of migrated repository content. Plain Snapshot and FullHistory retain their existing verification contracts. Snapshot migrations that used `-IncludeReleases` are verified against the immutable reviewed migration plan rather than by rerunning live release selection.

## Synopsis

```powershell
Test-GitHubRepositoryMigration `
    -SourceRepository <owner/name> `
    -DestinationRepository <owner/name> `
    [-ContentMode Snapshot|FullHistory] `
    [-IncludeReleases] `
    [-ReleaseTag <string[]>] `
    [-ReleaseExcludeTag <string[]>] `
    [-IncludePrerelease] `
    [-IncludeDraftReleases] `
    [-ReleaseCount <int>] `
    [-ApprovedPlan <object>] `
    [-HostName <hostname>]
```

## When to use it

Use this command when you want an independent verification result for a completed Snapshot or FullHistory migration. For Snapshot migrations that used `-IncludeReleases`, provide the exact reviewed plan returned by the migration with `-ApprovedPlan`; that evidence defines the expected checkpoints and selected releases. For FullHistory migrations that included GitHub Releases, add `-IncludeReleases` and the same release filters to verify the selected current source releases against the destination. The command does not repair or mutate either repository.

## Parameters

| Parameter | Type | Required | Default | Accepted values / format | Description |
| --- | --- | --- | --- | --- | --- |
| `SourceRepository` | `String` | Yes | — | `owner/name` | Source repository identity associated with the migration. Plain Snapshot and FullHistory read it as the verification reference; Snapshot `-IncludeReleases` uses the approved plan as expected-state evidence. |
| `DestinationRepository` | `String` | Yes | — | `owner/name` | Destination repository whose migrated content and, when requested, recreated releases are independently read and checked. |
| `ContentMode` | `String` | No | `Snapshot` | `Snapshot`, `FullHistory` | Selects the verification contract. Use the same mode as the migration. |
| `IncludeReleases` | `Switch` | No | `$false` | Snapshot or FullHistory | Adds GitHub Release verification. Snapshot requires `-ApprovedPlan`; FullHistory retains live source-selection verification. |
| `ReleaseTag` | `String[]` | No | — | PowerShell wildcard patterns | Includes only source releases whose tag names match at least one supplied pattern for FullHistory verification. Requires `-IncludeReleases`. Snapshot approved-plan verification rejects live release filters. |
| `ReleaseExcludeTag` | `String[]` | No | — | PowerShell wildcard patterns | Excludes matching source release tags after include filtering for FullHistory verification. Requires `-IncludeReleases`. Snapshot approved-plan verification rejects live release filters. |
| `IncludePrerelease` | `Switch` | No | `$false` | Switch | Includes prereleases in FullHistory live-selection verification. Requires `-IncludeReleases`; not used with Snapshot `-ApprovedPlan`. |
| `IncludeDraftReleases` | `Switch` | No | `$false` | Switch | Includes draft releases in FullHistory live-selection verification. Requires `-IncludeReleases`; not used with Snapshot `-ApprovedPlan`. |
| `ReleaseCount` | `Int32` | No | — | `1` or greater | Limits FullHistory live-selection verification to the newest N source releases after filtering. Requires `-IncludeReleases`; not used with Snapshot `-ApprovedPlan`. |
| `ApprovedPlan` | `PSObject` | No | — | Reviewed Snapshot migration plan | Required with `-ContentMode Snapshot -IncludeReleases`. Supplies immutable `ReleaseCheckpointPlan` and `ReleaseSelection` evidence so verification does not rerun release selection, filtering, ordering, or topology discovery. |
| `HostName` | `String` | No | `github.com` | `github.com` in the current release line | GitHub host used for discovery and authentication. Unsupported hosts fail closed. |

Standard PowerShell common parameters are also available.

## Verification behavior

Plain `Snapshot` compares the source and destination default-branch Git trees and verifies that the destination has the expected single-root-commit history shape.

With `Snapshot -IncludeReleases -ApprovedPlan`, the command uses immutable reviewed planning evidence and destination reads to verify:

- the exact generated Snapshot checkpoint count and linear sequence;
- root and parent relationships between generated checkpoint commits;
- each checkpoint tree against the reviewed source release-state tree, without requiring source and destination commit SHA identity;
- each reviewed selected release tag against its expected generated Snapshot checkpoint;
- the final destination default-branch tree against the reviewed source HEAD;
- whether a final current-state checkpoint is present only when the reviewed plan requires one;
- the exact reviewed selected destination release-tag set;
- the exact reviewed selected GitHub Release set;
- release name/body, draft/prerelease state, assets, supported asset digest/size/content-type evidence, and Latest designation.

Snapshot release verification does not rerun live source release selection or filtering. The reviewed plan defines what must exist. A mismatch fails verification; the command does not repair, retag, recreate, delete, or otherwise mutate destination state.

`FullHistory` compares ordinary branch/tag targets, reachable commit counts, branch-tip trees, the default branch, and reachable Git LFS object availability.

With `FullHistory -IncludeReleases`, the command retains the existing behavior: it applies the requested current source release-selection rules, then verifies each selected source release against the destination by tag. It compares release tag and resolved commit identity, release metadata, assets, and Latest designation where applicable.

See [Architecture](../../product/architecture.md) for the detailed evidence model.

## Output

Returns a `CopyGitHubRepo.MigrationVerificationResult`.

For Snapshot `-IncludeReleases -ApprovedPlan`, the result includes generated checkpoint and release-tag verification evidence plus:

- `GitContentSuccessful` — the checkpoint/tag/tree/HEAD verification outcome;
- `ReleaseVerification` — structured per-release destination verification evidence;
- `ReleasesVerified` — the recreated-release verification outcome; and
- `IsSuccessful` — `$true` only when both Git/checkpoint and requested release verification succeed.

For FullHistory `-IncludeReleases`, the existing FullHistory result similarly includes `GitContentSuccessful`, `ReleaseVerification`, `ReleasesVerified`, and a combined `IsSuccessful` result.

## Important failure conditions

The command fails when Git or GitHub CLI is unavailable, authentication is unavailable, an unsupported host is supplied, required repository discovery fails, or native verification cannot gather required evidence. Release filter parameters require `-IncludeReleases`.

Snapshot `-IncludeReleases` additionally fails closed when `-ApprovedPlan` is absent or incomplete, or when live release filters are supplied alongside the approved plan. A completed verification returns `IsSuccessful = $false` for concrete destination mismatches such as an incorrect checkpoint tree or tag target, a missing/unexpected selected release, altered release metadata or assets, or an incorrect Latest designation.

## Examples

### Verify the default Snapshot contract

```powershell
Test-GitHubRepositoryMigration `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination
```

### Verify Snapshot release checkpoints from the reviewed plan

```powershell
Test-GitHubRepositoryMigration `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -ContentMode Snapshot `
    -IncludeReleases `
    -ApprovedPlan $migration.Plan
```

### Verify a FullHistory migration

```powershell
Test-GitHubRepositoryMigration `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -ContentMode FullHistory
```

### Verify FullHistory plus all stable releases

```powershell
Test-GitHubRepositoryMigration `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -ContentMode FullHistory `
    -IncludeReleases
```

### Verify the three newest stable v2 FullHistory releases

```powershell
Test-GitHubRepositoryMigration `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -ContentMode FullHistory `
    -IncludeReleases `
    -ReleaseTag 'v2.*' `
    -ReleaseCount 3
```

## Related documentation

- [`Copy-GitHubRepository`](Copy-GitHubRepository.md)
- [Product contract](../../product/product-contract.md)
- [Command design](../../product/command-design.md)
- [Architecture](../../product/architecture.md)
- [Host support](../../user/host-support.md)
