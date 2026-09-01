---
title: "CopyGitHubRepo Source Code Documentation Policy – PowerShell Help and Inventories"
description: "Review CopyGitHubRepo source documentation requirements for public PowerShell help, private-function documentation tiers, operational script inventories, comments, and automated enforcement."
---

# Source code documentation policy

This document defines the maintainership documentation standard for the PowerShell source and operational scripts. The objective is useful engineering context, not comment volume.

## Documentation tiers

Public commands must provide complete native PowerShell comment-based help: synopsis, description, meaningful help for every declared parameter, examples, inputs, outputs, and related links. Help must describe defaults, parameter-set behavior, destructive-operation safeguards, limitations, and `-WhatIf`, `-Confirm`, or `-Force` semantics where applicable.

Every private function is accounted for in the inventory below. Most small private helpers use the **catalog** tier: the function name, file boundary, and responsibility are documented here while the implementation remains uncluttered. Functions that form critical planning or Git/GitHub mutation boundaries use the **inline** tier and additionally carry comment-based help beside the function. `tests/SourceDocumentationPolicy.psd1` is the machine-readable list of inline-help boundaries.

The module manifest/bootstrap and significant build, installation, release, and live E2E scripts are also inventoried below. Their entries record purpose and operational risk even when their implementation is intentionally procedural.

Do not add author, creation-date, last-modified, or change-history headers. Git is the source of truth for authorship and history. Comments should explain why a constraint exists, safety and failure semantics, invariants, non-obvious Git/GitHub behavior, cross-platform assumptions, or output contracts. Avoid comments that merely restate the next PowerShell statement.

## Module files

| File | Responsibility |
| --- | --- |
| `src/CopyGitHubRepo/CopyGitHubRepo.psd1` | Defines the Gallery/module contract: version metadata, supported PowerShell version, exported public commands, tags, links, and formatting data. |
| `src/CopyGitHubRepo/CopyGitHubRepo.psm1` | Module bootstrap that enables strict behavior, dot-sources private helpers first, then dot-sources the public command surface in deterministic file-name order. |

## Private function inventory

| Function | Responsibility |
| --- | --- |
| `Assert-CgrApprovedSourceState` | Fails closed when current source identity or Git state no longer matches the reviewed plan evidence. |
| `Assert-CgrDestinationPagesReadBack` | Independently reads destination Pages after mutation and fails closed when the reviewed build mode, exact legacy source, custom domain, or HTTPS intent disagrees. |
| `Assert-CgrDestinationPagesSource` | Validates that the exact reviewed legacy Pages branch/path exists at the destination before mutation and refuses substitute branches or paths. |
| `Assert-CgrExistingDestinationReplacementConfirmation` | Enforces exact confirmation before an existing destination is archived and replaced. |
| `Assert-CgrFullHistoryWorkspaceState` | Verifies a local FullHistory workspace against immutable approved refs and commit evidence. |
| `Assert-CgrGitHubPagesPlanEvidence` | Requires immutable reviewed `Plan.Pages` evidence and revalidates only its drift-driving source state immediately before destination Pages mutation. |
| `Assert-CgrLocalResourcePreflight` | Checks current free space on the temporary-storage volume against the observed planning-workspace lower bound before GitHub mutation; insufficient known capacity fails closed while uncertain/headroom cases remain advisory. |
| `Assert-CgrReplacementRepositoryIdentity` | Verifies archive identity is preserved and the fresh replacement has a distinct repository identity. |
| `Assert-CgrSameNameReplacementConfirmation` | Enforces exact confirmation for the highest-risk same-name publication path. |
| `Assert-CgrSupportedHostName` | Restricts operations to the GitHub host contract supported by this version. |
| `ConvertTo-CgrRepository` | Normalizes GitHub API repository payloads into the module repository output contract. |
| `ConvertTo-CgrRepositoryName` | Canonicalizes owner/name identity for stable comparisons. |
| `ConvertTo-CgrWizardNavigationResult` | Normalizes wizard navigation responses into the internal navigation contract. |
| `Copy-CgrApprovedGitHubRelease` | Restores only the GitHub Releases captured in the approved FullHistory plan, revalidates selected source release/tag/asset evidence before mutation, refuses destination-release overwrite, preserves the selected Latest designation when applicable, and verifies destination metadata/assets after creation. |
| `Copy-CgrGitLfsObject` | Transfers Snapshot Git LFS content while preserving explicit failure evidence. |
| `Copy-CgrRepositoryFullHistory` | **Inline tier.** Copies branches, tags, reachable commits, and Git LFS objects after approved-state validation. |
| `Copy-CgrRepositorySnapshot` | **Inline tier.** Publishes an approved branch tree as one unrelated root commit and verifies the pushed ref. |
| `Enable-CgrPagesWorkflowActivationAfterRestore` | Releases the temporary Pages-specific activation guard only after reviewed Pages or no-Pages verification succeeds, then verifies Actions is enabled. |
| `Format-CgrConsoleStatus` | Produces accessible textual status presentation independent of migration behavior. |
| `Format-CgrMigrationExecutionResult` | Converts structured execution evidence into the human-readable execution report. |
| `Format-CgrMigrationPlan` | Converts an immutable migration plan into its reviewable console representation. |
| `Format-CgrWizardText` | Applies consistent wizard text formatting without changing workflow behavior. |
| `Get-CgrActivityCompletionMessage` | Maps activity outcomes to consistent completion messages. |
| `Get-CgrActivityTerminalState` | Derives the terminal activity state from structured stage output. |
| `Get-CgrApprovedSourceState` | Captures immutable Snapshot or FullHistory source evidence used to bind planning to execution. |
| `Get-CgrDefaultArchiveRepositoryName` | Creates the safe default archive name used by replacement workflows. |
| `Get-CgrGitCommitIdentity` | Resolves the authenticated identity used to author the clean Snapshot root commit. |
| `Get-CgrGitHubApi` | Executes required GitHub API reads and converts failures into stable application errors. |
| `Get-CgrGitHubApiOptional` | Performs optional GitHub API reads where unsupported or unavailable data is an expected condition. |
| `Get-CgrGitHubAuthenticationStatus` | Reports GitHub CLI authentication readiness without mutating account state. |
| `Get-CgrGitHubPagesPlanEvidence` | Captures immutable reviewed GitHub-side Pages configuration, representability, external readiness, and drift-driving evidence for opt-in planning without mutating Pages or querying external DNS. |
| `Get-CgrGitHubReleaseSelection` | Enumerates GitHub Releases, applies the public release-filter policy, resolves selected tag commit identities, captures asset evidence and the source Latest designation, and returns the exact release inventory bound into a FullHistory plan or standalone verification. |
| `Get-CgrObjectProperty` | Safely reads optional properties from heterogeneous GitHub/module result objects. |
| `Get-CgrPrerequisiteStatus` | Aggregates Git, GitHub CLI, and authentication prerequisites for public workflows. |
| `Get-CgrRepository` | Retrieves repository state and normalizes it through the repository contract. |
| `Get-CgrRepositoryDefaultBranchTree` | Reads a repository default-branch tree, including pagination-sensitive Snapshot evidence. |
| `Get-CgrRepositoryFullHistoryIdentity` | Captures branches, tags, reachable commits, and FullHistory identity for comparison. |
| `Get-CgrRepositoryProtectionConfiguration` | Captures transferable protection while identifying settings that cannot be safely reproduced. |
| `Get-CgrSnapshotHistory` | Reads Snapshot history evidence used to prove the destination contains a clean publication root. |
| `Get-CgrSnapshotReleasePreservationEvidence` | Builds additive Snapshot `-IncludeReleases` provenance from immutable reviewed planning evidence plus completed execution results, or performs read-only destination observation after failure to record published checkpoint/tag/release/asset state without rollback or repair. |
| `Invoke-CgrActivityStage` | Wraps a logical operation with structured activity start/completion/failure signaling. |
| `Invoke-CgrApprovedFullHistoryVerification` | Verifies copied FullHistory against the exact approved source evidence rather than a moving source. |
| `Invoke-CgrApprovedMigrationPlan` | Executes only the reviewed plan and routes to the correct migration/replacement mode. |
| `Invoke-CgrApprovedSnapshotReleaseVerification` | Performs read-only verification of generated Snapshot release-checkpoint history against immutable reviewed checkpoint evidence, including sequence, parentage, tree equivalence, selected tag targets, and final reviewed HEAD state. |
| `Invoke-CgrExistingDestinationReplacement` | **Inline tier.** Archives an existing destination, proves identity preservation, creates a fresh replacement, and emits recovery evidence on failure. |
| `Invoke-CgrGitCommand` | Runs Git with the repository authentication/environment conventions required by the module. |
| `Invoke-CgrGitHubApiMutation` | Centralizes GitHub API mutation execution and application-grade error handling. |
| `Invoke-CgrGitHubApiReadRequest` | Applies bounded retry/backoff only to side-effect-free GitHub API reads, honoring bounded server retry guidance while keeping mutation retries out of scope. |
| `Invoke-CgrNativeCommand` | Captures native-process stdout, stderr, and exit status without leaking stream implementation details. |
| `Invoke-CgrNewDestinationFullHistory` | **Inline tier.** Orchestrates FullHistory copy, verification, optional approved-release restoration, settings/protection restoration, and recovery reporting for a new destination. |
| `Invoke-CgrNewDestinationSnapshot` | **Inline tier.** Orchestrates Snapshot publication, verification, settings/protection restoration, and recovery reporting for a new destination. |
| `Invoke-CgrPostVerificationConfigurationRestore` | Centralizes post-verification supported-settings, reviewed Pages restoration and activation-guard release, and planned-protection restoration, including `SkipSettings`, structured completeness results, and precise recovery-stage evidence. |
| `Invoke-CgrRepositoryCopyWizard` | Implements the testable wizard state machine while keeping prompts separate from migration execution. |
| `Invoke-CgrRepositoryFullHistoryVerification` | Compares live source and destination history when immutable approved evidence is not supplied. |
| `Invoke-CgrRepositorySnapshotVerification` | Verifies destination tree/root-history semantics against approved Snapshot evidence. |
| `Invoke-CgrSameNameFullHistoryReplacement` | **Inline tier.** Preserves the source as an archive before publishing a fresh same-name FullHistory replacement, with optional approved-release restoration from the preserved archive. |
| `Invoke-CgrSameNameSnapshotReplacement` | **Inline tier.** Preserves the source as an archive before publishing a fresh same-name Snapshot replacement. |
| `Invoke-CgrWithActivitySink` | Scopes activity event delivery to the current operation without global presentation coupling. |
| `New-CgrGitHubRepository` | Creates an empty destination repository after the public safety boundary has approved mutation. |
| `New-CgrMigrationPlan` | **Inline tier.** Creates the immutable reviewed plan, source-state evidence, optional approved-release selection, replacement mode, and ordered safety steps without performing migration mutation. |
| `New-CgrSnapshotReleaseCheckpointPlan` | **Inline tier.** Converts the already-approved Snapshot release selection into immutable tag/ref/tree evidence and a deterministic ancestry-ordered checkpoint sequence, coalescing duplicate targets and failing closed on incompatible release-to-release or release-to-HEAD topology without performing mutation. |
| `New-CgrWizardActivitySink` | Creates the wizard activity adapter used to render structured progress events. |
| `Protect-CgrDiagnosticText` | Redacts or normalizes sensitive diagnostic text before presentation or persistence. |
| `Read-CgrWizardChoice` | Reads a bounded menu choice with default/help/navigation behavior suitable for mocked tests. |
| `Read-CgrWizardInput` | Provides the base injectable wizard input boundary. |
| `Read-CgrWizardRepositoryName` | Reads and validates repository-name input while supporting wizard navigation. |
| `Read-CgrWizardTextValue` | Reads text input with default, validation, help, and navigation semantics. |
| `Rename-CgrGitHubRepository` | Renames a repository while verifying the returned GitHub identity remains the original repository. |
| `Resolve-CgrNativeCommand` | Resolves required native executables consistently across supported platforms. |
| `Resolve-CgrWizardDestinationRepository` | Resolves wizard destination identity and replacement implications. |
| `Resolve-CgrWizardNavigationInput` | Interprets navigation/help tokens without mixing them with business values. |
| `Restore-CgrGitHubPagesConfiguration` | Restores supported GitHub-side Pages state from immutable reviewed plan evidence, verifies destination readback, keeps replacement custom-domain handoff separate, and coordinates activation-guard release. |
| `Select-CgrWizardRepository` | Presents and resolves repository selection using the injectable wizard interaction contract. |
| `Send-CgrActivityEvent` | Emits structured activity events only when an activity sink is active. |
| `Set-CgrGitHubRepositorySetting` | Restores supported repository settings after content verification and reports unsupported state explicitly. |
| `Set-CgrRepositoryProtectionConfiguration` | Restores transferable protection without weakening identity-bound or unsupported rules. |
| `Show-CgrWizardHelp` | Displays contextual help and returns control to the originating prompt. |
| `Test-CgrConsoleStylingAvailable` | Detects whether optional styling can be used without making color a correctness dependency. |
| `Test-CgrExpectedWizardApplicationError` | Distinguishes expected application errors from unexpected implementation failures for user-facing presentation. |
| `Test-CgrGitHubPagesDriftEvidenceMatch` | Compares only contract-relevant Pages drift fields between reviewed evidence and the immediate pre-mutation source read. |
| `Test-CgrGitHubPagesMigration` | Independently reads destination GitHub Pages configuration and compares deterministic GitHub-side state with immutable reviewed plan evidence while reporting external readiness separately. |
| `Test-CgrGitHubReleaseMigration` | Performs read-only current source-versus-destination verification for a selected FullHistory GitHub Release set, including tag commit identity, supported metadata/assets, and Latest designation when selected. |
| `Test-CgrGitHubRepositoryExistence` | Checks repository existence while preserving the distinction between not-found and API failure. |
| `Test-CgrInteractiveTerminal` | Detects whether interactive wizard operation is appropriate in the current host. |
| `Write-CgrExistingDestinationRecoveryReport` | Persists recovery evidence for partial existing-destination replacement. |
| `Write-CgrMigrationExecutionReport` | Writes the structured successful execution report to a requested path. |
| `Write-CgrMigrationPlanReport` | Writes a reviewed plan artifact without executing it. |
| `Write-CgrMigrationRecoveryReport` | Persists generic recovery evidence when a new-destination migration fails after mutation begins. |
| `Write-CgrSameNameRecoveryReport` | Persists identities and completed stages needed to recover a partial same-name replacement. |
| `Write-CgrWizardActivityEvent` | Renders structured activity events for the interactive wizard. |
| `Write-CgrWizardCompletionSummary` | Presents the final wizard result without changing the structured execution object. |
| `Write-CgrWizardMessage` | Writes consistently styled wizard messages with a plain-text fallback. |

## Operational script inventory

| Script | Purpose and operational context |
| --- | --- |
| `build/Install-DevelopmentDependencies.ps1` | Installs only repository-pinned development dependencies into the current-user PowerShell module scope. |
| `build/Invoke-LiveScaleCharacterization.ps1` | Runs authenticated disposable Snapshot and FullHistory GitHub.com E2E characterization and writes non-SLA evidence; it requires repository creation/deletion capability and relies on the E2E harnesses for protected-prefix cleanup. |
| `build/Measure-ScaleCharacterization.ps1` | Measures local Git fixture scale, clone timing, workspace consumption, and environment metadata for non-SLA characterization evidence. |
| `build/New-PowerShellGalleryPackage.ps1` | Builds and validates the minimal Gallery module payload and isolated import contract. |
| `build/New-ReleaseArtifact.ps1` | Produces release artifacts from validated source rather than ad-hoc working-tree content. |
| `build/New-ReleaseSbom.ps1` | Generates the deterministic SPDX 2.3 JSON SBOM from the completed release ZIP, binds it to the exact source commit, and keeps development/CI dependencies outside the shipped runtime graph. |
| `build/New-ScaleCharacterizationFixture.ps1` | Generates deterministic local Git fixtures used by the scale-characterization harness without claiming a production support limit. |
| `build/Set-PowerShellGalleryReleaseNotes.ps1` | Extracts the current version's dated `CHANGELOG.md` section and injects it into the staged Gallery manifest so each immutable package carries version-specific release notes. |
| `build/Test-Documentation.ps1` | Runs the narrow documentation validation path used for documentation-only changes. |
| `build/Test-GeneratedSite.ps1` | Validates generated GitHub Pages content and site-link assumptions. |
| `build/Test-Project.ps1` | Canonical local/CI quality gate: analyzer, classified Pester suites, and aggregate coverage for `All`. |
| `build/Test-ReleaseReadiness.ps1` | Checks release metadata and packaging prerequisites before publication. |
| `copy-github-repo.ps1` | Compatibility launcher that imports the module and starts the supported workflow. |
| `install.ps1` | Installs the module from repository source using the documented trust/security model. |
| `install-prerelease.ps1` | Installs an explicitly selected prerelease artifact for validation. |
| `install-release.ps1` | Installs a published release artifact with integrity/security checks. |
| `uninstall.ps1` | Discovers installed copies, obtains confirmation as needed, and removes only selected module installations. |
| `tests/e2e/Invoke-CleanSnapshotDemonstration.ps1` | Creates disposable repositories to demonstrate clean Snapshot publication; this is a demonstration, not part of the E2E test taxonomy. |
| `tests/e2e/Invoke-FullHistoryEndToEndTests.ps1` | Exercises a live FullHistory copy against disposable GitHub repositories. |
| `tests/e2e/Invoke-GitHubReleaseEndToEndTests.ps1` | Exercises filtered FullHistory GitHub Release restoration against disposable repositories, including assets, Latest designation, ordinary tag-target preservation, and independent post-migration release verification. |
| `tests/e2e/Invoke-GitLfsEndToEndTests.ps1` | Exercises live Git LFS transfer behavior. |
| `tests/e2e/Invoke-RecoveryEndToEndTests.ps1` | Exercises live failure/recovery evidence paths. |
| `tests/e2e/Invoke-RepositorySettingsEndToEndTests.ps1` | Exercises live supported-settings restoration. |
| `tests/e2e/Invoke-SameNameEndToEndTests.ps1` | Exercises live same-name Snapshot archive-and-replace behavior. |
| `tests/e2e/Invoke-SameNameFullHistoryEndToEndTests.ps1` | Exercises live same-name FullHistory archive-and-replace behavior. |
| `tests/e2e/Invoke-SnapshotEndToEndTests.ps1` | Exercises live clean Snapshot publication and verification. |
| `tests/e2e/Invoke-SnapshotReleaseEndToEndTests.ps1` | Exercises Snapshot release preservation against disposable GitHub repositories, including filtered sequential checkpoints, assets, Latest designation, final-HEAD behavior, same-name replacement safeguards, and independent Git/GitHub verification. |

The E2E scripts create and delete real repositories and therefore require authenticated GitHub access with repository creation and deletion capability. They remain outside the routine Quality Gate by design.

## Enforcement

`tests/SourceDocumentation.Tests.ps1` enforces this policy through source discovery and PowerShell AST inspection. Every private function must be represented in this document. The module manifest/bootstrap must be inventoried. Every root, `build/`, and `tests/e2e/` PowerShell script is discovered automatically and must match the machine-readable operational-script policy and this inventory. Every inline-tier function must contain attached comment-based help, and public-command coverage is derived from the module manifest rather than a hard-coded command list.