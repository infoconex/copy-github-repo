---
title: "Copy and Migrate GitHub Repositories with PowerShell"
description: "Copy GitHub repositories with PowerShell using Snapshot for a clean copy or FullHistory to preserve history, with optional releases and GitHub Pages restoration plus planning, verification, and recovery safeguards."
---

![Copy GitHub Repo banner](assets/images/product_banner.png)

# Copy GitHub Repository

[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/CopyGitHubRepo?label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/CopyGitHubRepo)
[![PowerShell Gallery Downloads](https://img.shields.io/powershellgallery/dt/CopyGitHubRepo?label=Downloads)](https://www.powershellgallery.com/packages/CopyGitHubRepo)
[![Validate Project Quality](https://github.com/infoconex/copy-github-repo/actions/workflows/validate-project-quality.yml/badge.svg)](https://github.com/infoconex/copy-github-repo/actions/workflows/validate-project-quality.yml)
![PowerShell 7.4+](https://img.shields.io/badge/PowerShell-7.4%2B-informational)
![Platforms](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS-informational)

Copy GitHub Repository is a PowerShell utility for safely publishing or copying GitHub repositories. Its default `Snapshot` mode is designed for **clean publication**. Plain Snapshot copies the current source default-branch state into one unrelated root commit, intentionally leaving prior Git history, old branches/tags, pull requests, issues, milestones, and other historical GitHub records behind. With `-IncludeReleases`, Snapshot can instead preserve selected release states as a new unrelated checkpoint history while still intentionally replacing the source commit identities and detailed ancestry. The explicit `FullHistory` mode is the history-preserving alternative and keeps ordinary Git history, branches, tags, and reachable Git LFS objects; with `-IncludeReleases`, it also recreates selected GitHub Releases and their assets against the original preserved tag targets.

GitHub Pages restoration is a separate opt-in capability. `-RestorePages` restores supported **GitHub-side Pages configuration** from immutable reviewed plan evidence after content verification. Site files, `CNAME`, Jekyll configuration, and Pages workflow files remain ordinary Git content and may be copied even when `-RestorePages` is omitted; copying those files does not prove that the GitHub-side Pages configuration was preserved.

The project prioritizes preservation, explicit human authority, verification, and recoverability. It never automatically deletes a repository or overwrites an existing destination.

> [!IMPORTANT]
> Snapshot execution, Snapshot release preservation, FullHistory execution, same-name and existing-destination replacement, supported repository settings/protection restoration, GitHub Release preservation, and opt-in GitHub Pages restoration are implemented on the current development line. The guided wizard exposes the supported Pages opt-in and reviews the same immutable plan used by deterministic execution.

## Choose the right content mode

Use **Snapshot** when you want a clean new Git history. Plain Snapshot creates one unrelated current-state root commit. Add `-IncludeReleases` when selected release states should become newly created Snapshot checkpoint commits before the optional final current-state commit. The recreated release tags point to those new checkpoint commits, so original source commit SHAs and detailed ancestry are intentionally not preserved.

Use **FullHistory** when commit ancestry, branches, tags, signed historical commits, blame history, or other Git-history evidence must remain intact. Add `-IncludeReleases` when selected GitHub Release pages and assets should also be recreated while preserving their original Git tag targets.

Add **`-RestorePages`** in either content mode only when supported GitHub-side Pages configuration should be restored. Actions-based Pages and representable branch/path publishing are supported. External DNS is never modified, secrets are never copied, and domain verification/certificate issuance can remain externally dependent after GitHub-side restoration.

For the complete user journey, support matrix, and common operating scenarios, start with the [User guide](docs/user/user-guide.md). For Pages-specific behavior and recovery, see [GitHub Pages migration and recovery](docs/user/github-pages-migration.md). The detailed Snapshot checkpoint rules are authoritative in the [Product contract](docs/product/product-contract.md#snapshot-release-checkpoint-contract).

Want to see what plain Snapshot automates? See [Manually Creating a Clean GitHub Repository Snapshot](docs/user/manual-process.md) for the equivalent Git and GitHub CLI/API procedure, including settings restoration and verification.

## Safety at a glance

- Existing destination repositories are rejected rather than overwritten unless an explicit archive-and-replace flow is selected.
- Same-name replacement archives and verifies the original before the original name is reused.
- Replacement flows require exact typed confirmation; `-Force` cannot bypass it.
- `-PlanOnly` and `-WhatIf` are non-mutating.
- Content is verified before success is reported.
- Plain Snapshot remains one unrelated current-state root commit.
- Snapshot release preservation is bound to reviewed release/tag/tree evidence; incompatible release topology or selected source drift fails closed rather than inventing history.
- Snapshot release tags are recreated against new checkpoint commits whose trees match the reviewed selected release states; original source commit identities are not claimed to be preserved.
- A final current-state Snapshot commit is created only when reviewed source HEAD differs in repository state from the latest selected release checkpoint.
- FullHistory release restoration remains bound to the exact release inventory approved during planning and retains original history/tag targets.
- Existing destination GitHub Releases are not silently overwritten.
- When the source release marked Latest is selected, that designation is preserved and verified at the destination.
- `-RestorePages` is opt-in and consumes immutable reviewed Pages evidence; material source Pages drift before mutation fails closed.
- Copied site/workflow files are Git content, not proof of preserved GitHub-side Pages configuration.
- Pages restoration independently verifies the supported destination configuration and controls copied Pages workflow activation until the approved restoration boundary.
- Same-name/existing-destination custom-domain handoff verifies archive/replacement identity and records partial handoff evidence for recovery.
- External DNS, account/organization domain verification, certificate provisioning, and secrets are not migrated. Pending certificate provisioning can remain a valid external readiness state.
- Release immutability state and linked release discussions are not currently recreated.
- Failures after mutation begins retain durable recovery information instead of automatically deleting or rolling back repositories, restored releases, or uncertain custom-domain ownership.
- The current release line supports GitHub.com only and fails closed for other hosts.

See the [Product contract](docs/product/product-contract.md), [GitHub Pages migration contract](docs/product/github-pages-migration-contract.md), and [Architecture](docs/product/architecture.md) for detailed safety and verification contracts.

## Prerequisites

- [PowerShell](https://learn.microsoft.com/powershell/) 7.4 or newer
- [Git](https://git-scm.com/)
- [GitHub CLI](https://cli.github.com/) (`gh`)
- [Git LFS](https://git-lfs.com/) when required by the selected migration mode/content

For the supported module-version line, PowerShell/platform expectations, prerequisite compatibility, deprecation, and end-of-support rules, see [Support, compatibility, and deprecation policy](docs/user/support-policy.md).

Authenticate GitHub CLI before discovery:

```powershell
gh auth login --hostname github.com
```

## Install

The recommended normal installation path is PowerShell Gallery:

```powershell
Install-PSResource CopyGitHubRepo
Import-Module CopyGitHubRepo
Start-CopyGitHubRepositoryWizard
```

For environments using the older PowerShellGet commands, the compatible alternative is:

```powershell
Install-Module CopyGitHubRepo -Scope CurrentUser
```

Use PowerShell Gallery for normal public installation and updates. The repository-hosted installers remain available for bootstrap, pinned-release, development, and release-candidate scenarios where that trust model is appropriate.

To update a Gallery installation:

```powershell
Update-PSResource CopyGitHubRepo
```

To remove a Gallery installation:

```powershell
Uninstall-PSResource CopyGitHubRepo
```

Version `0.1.0` is the initial stable release. Use the prerelease workflow below only for deliberate development or release-candidate testing of unreleased `main` content.

## Install the current prerelease build

Install the current `main` build with:

```powershell
irm https://raw.githubusercontent.com/infoconex/copy-github-repo/main/install-prerelease.ps1 | iex
Import-Module CopyGitHubRepo -Force
Start-CopyGitHubRepositoryWizard
```

The prerelease bootstrap resolves `main` to an exact commit SHA before downloading the source archive. It does not provide the stable release checksum contract and does not publish to PowerShell Gallery.

## Repository-hosted stable installation

The repository-hosted stable convenience bootstrap is available as an alternative to PSGallery. It resolves the latest stable release (or an explicitly requested version), verifies the release ZIP against its published SHA-256 file and GitHub artifact provenance, and invokes the packaged installer:

```powershell
irm https://raw.githubusercontent.com/infoconex/copy-github-repo/main/install-release.ps1 | iex
Import-Module CopyGitHubRepo
Start-CopyGitHubRepositoryWizard
```

> [!IMPORTANT]
> The stable convenience command downloads `install-release.ps1` from mutable `main` and executes it before release artifact verification can protect the bootstrap itself. The bootstrap is therefore part of the trust boundary. The downloaded release ZIP is verified by checksum and GitHub artifact provenance before extraction.

For pinned-release installation, checksum limitations, provenance verification, `-Force` replacement behavior, and the complete trust model, see [Installation security](docs/security/installation-security.md). The initial stable release is `v0.1.0`, and the stable procedures apply to that release and later stable versions.

## Uninstall

For a module installed from PowerShell Gallery, prefer the package manager that installed it:

```powershell
Uninstall-PSResource CopyGitHubRepo
```

The project also provides its own safe interactive uninstaller for repository-hosted installations and explicit local cleanup. It discovers installed CopyGitHubRepo versions, shows the exact local paths that would be removed, and requires confirmation before deletion:

```powershell
irm https://raw.githubusercontent.com/infoconex/copy-github-repo/main/uninstall.ps1 | iex
```

If multiple versions are installed, the script lets you remove one version, remove all validated versions, or cancel. Destructive confirmation defaults to No.

For deterministic local or automated removal, replace `X.Y.Z` with the installed module version and use the packaged/repository script directly:

```powershell
./uninstall.ps1 -Version 'X.Y.Z'
./uninstall.ps1 -AllVersions
./uninstall.ps1 -Version 'X.Y.Z' -DestinationRoot D:\PowerShell\Modules
./uninstall.ps1 -Version 'X.Y.Z' -WhatIf
./uninstall.ps1 -Version 'X.Y.Z' -Confirm:$false
```

`-Version` and `-AllVersions` are mutually exclusive. The uninstaller validates module identity and path containment before recursive deletion, does not remove neighboring modules, and does not require network access when run locally. The one-line command above executes mutable `main`, so it has the same bootstrap trust-boundary consideration as the convenience installers. See [Installation security](docs/security/installation-security.md) for details.

## Guided quick start

The recommended human-facing entry point is the guided wizard:

```powershell
Start-CopyGitHubRepositoryWizard
```

It discovers repositories, defaults to Snapshot/source visibility/settings restoration, lets you navigate Back/Next/Cancel before execution, displays a real `Copy-GitHubRepository -PlanOnly` plan, and requires an explicit Execute decision before mutation. When Snapshot is selected, the wizard can optionally preserve selected releases. When the source has Pages state that can be reviewed, the wizard also offers the explicit Pages-restoration choice, shows the actual plan evidence and external boundaries, and passes that reviewed `-RestorePages` decision into deterministic execution.

A repository checkout can start the same guided experience through the root launcher:

```powershell
./copy-github-repo.ps1
```

See the [User guide](docs/user/user-guide.md) for scenario selection and what gets copied, [GitHub Pages migration and recovery](docs/user/github-pages-migration.md) for Pages-specific guidance, then [`Start-CopyGitHubRepositoryWizard`](docs/reference/commands/Start-CopyGitHubRepositoryWizard.md) for complete command-level reference.

## Scripted quick start

`Copy-GitHubRepository` is the deterministic API for scripts and automation. Preview first:

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -PlanOnly
```

Then execute the reviewed default clean Snapshot publication:

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination
```

To keep a clean Snapshot history while preserving selected release checkpoints and GitHub Release content:

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -ContentMode Snapshot `
    -IncludeReleases
```

To preserve FullHistory plus all stable, non-draft GitHub Releases and assets:

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -ContentMode FullHistory `
    -IncludeReleases
```

To restore supported GitHub-side Pages configuration from reviewed evidence:

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -RestorePages
```

This does not migrate external DNS, domain-verification ownership, certificate provisioning, or secrets. Review the generated plan before execution, especially for branch/path publishing or custom-domain replacement.

Release selection can be narrowed in either mode. For example, preserve only the three newest stable v2 releases:

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -ContentMode Snapshot `
    -IncludeReleases `
    -ReleaseTag 'v2.*' `
    -ReleaseCount 3
```

Snapshot/FullHistory distinctions, release selection, Pages restoration, visibility changes, replacement modes, reporting, non-interactive execution, settings choices, and all parameter details are documented in [`Copy-GitHubRepository`](docs/reference/commands/Copy-GitHubRepository.md).

## Commands

| Command | Purpose | Mutates GitHub? |
| --- | --- | --- |
| [`Start-CopyGitHubRepositoryWizard`](docs/reference/commands/Start-CopyGitHubRepositoryWizard.md) | Guided repository migration, including optional Snapshot release preservation and reviewed Pages restoration | Yes, after plan review and confirmation |
| [`Copy-GitHubRepository`](docs/reference/commands/Copy-GitHubRepository.md) | Scriptable planning and repository migration, including optional releases and GitHub Pages restoration | Yes, except `-PlanOnly`/`-WhatIf` |
| [`Get-GitHubRepository`](docs/reference/commands/Get-GitHubRepository.md) | Repository discovery and metadata | No |
| [`Test-GitHubRepositoryMigration`](docs/reference/commands/Test-GitHubRepositoryMigration.md) | Snapshot/FullHistory verification | No |

Start with the [command reference index](docs/reference/commands/README.md) for detailed syntax, parameter tables, outputs, failure conditions, and examples.

## Documentation

Documentation uses progressive disclosure and one authoritative home per contract where practical. Start at the [documentation index](docs/README.md). See the [Documentation strategy](docs/engineering/documentation-strategy.md) for the seven primary audiences, their journeys, the authority map, and anti-duplication rules.

| Goal | Start here |
| --- | --- |
| Use the product safely | [User guide](docs/user/user-guide.md), [GitHub Pages migration and recovery](docs/user/github-pages-migration.md), [Installation security](docs/security/installation-security.md), [Command reference](docs/reference/commands/README.md) |
| Understand product journeys, capabilities, use cases, and behavior scenarios | [Product journeys and behavioral model](docs/product/product-model.md) |
| Understand normative product behavior and safety | [Product contract](docs/product/product-contract.md), [GitHub Pages migration contract](docs/product/github-pages-migration-contract.md), [Architecture](docs/product/architecture.md) |
| Understand the guided interaction | [Wizard contract](docs/product/wizard-contract.md) |
| Understand how Snapshot can be done manually | [Manual Snapshot procedure](docs/user/manual-process.md) |
| Determine supported versions, platforms, prerequisites, and deprecation rules | [Support, compatibility, and deprecation policy](docs/user/support-policy.md) |
| Contribute or maintain the project | [CONTRIBUTING.md](CONTRIBUTING.md), [Engineering principles](docs/engineering/engineering-principles.md), [PowerShell style guide](docs/engineering/powershell-style-guide.md), [Source documentation](docs/engineering/source-code-documentation.md) |
| Understand versioning and publication | [Versioning](docs/release/versioning.md), [PowerShell Gallery publishing](docs/release/publishing.md) |
| Review project security and governance | [Software assurance review](docs/security/software-assurance.md), [SECURITY.md](SECURITY.md), [Installation security](docs/security/installation-security.md), [License](LICENSE) |
| Understand how documentation is governed | [Documentation strategy](docs/engineering/documentation-strategy.md) |

## Development

Install development dependencies as needed, then run the repository quality gate:

```powershell
./build/Test-Project.ps1
```

The quality gate runs in GitHub Actions on Windows, Ubuntu, and macOS for pushes to `main` and pull requests targeting `main` or `release/**` integration branches. Controlled live-validation harnesses live under `tests/e2e/`; build/release tooling remains under `build/`.

Release publication is tag-only. A stable release tag must exactly match `v<ModuleVersion>` and the exact tagged commit must pass the cross-platform quality gate before publication. The release workflow validates a clean Gallery package, rejects duplicate PSGallery and GitHub Release versions, publishes with `Publish-PSResource`, and creates the immutable GitHub release assets. Merging to `main` does not publish a release.

Maintainer setup, API-key rotation, manual fallback, signing policy, and prerelease behavior are documented in [Publishing to PowerShell Gallery](docs/release/publishing.md).

See [CONTRIBUTING.md](CONTRIBUTING.md) for contributor guidance.

## License

This project is available under the [MIT License](LICENSE).