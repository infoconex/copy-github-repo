# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-08-15

### Added

- Safe cross-platform `uninstall.ps1` support with interactive installed-version discovery/selection, exact-path confirmation, deterministic `-Version`/`-AllVersions` automation, `-WhatIf`, custom destination roots, module identity/path safety checks, and release-artifact packaging.
- Cross-platform PowerShell Gallery package validation in the normal quality gate, including manifest/export checks and an isolated fresh-process import of the exact staged package.
- Explicit engineering principles for pragmatic SOLID, single responsibility, DRY, cohesion/coupling, stable error contracts, destructive-operation clarity, and risk-based testing in PowerShell.
- Guarded manual stable-release dispatch from GitHub Actions for phone/web publication, with explicit confirmation, current-`main` SHA validation, exact tag/version validation, reusable quality gating, annotated tag creation, and the same Gallery/GitHub publication path used by tag-triggered releases.
- Guided repository-copy orchestration through `Start-CopyGitHubRepositoryWizard`, including source filtering, safe defaults, Back/Next/Cancel navigation, real `-PlanOnly` review before mutation, FullHistory selection, and same-name archive/exact-confirmation handling.
- Node 24-compatible pinned `actions/checkout` version for the quality gate.
- Repository discovery through GitHub CLI and GitHub API.
- GitHub CLI prerequisite and authentication checks.
- Direct repository lookup by `owner/name`.
- Repository filters for owner, name, visibility, and archived status.
- Structured repository objects with permission summary fields.
- Dry-run migration planning with `Copy-GitHubRepository -PlanOnly`.
- Destination and archive non-overwrite checks during planning.
- Empty source repository rejection before destination checks or mutation.
- Markdown and JSON migration plan rendering.
- Destination repository creation behind `ShouldProcess`.
- Destination verification after repository creation.
- Snapshot content copy into one new root commit from the source Git tree object.
- Git LFS object transfer for Snapshot migrations when the source uses Git LFS.
- Snapshot migration verification for tree identity and clean destination history.
- FullHistory migration for ordinary branches, tags, reachable history, default branch, and reachable Git LFS objects.
- FullHistory verification for branch/tag targets, reachable commit counts, branch-tip trees, default branch, and LFS availability.
- Same-name Snapshot replacement with archive-first verification and exact confirmation.
- Same-name FullHistory replacement with immutable pre-rename identity capture and archive verification before replacement creation.
- Durable JSON recovery reports for failures after destination creation and same-name archive/replacement mutations.
- Differential repository-level settings restoration with GitHub read-back verification for description, homepage, Issues/Projects/Wiki/Discussions flags, merge settings, auto-merge, delete-branch-on-merge, update-branch allowance, web commit signoff, and topics.
- Markdown and JSON execution reports.
- Isolated Git authentication through GitHub CLI credentials for private and non-interactive repository operations.
- Child-process-scoped native-command environment overrides that avoid mutating process-wide environment state.
- Controlled opt-in end-to-end harnesses for Snapshot, recovery, Git LFS, same-name Snapshot, new-destination FullHistory, same-name FullHistory, and repository-settings restoration.
- Deterministic release ZIP generation with fixed entry ordering/timestamps and SHA-256 checksum output.
- A release-package installer that targets the current user's PowerShell module location and requires explicit `-Force` before replacing the same version.
- A stable one-line `install-release.ps1` bootstrap that installs the latest stable release by default or an exact stable release when `-Version X.Y.Z` is supplied, verifies the release ZIP against its published SHA-256 checksum, runs the packaged installer, and cleans temporary files.
- A separate one-line `install-prerelease.ps1` bootstrap for development and release-candidate testing that resolves `main` to an exact commit SHA before downloading and installing that unreleased source archive.
- Stable GitHub release automation for exact version-tag pushes and guarded manual dispatch, validating `v<ModuleVersion>`, rerunning the quality gate, building the release artifact, publishing PowerShell Gallery, and publishing the ZIP plus checksum as a GitHub Release.
- Initial PowerShell module and thin launcher.
- Public command surface for `Copy-GitHubRepository`, `Get-GitHubRepository`, `Start-CopyGitHubRepositoryWizard`, and `Test-GitHubRepositoryMigration`.
- Pester and PSScriptAnalyzer quality-gate foundation.
- Enforced Pester code-coverage reporting and minimum coverage threshold.
- Cross-platform continuous integration configuration with bounded job runtime and diagnostic artifacts.
- Project PowerShell style guide and focused PSScriptAnalyzer policy for objective, low-noise enforcement.
- Architecture, command-design, contribution, security, and versioning documentation.
- Community code of conduct.

### Changed

- PowerShell Gallery manifest description and tags now use the current repository-copy terminology and include `Copy` for package discovery while retaining `Migration` for compatibility and searchability.
- Gallery package validation now rejects unexpected cmdlet, alias, or variable exports and missing declared formatting files before publication.
- Removed the prerelease `alpha` marker from the module manifest in preparation for the initial stable `0.1.0` release.
- Supported settings are written only when the destination differs from the source and are verified after GitHub read-back.
- Removed obsolete compatibility paths that bypassed current same-name migration and repository-settings verification contracts.
- Extracted new-destination Snapshot execution into a dedicated `Invoke-CgrNewDestinationSnapshot` orchestration helper while preserving public behavior.
- Native command execution now applies environment overrides directly to child processes while preserving stdout, stderr, and exit-code capture.
- Renamed the stable convenience bootstrap from `install-latest.ps1` to `install-release.ps1` so the same installer can target either the latest stable release or an explicitly requested stable version.
- The repository-root launcher now starts the same public guided wizard exposed by the installed module.

### Validated

- Guided wizard plan-before-mutation, cancellation/no-change, FullHistory option flow, same-name confirmation flow, and delegation to the deterministic migration API through controlled Pester interaction boundaries.
- Snapshot migration against disposable public and private repositories.
- Snapshot Git LFS transfer and retrieval.
- Same-name Snapshot replacement with archive preservation.
- New-destination FullHistory migration including branches, annotated tags, reachable history, default branch, and Git LFS.
- Same-name FullHistory replacement including archive and replacement identity verification.
- Supported repository-settings restoration with independent source/destination GitHub API comparison.
- Deterministic release artifact generation across repeated builds.
- Release ZIP extraction, isolated current-user-style module installation, installed manifest validation, exact four-command public surface, overwrite refusal, and explicit forced replacement.
- Windows, Ubuntu, and macOS quality gates.
