---
title: "Test-GitHubRepositoryMigration – Verify GitHub Repository Migrations"
description: "Verify Snapshot or FullHistory GitHub repository migrations with read-only destination evidence, including approved release checkpoints, GitHub Releases, and reviewed GitHub Pages configuration."
---

# Test-GitHubRepositoryMigration

Performs read-only verification of migrated repository content. Plain Snapshot and FullHistory retain their existing verification contracts. Snapshot migrations that used `-IncludeReleases` are verified against immutable reviewed migration evidence rather than by rerunning live release selection. Migrations that used `-RestorePages` can add `-VerifyPages -ApprovedPlan` to independently compare destination GitHub Pages state with the reviewed Pages evidence.

## Synopsis

```powershell
Test-GitHubRepositoryMigration `
    -SourceRepository <owner/name> `
    -DestinationRepository <owner/name> `
    [-ContentMode Snapshot|FullHistory] `
    [-IncludeReleases] `
    [-VerifyPages] `
    [-ReleaseTag <string[]>] `
    [-ReleaseExcludeTag <string[]>] `
    [-IncludePrerelease] `
    [-IncludeDraftReleases] `
    [-ReleaseCount <int>] `
    [-ApprovedPlan <object>] `
    [-HostName <hostname>]
```

## When to use it

Use this command when you want an independent verification result for a completed Snapshot or FullHistory migration. For Snapshot migrations that used `-IncludeReleases`, provide the exact reviewed plan with `-ApprovedPlan`; that evidence defines the expected checkpoints and selected releases. For any supported migration that requested `-RestorePages`, add `-VerifyPages -ApprovedPlan`; `Plan.Pages` defines the expected GitHub-side Pages state and live source Pages discovery is not rerun as authority. The command does not repair or mutate either repository.

## Parameters

| Parameter | Type | Required | Default | Accepted values / format | Description |
| --- | --- | --- | --- | --- | --- |
| `SourceRepository` | `String` | Yes | — | `owner/name` | Source repository identity associated with the migration. Approved Pages verification requires it to match the reviewed plan. |
| `DestinationRepository` | `String` | Yes | — | `owner/name` | Destination repository whose migrated content and requested GitHub-side state are independently read and checked. Approved Pages verification requires it to match the reviewed plan. |
| `ContentMode` | `String` | No | `Snapshot` | `Snapshot`, `FullHistory` | Selects the verification contract. Use the same mode as the migration. |
| `IncludeReleases` | `Switch` | No | `$false` | Snapshot or FullHistory | Adds GitHub Release verification. Snapshot requires `-ApprovedPlan`; FullHistory retains live source-selection verification. |
| `VerifyPages` | `Switch` | No | `$false` | Switch | Verifies supported GitHub-side Pages configuration from immutable `Plan.Pages` evidence. Requires `-ApprovedPlan` from a migration that requested `-RestorePages`. |
| `ReleaseTag` | `String[]` | No | — | PowerShell wildcard patterns | Includes matching source releases for FullHistory verification. Requires `-IncludeReleases`. Snapshot approved-plan verification rejects live release filters. |
| `ReleaseExcludeTag` | `String[]` | No | — | PowerShell wildcard patterns | Excludes matching source release tags for FullHistory verification. Requires `-IncludeReleases`. |
| `IncludePrerelease` | `Switch` | No | `$false` | Switch | Includes prereleases in FullHistory release verification. Requires `-IncludeReleases`. |
| `IncludeDraftReleases` | `Switch` | No | `$false` | Switch | Includes draft releases in FullHistory release verification. Requires `-IncludeReleases`. |
| `ReleaseCount` | `Int32` | No | — | `1` or greater | Limits FullHistory release verification to the newest N selected source releases. Requires `-IncludeReleases`. |
| `ApprovedPlan` | `PSObject` | No | — | Reviewed migration plan | Required for Snapshot `-IncludeReleases` and for `-VerifyPages`. Pages verification requires the plan to be bound to the requested source, destination, content mode, host, and `RestorePages` decision. |
| `HostName` | `String` | No | `github.com` | Supported GitHub host | GitHub host used for discovery and authentication. Unsupported hosts fail closed. |

Standard PowerShell common parameters are also available.

## Verification behavior

Plain `Snapshot` compares the source and destination default-branch Git trees and verifies that the destination has the expected single-root-commit history shape.

With `Snapshot -IncludeReleases -ApprovedPlan`, the command uses immutable reviewed planning evidence and destination reads to verify checkpoint sequence and parentage, checkpoint trees, selected release-tag targets, the reviewed source HEAD state, recreated release metadata/assets, and Latest designation. It does not rerun live release selection or topology discovery.

`FullHistory` compares ordinary branch/tag targets, reachable commit counts, branch-tip trees, the default branch, and reachable Git LFS object availability. With `FullHistory -IncludeReleases`, existing live source release-selection behavior remains unchanged.

With `-VerifyPages -ApprovedPlan`, the command independently reads destination GitHub Pages configuration and, where applicable, verifies:

- whether Pages is configured when the reviewed plan requires it;
- the explicit reviewed no-Pages state;
- Actions/workflow versus legacy branch/path build type;
- the exact reviewed branch and path for legacy Pages;
- the exact reviewed custom domain, including a reviewed absence of a custom domain;
- HTTPS enforcement when the reviewed evidence exposes a deterministic value; and
- for same-name or existing-destination replacement handoff, that the reviewed production custom domain is absent from the archive and present on the replacement.

Pages verification never reruns mutable source Pages discovery as expected-state authority. For plain Snapshot plus `-VerifyPages`, repository-content verification also uses the plan's approved `SourceState` rather than recloning source content as the expected tree.

DNS records, account/organization domain verification, certificate issuance/propagation, and similar external or asynchronous state are not migration success criteria. The verifier reports available GitHub readiness evidence separately, records DNS as `ExternalNotQueried`, and reports `DnsMigrated = $false`.

See [GitHub Pages migration contract](../../product/github-pages-migration-contract.md) for the normative Pages boundary.

## Output

Returns a `CopyGitHubRepo.MigrationVerificationResult`.

When release verification is requested, the result retains `GitContentSuccessful`, `ReleaseVerification`, `ReleasesVerified`, and the existing combined `IsSuccessful` behavior.

When `-VerifyPages` is requested, the result additionally includes:

- `PagesVerification` — a `CopyGitHubRepo.GitHubPagesVerificationResult` containing expected/actual configured state, named deterministic comparison checks, and external-readiness evidence;
- `PagesVerified` — whether all deterministic reviewed Pages checks passed; and
- `IsSuccessful` — `$true` only when the existing content/release contract and Pages verification all succeed.

`PagesVerification.ExternalReadiness` is informational evidence. It explicitly does not affect Pages configuration verification success.

## Important failure conditions

The command fails before verification when required reviewed evidence is absent or not bound to the requested migration identity. `-VerifyPages` requires a plan produced with `RestorePages = $true`, non-null `Plan.Pages`, the same source and destination repository identities, the same content mode, and the same GitHub host.

A completed verification returns `IsSuccessful = $false` for concrete destination mismatches such as an incorrect Pages configured state, build type, legacy branch/path, custom domain, deterministic HTTPS state, or replacement/archive domain ownership. External DNS, domain-verification, and certificate readiness do not make those deterministic checks pass or fail.

Existing Git/content/release failure behavior is unchanged.

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

### Verify restored GitHub Pages from reviewed evidence

```powershell
Test-GitHubRepositoryMigration `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -ContentMode Snapshot `
    -VerifyPages `
    -ApprovedPlan $migration.Plan
```

### Verify FullHistory plus Pages

```powershell
Test-GitHubRepositoryMigration `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -ContentMode FullHistory `
    -VerifyPages `
    -ApprovedPlan $migration.Plan
```

## Related documentation

- [`Copy-GitHubRepository`](Copy-GitHubRepository.md)
- [GitHub Pages migration contract](../../product/github-pages-migration-contract.md)
- [Product contract](../../product/product-contract.md)
- [Architecture](../../product/architecture.md)
- [Host support](../../user/host-support.md)
