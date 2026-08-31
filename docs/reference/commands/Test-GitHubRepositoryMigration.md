---
title: "Test-GitHubRepositoryMigration – Verify GitHub Repository Migrations"
description: "Verify Snapshot or FullHistory GitHub repository migrations with PowerShell using read-only source/destination comparison, including optional GitHub Release and asset verification."
---

# Test-GitHubRepositoryMigration

Performs read-only verification of migrated repository content. Use the same content mode and, when applicable, the same release-selection intent that was used for the migration.

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
    [-HostName <hostname>]
```

## When to use it

Use this command when you want an independent verification result for a completed Snapshot or FullHistory migration. For FullHistory migrations that included GitHub Releases, add `-IncludeReleases` and the same release filters to verify the selected current source releases against the destination. The command does not repair or mutate either repository.

## Parameters

| Parameter | Type | Required | Default | Accepted values / format | Description |
| --- | --- | --- | --- | --- | --- |
| `SourceRepository` | `String` | Yes | — | `owner/name` | Source repository used as the verification reference. |
| `DestinationRepository` | `String` | Yes | — | `owner/name` | Destination repository whose migrated content is checked. |
| `ContentMode` | `String` | No | `Snapshot` | `Snapshot`, `FullHistory` | Selects the verification contract. Use the same mode as the migration. |
| `IncludeReleases` | `Switch` | No | `$false` | FullHistory only | Adds read-only GitHub Release verification. Stable, non-draft source releases are selected by default. |
| `ReleaseTag` | `String[]` | No | — | PowerShell wildcard patterns | Includes only source releases whose tag names match at least one supplied pattern. Requires `-IncludeReleases`. |
| `ReleaseExcludeTag` | `String[]` | No | — | PowerShell wildcard patterns | Excludes matching source release tags after include filtering. Requires `-IncludeReleases`. |
| `IncludePrerelease` | `Switch` | No | `$false` | Switch | Includes releases marked prerelease. Requires `-IncludeReleases`. |
| `IncludeDraftReleases` | `Switch` | No | `$false` | Switch | Includes draft releases. Requires `-IncludeReleases`. |
| `ReleaseCount` | `Int32` | No | — | `1` or greater | Limits verification to the newest N source releases after filtering. Requires `-IncludeReleases`. |
| `HostName` | `String` | No | `github.com` | `github.com` in the current release line | GitHub host used for discovery and authentication. Unsupported hosts fail closed. |

Standard PowerShell common parameters are also available.

## Verification behavior

`Snapshot` compares the source and destination default-branch Git trees and verifies that the destination has the expected single-root-commit history shape. GitHub Release verification is not supported for Snapshot.

`FullHistory` compares ordinary branch/tag targets, reachable commit counts, branch-tip trees, the default branch, and reachable Git LFS object availability.

With `FullHistory -IncludeReleases`, the command first applies the same source release-selection rules as `Copy-GitHubRepository`, then verifies each selected source release against the destination by tag. It compares:

- release tag and resolved commit identity;
- release name and body;
- draft/prerelease state;
- asset count, names, labels, sizes, content types, and digests when GitHub provides them; and
- the repository's Latest release designation when the selected set contains the current source Latest full release.

The standalone verifier compares the **current source release state**. It does not have the original immutable migration plan, so it cannot prove that the source has remained unchanged since the migration. Extra destination releases outside the selected current source set do not cause failure.

See [Architecture](../../product/architecture.md) for the detailed evidence model.

## Output

Returns the normal Snapshot or FullHistory migration-verification result. When `-IncludeReleases` is requested with FullHistory, the FullHistory result additionally contains:

- `GitContentSuccessful` — the ordinary FullHistory Git/LFS verification outcome;
- `ReleaseVerification` — structured per-release verification evidence;
- `ReleasesVerified` — the release-verification outcome; and
- `IsSuccessful` — `$true` only when both Git/LFS and requested release verification succeed.

## Important failure conditions

The command fails when Git or GitHub CLI is unavailable, authentication is unavailable, an unsupported host is supplied, source/destination discovery fails, release filter parameters are supplied without `-IncludeReleases`, `-IncludeReleases` is requested for Snapshot, or native verification cannot gather required evidence. A completed verification can return `IsSuccessful = $false` when Git/LFS state or selected GitHub Release state does not match.

## Examples

### Verify the default Snapshot contract

```powershell
Test-GitHubRepositoryMigration `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination
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

### Verify the three newest stable v2 releases

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
