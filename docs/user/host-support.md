---
title: "GitHub Host Support – GitHub.com Compatibility | CopyGitHubRepo"
description: "Learn which GitHub hosts CopyGitHubRepo supports, how the HostName parameter behaves, and why unsupported GitHub hosts fail closed before repository operations."
---

# GitHub host support

The current `0.4.x` release line supports GitHub.com only.

The public `-HostName` parameter remains part of the command contract so GitHub Enterprise support can be added without redesigning the public API. For the current `0.4.x` release line, the supported value is `github.com` (case-insensitive).

All four public commands fail closed for any other hostname:

- `Copy-GitHubRepository`
- `Get-GitHubRepository`
- `Start-CopyGitHubRepositoryWizard`
- `Test-GitHubRepositoryMigration`

Unsupported hosts produce the structured `GitHubHostNotSupported` error before prerequisite checks, repository discovery, planning, verification, or remote mutation begin.

This fail-closed behavior prevents repository discovery through one GitHub host while a later operation implicitly targets another host. GitHub Enterprise Server and other GitHub hosts remain outside the current `0.4.x` product contract.

For the broader module-version, prerequisite, operating-system, compatibility, deprecation, and end-of-support rules, see [Support, compatibility, and deprecation policy](support-policy.md).
