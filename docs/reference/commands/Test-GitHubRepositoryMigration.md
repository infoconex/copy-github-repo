# Test-GitHubRepositoryMigration

Performs read-only verification of migrated Git content. Use the same content mode that was used for the migration.

## Synopsis

```powershell
Test-GitHubRepositoryMigration `
    -SourceRepository <owner/name> `
    -DestinationRepository <owner/name> `
    [-ContentMode Snapshot|FullHistory] `
    [-HostName <hostname>]
```

## When to use it

Use this command when you want an independent verification result for a completed Snapshot or FullHistory migration. It does not repair or mutate either repository.

## Parameters

| Parameter | Type | Required | Default | Accepted values / format | Description |
| --- | --- | --- | --- | --- | --- |
| `SourceRepository` | `String` | Yes | — | `owner/name` | Source repository used as the verification reference. |
| `DestinationRepository` | `String` | Yes | — | `owner/name` | Destination repository whose migrated Git content is checked. |
| `ContentMode` | `String` | No | `Snapshot` | `Snapshot`, `FullHistory` | Selects the verification contract. Use the same mode as the migration. |
| `HostName` | `String` | No | `github.com` | `github.com` in version 1 | GitHub host used for discovery and authentication. Unsupported hosts fail closed. |

Standard PowerShell common parameters are also available.

## Verification behavior

`Snapshot` compares the source and destination default-branch Git trees and verifies that the destination has the expected single-root-commit history shape.

`FullHistory` compares ordinary branch/tag targets, reachable commit counts, branch-tip trees, the default branch, and reachable Git LFS object availability.

See [Architecture](../../product/architecture.md) for the detailed evidence model.

## Output

Returns `CopyGitHubRepo.SnapshotVerificationResult` or `CopyGitHubRepo.FullHistoryVerificationResult`. The structured result contains verification evidence and `IsSuccessful`.

## Important failure conditions

The command fails when Git or GitHub CLI is unavailable, authentication is unavailable, an unsupported host is supplied, source/destination discovery fails, or native Git/LFS verification cannot gather required evidence. A completed verification can also return `IsSuccessful = $false` when the repositories do not satisfy the selected migration contract.

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

## Related documentation

- [`Copy-GitHubRepository`](Copy-GitHubRepository.md)
- [Product contract](../../product/product-contract.md)
- [Command design](../../product/command-design.md)
- [Architecture](../../product/architecture.md)
- [Host support](../../user/host-support.md)
