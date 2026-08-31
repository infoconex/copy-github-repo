---
title: "CopyGitHubRepo Changelog – Release History"
description: "Review CopyGitHubRepo release history, including new features, behavior changes, packaging improvements, and notable updates across stable versions."
---

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Added opt-in GitHub Release preservation for `Snapshot` migrations with `-IncludeReleases`.
- Added deterministic Snapshot checkpoint history construction from selected release states, with recreated release tags pointing to newly created Snapshot checkpoint commits rather than original source commit identities.
- Added Snapshot release filtering, immutable reviewed release/checkpoint planning, fail-closed topology and source/tag/release drift detection, release metadata/assets/Latest restoration, independent verification, recovery evidence, guided wizard support, and controlled GitHub E2E coverage.
- Added the final current-state Snapshot commit only when reviewed source HEAD is not state-equivalent to the latest selected release checkpoint; plain Snapshot remains a single unrelated current-state root commit.

### Changed

- Clarified the user-facing distinction between `Snapshot -IncludeReleases`, which preserves selected release states in a new unrelated checkpoint history, and `FullHistory -IncludeReleases`, which preserves the original Git history and original tag targets.

## [0.2.0] - 2026-08-30

### Added

- Added opt-in GitHub Release preservation for `FullHistory` migrations with `-IncludeReleases`.
- Added release filtering by tag include/exclude wildcard patterns, prerelease/draft opt-in, and newest-N limiting.
- Added immutable release-selection evidence to migration planning so execution restores the exact reviewed releases rather than rerunning a live filter.
- Added post-FullHistory restoration of release metadata and assets with tag-target, release metadata, asset name/label/size/content-type/digest verification where available, plus preservation of the selected source Latest release designation.
- Added fail-closed release drift detection when a selected source release changes after planning, plus release provenance in migration/recovery results.
- Added `Test-GitHubRepositoryMigration -IncludeReleases` with the same release-selection filters for independent read-only FullHistory release verification.
- Added `Start-CopyGitHubRepositoryWizard -Version` to report the loaded module version without starting discovery, planning, or migration activity.
- Added controlled unit, integration, and GitHub E2E coverage for filtered release selection, release assets, Latest designation, tag-target preservation, and independent post-migration verification.

### Changed

- Strengthened release-line safety and reliability by keeping repository-protection restoration bound to reviewed planning evidence, preserving fail-closed GitHub API read behavior, and maintaining verification-before-restoration and recovery-evidence ordering across supported copy paths.
- Improved documentation discoverability and validation with page-specific search/social metadata, sitemap and robots support, structured-data checks, and clearer quality-gate diagnostics.

## [0.1.1] - 2026-08-25

### Changed

- Improved PowerShell Gallery discovery metadata with Windows, Linux, macOS, PowerShell Core, Automation, and DevOps tags plus a more search-friendly package description.
- Pointed the Gallery project and icon metadata at the GitHub Pages documentation site and added an exact 85x85 Gallery icon.
- Added PowerShell Gallery version/download, project-quality, PowerShell-version, and platform badges to the README and improved the documentation site's SEO description.
- Updated Gallery packaging so each staged release automatically receives version-specific `ReleaseNotes` from its matching `CHANGELOG.md` release section.
- Made current-version support and GitHub-host documentation release-line based so future patch releases do not require unnecessary version-number edits.

## [0.1.0] - 2026-08-22

Initial public stable release. Before `v0.1.0` was tagged, the repository was intentionally republished as a clean Snapshot with a new root commit. This entry therefore describes the shipped starting capability set rather than reconstructing the project's prerelease development history.

### Added

- Cross-platform PowerShell module for safely copying GitHub repositories on Windows, macOS, and Linux with PowerShell 7.4+.
- Public commands for repository discovery, guided copying, scripted copying, and independent migration verification: `Get-GitHubRepository`, `Start-CopyGitHubRepositoryWizard`, `Copy-GitHubRepository`, and `Test-GitHubRepositoryMigration`.
- `Snapshot` mode for publishing the approved default-branch contents as a clean repository with one unrelated root commit, and `FullHistory` mode for preserving ordinary branches, tags, reachable commit history, and required Git LFS content.
- Plan-before-mutation workflows, including `-PlanOnly`, `-WhatIf`, immutable source-state checks, destination/archive collision prevention, and fail-closed handling when the approved source changes before mutation.
- Safe new-destination and archive-and-replace workflows, including same-name replacement with exact confirmation, repository identity checks, archive preservation, and no automatic destructive rollback after partial failure.
- Restoration and verification of supported repository settings and transferable repository protection after content verification.
- Structured migration, verification, provenance, and recovery evidence, including durable JSON recovery reports for post-mutation failures.
- GitHub CLI authentication integration for GitHub.com, including private and non-interactive repository operations without intentionally persisting or displaying credential material.
- PowerShell Gallery distribution as the primary stable installation channel, plus versioned GitHub Release artifacts, repository-hosted stable/prerelease installers, and safe uninstall support.
- Deterministic release ZIPs with SHA-256 checksums, SPDX 2.3 SBOMs, and GitHub artifact provenance/SBOM attestations.
- Cross-platform automated quality, security, packaging, documentation, and controlled end-to-end validation for the supported release surface.
- User, command-reference, architecture, security, support, troubleshooting, contributor, governance, and release documentation for the initial supported product contract.
