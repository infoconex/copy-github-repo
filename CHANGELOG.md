---
title: "CopyGitHubRepo Changelog – Release History"
description: "Review CopyGitHubRepo release history, including new features, behavior changes, packaging improvements, and notable updates across stable versions."
---

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
