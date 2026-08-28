---
title: "Get-GitHubRepository – Find and Inspect GitHub Repositories"
description: "Use Get-GitHubRepository to find or inspect GitHub repositories and return structured metadata without changing repository state."
---

# Get-GitHubRepository

Returns structured GitHub repository metadata. The command is read-only.

## Synopsis

```powershell
Get-GitHubRepository -Repository <owner/name> [-HostName <hostname>]
Get-GitHubRepository [-Owner <owner>] [-Name <text>] [-Visibility public|private|internal] [-Archived <bool>] [-HostName <hostname>]
```

`Search` is the default parameter set.

## When to use it

Use this command to inspect one repository by exact identity or search repository metadata before planning a migration. It does not change GitHub state.

## Parameters

| Parameter | Type | Required | Default | Accepted values / format | Description |
| --- | --- | --- | --- | --- | --- |
| `Repository` | `String` | Yes in `ByRepository` | — | `owner/name` | Exact repository lookup. Cannot be combined with Search parameters. |
| `Owner` | `String` | No | — | Owner login | Filters Search results by owner. |
| `Name` | `String` | No | — | Text | Filters Search results by repository name. |
| `Visibility` | `String` | No | — | `public`, `private`, `internal` | Filters Search results by visibility. |
| `Archived` | `Nullable[Boolean]` | No | — | `$true`, `$false` | Filters Search results by archived state. |
| `HostName` | `String` | No | `github.com` | `github.com` in `v0.1.0` | GitHub host for discovery and authentication. |

Standard PowerShell common parameters are also available.

## Parameter sets

`ByRepository` requires `-Repository`. `Search` is the default parameter set; with no filters it lists repositories available to the authenticated account. `-Repository` cannot be mixed with `-Owner`, `-Name`, `-Visibility`, or `-Archived`.

## Output

Returns `CopyGitHubRepo.Repository` objects with repository identity, owner/name, visibility, archived state, default branch, URLs, immutable GitHub identifiers when available, and supported settings.

## Important failure conditions

The command fails when GitHub CLI or authentication is unavailable, an unsupported host is supplied, or the requested discovery operation cannot be completed.

## Examples

```powershell
Get-GitHubRepository -Repository infoconex/copy-github-repo
Get-GitHubRepository -Owner infoconex
Get-GitHubRepository -Owner infoconex -Name copy -Visibility public -Archived $false
Get-GitHubRepository
```

## Related documentation

- [`Copy-GitHubRepository`](Copy-GitHubRepository.md)
- [`Start-CopyGitHubRepositoryWizard`](Start-CopyGitHubRepositoryWizard.md)
- [Command design](../../product/command-design.md)
- [Host support](../../user/host-support.md)
