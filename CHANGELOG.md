---
title: "CopyGitHubRepo Changelog – Release History"
description: "Review CopyGitHubRepo release history, including new features, behavior changes, packaging improvements, and notable updates across stable versions."
---

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

No unreleased product changes.

## [0.4.0] - 2026-09-01

### Added

- Added opt-in GitHub Pages configuration restoration with `-RestorePages`, binding execution to immutable reviewed Pages evidence captured during planning and revalidating relevant source state before destination mutation.
- Added restoration and independent verification for supported GitHub-side Pages configuration, including Actions-based publishing and representable branch/path publishing without treating copied site or workflow files as proof that Pages configuration was preserved.
- Added controlled Pages activation behavior so copied Pages workflows do not silently become authoritative migration evidence or enable unsupported GitHub-side state outside the reviewed restoration path.
- Added same-name and archive-and-replace custom-domain handoff with fail-closed repository identity safeguards, deliberate archive release/replacement claim ordering, independent readback, and durable recovery/provenance evidence for partial handoff failures.
- Added guided-wizard support, command/reference documentation, operational guidance, contract tests, and controlled GitHub end-to-end coverage for the supported Pages migration paths.

### Changed

- Clarified that external DNS records, DNS ownership-verification records, secret values, account/organization domain ownership, certificate provisioning, and externally dependent HTTPS readiness are outside the migration contract and are reported rather than assumed complete.
- Clarified branch/path representability and failure behavior: CopyGitHubRepo does not invent substitute publishing branches or paths when the reviewed source Pages configuration cannot be represented safely at the destination.
- Extended migration verification and recovery reporting to distinguish migrated GitHub-side Pages state from externally observed DNS, domain-verification, certificate, and HTTPS readiness state.

## [0.3.0] - 2026-08-31

### Added

- Added opt-in GitHub Release preservation for `Snapshot` migrations with `-IncludeReleases`, building a clean unrelated checkpoint history from selected reviewed release states instead of preserving original source commit identity or detailed ancestry.
- Added deterministic ancestry-ordered Snapshot checkpoint planning from immutable reviewed tag, ref, and tree evidence, including duplicate-target coalescing and fail-closed handling for incompatible release topology or selected source drift.
- Added recreation of selected release tags, GitHub Release metadata, assets, and Latest designation against generated Snapshot checkpoint commits, with independent read-only verification of checkpoint sequence, parentage, tree equivalence, tag targets, release content, and final current-state behavior.
- Added Snapshot release-preservation options to the guided wizard, including the same tag include/exclude, prerelease, draft, and newest-N filters available to the command surface.
- Added Snapshot release-preservation provenance and recovery evidence plus controlled unit, integration, and live GitHub end-to-end coverage for new-destination, same-name replacement, filtering, assets, Latest designation, and final-HEAD scenarios.

### Changed

- Clarified the Snapshot contract across user, reference, product, and engineering documentation: plain Snapshot remains one unrelated current-state root commit, while `Snapshot -IncludeReleases` creates new checkpoint commits and intentionally does not preserve original commit identities or ancestry; FullHistory remains the history- and tag-target-preserving mode.
- Extended product traceability and migration orchestration documentation to distinguish plain Snapshot, Snapshot release checkpoints, and FullHistory release preservation consistently.

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

- Cross-platform PowerShell module for safely copying and migrating GitHub repositories on Windows, macOS, and Linux with PowerShell 7.4+.
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
