---
title: "Publish CopyGitHubRepo to PowerShell Gallery – Release Workflow and Validation"
description: "Learn how stable CopyGitHubRepo releases are integrated, qualified, and published from the exact approved main commit to PowerShell Gallery and GitHub Releases."
---

# Publishing to PowerShell Gallery

PowerShell Gallery is the primary public package channel for stable CopyGitHubRepo releases. The repository-hosted installers remain available as bootstrap and pinned-release alternatives.

## Release contract

Stable publication is performed by `.github/workflows/publish-release.yml`, displayed in GitHub Actions as **Publish Release**.

Stable publication is manual-dispatch-only from `main`. The release branch must first be integrated through the protected pull-request process, and final release qualification must apply to the exact resulting `main` SHA. Publication must use that same SHA.

The workflow requires the intended stable tag and the `confirm_publish` checkbox. The requested tag must exactly match `ModuleVersion` in `src/CopyGitHubRepo/CopyGitHubRepo.psd1`.

This ordering is deliberate:

```text
finish release work on release branch
-> integrate release branch into main through required PR controls
-> record exact resulting main SHA
-> qualify that exact main SHA
-> reconfirm main has not moved
-> manually dispatch Publish Release from main
-> rerun release readiness and cross-platform quality validation
-> build release artifacts, SBOM, and attestations
-> verify PowerShell Gallery and GitHub Release do not already contain the version
-> create or safely reuse the stable tag on the approved main commit
-> publish the PowerShell Gallery package
-> create/publish the GitHub Release and release assets
-> verify both distribution channels
```

Do not create the stable tag before final qualification during the normal release process. A tag is an externally visible release identity and must not be used as a substitute for integration or exact-candidate qualification.

### Clean same-name publication

When the repository itself is being converted to a clean same-name Snapshot publication, complete and verify that replacement before integrating and qualifying the stable release candidate. Snapshot does not copy historical tags or GitHub Releases. The renamed archive retains those records, while the fresh replacement repository starts with the new unrelated root commit.

For the initial stable publication, the stable tag must resolve to the final qualified clean replacement commit, not to a commit in the archived historical repository.

Before any release artifacts are built, `build/Test-ReleaseReadiness.ps1` validates the stable-release metadata contract. It requires the tag to match the manifest version exactly, requires a dated changelog entry for that version, requires the `Unreleased` section to be empty, validates the module manifest, and confirms the release-critical build, installer, uninstaller, workflow, and publishing files exist.

The workflow additionally requires that the run is started from `main` and that the workflow's exact commit SHA is still the current `main` SHA. This prevents a stale browser tab or an older revision from becoming the release source. The exact commit then passes the same reusable cross-platform **Validate Project Quality** workflow used elsewhere in CI.

The publication workflow builds the deterministic GitHub release ZIP and checksum, stages a clean Gallery package under `dist/PSGallery/CopyGitHubRepo`, validates the packaged manifest and exports, generates the SPDX SBOM and GitHub attestations, checks both PSGallery and GitHub for an existing version, ensures the stable tag resolves to the approved release commit, publishes the Gallery package, and then creates the GitHub Release.

The workflow creates an annotated tag only after project-quality validation, release-readiness validation, artifact creation, attestation, and duplicate destination checks have succeeded. If that tag already exists, the workflow reuses it only when it resolves to the exact approved release commit; otherwise publication stops.

The workflow does not publish from ordinary branch pushes, pull requests, or tag pushes. It does not change versions automatically.

## GitHub configuration

Create a protected GitHub Actions environment named `powershell-gallery`. Store the PowerShell Gallery API key in that environment as a secret named:

```text
PSGALLERY_API_KEY
```

The release job references the secret only in the Gallery publication step. Do not store the key in repository files, workflow variables, command-line examples containing a real value, comments, or logs.

Where practical, configure the `powershell-gallery` environment with required reviewers so a manual release request cannot immediately consume the production publishing credential without maintainer approval.

## Release-readiness validation

Before requesting a stable release, run:

```powershell
./build/Test-ReleaseReadiness.ps1 -Tag v0.2.0 -RequireEmptyUnreleased
```

Replace `v0.2.0` with the intended release tag. The command must succeed on the exact `main` SHA being qualified before publication.

This check intentionally does not create, move, or publish a tag. **Publish Release** remains the deliberate publication boundary.

## Phone-friendly release from GitHub web

A maintainer can publish a stable release without a local Git checkout by using the GitHub Actions web interface, including from a phone:

1. Confirm final qualification recorded `GO` for the exact current `main` SHA.
2. Open the repository on GitHub.
3. Open **Actions**.
4. Select **Publish Release**.
5. Choose **Run workflow**.
6. Ensure the branch selector is **main**.
7. Enter the intended stable tag, for example `v0.2.0`.
8. Select `confirm_publish`.
9. Run the workflow.

The workflow refuses to continue if the selected ref is not `main`, if the captured commit is no longer the current `main` SHA, if the tag does not match the manifest version, if `Unreleased` is not empty, if **Validate Project Quality** fails, or if the version already exists in PowerShell Gallery or as a GitHub Release.

For a successful run, the workflow creates an annotated tag for the exact validated commit immediately before publication. The tag is then used by the GitHub Release created later in the same workflow run. Do not separately draft or publish a GitHub Release from the Releases page.

## Package validation

Create and validate the clean Gallery package locally with:

```powershell
./build/New-PowerShellGalleryPackage.ps1
```

The package is staged at:

```text
dist/PSGallery/CopyGitHubRepo
```

During staging, `build/Set-PowerShellGalleryReleaseNotes.ps1` extracts the matching dated version section from `CHANGELOG.md` and writes that text into the staged manifest's `PSData.ReleaseNotes`. The source manifest keeps a stable releases-page fallback, while every immutable PowerShell Gallery version receives its own version-specific release notes automatically. Packaging fails if the current module version has no matching non-empty changelog section or if the injected `ReleaseNotes` value cannot be parsed back exactly.

The build fails if `Test-ModuleManifest` fails, if the manifest export surface differs from the public command contract, if aliases, variables, or cmdlets are unexpectedly exported, if a declared formatting file is absent, if common development directories appear in the package, or if the staged module cannot be imported with the expected command surface.

Package validation also launches a fresh `pwsh -NoProfile -NonInteractive` process and imports the staged manifest there. This isolated smoke test prevents a source-tree import or an already-loaded development module from masking a packaging defect.

The **Validate Project Quality** workflow is authoritative for Pester and broad PSScriptAnalyzer validation and also builds and validates the staged Gallery package on Windows, macOS, and Ubuntu. The separate **Analyze Code Security** workflow provides the focused PowerShell security profile and targeted security behavior evidence; it does not replace the broader project-quality gate.

## Manual publication fallback

Automation is preferred. If GitHub Actions is unavailable and a maintainer must publish manually, use the exact approved `main` revision and the same staged package produced by `New-PowerShellGalleryPackage.ps1`.

First validate without publishing:

```powershell
./build/Test-Project.ps1
./build/Test-ReleaseReadiness.ps1 -Tag v0.2.0 -RequireEmptyUnreleased
./build/New-PowerShellGalleryPackage.ps1
Test-ModuleManifest ./dist/PSGallery/CopyGitHubRepo/CopyGitHubRepo.psd1
Find-PSResource CopyGitHubRepo -Version 0.2.0 -Repository PSGallery
Publish-PSResource `
    -Path ./dist/PSGallery/CopyGitHubRepo `
    -Repository PSGallery `
    -ApiKey $apiKey `
    -WhatIf
```

Replace `0.2.0` and `v0.2.0` with the manifest version and tag being released. If `Find-PSResource` returns that exact version, stop; released versions are treated as immutable and must not be overwritten. If it reports that the exact package/version cannot be found, that is the expected pre-publication state. Other lookup errors should be investigated rather than treated as proof that the version is absent.

When the dry run and all validation are satisfactory, rerun `Publish-PSResource` without `-WhatIf`. Keep the API key in memory or a secure secret store and do not echo it.

## Prereleases

Prerelease Gallery publication is intentionally not enabled by the stable publication workflow. Tags such as `v0.3.0-beta1` are rejected rather than guessed or published as stable. If prerelease support is added later, the manifest prerelease metadata, tag convention, Gallery lookup, documentation, and workflow tests must be introduced together.

## Signing policy

Authenticode signing is optional unless a release-readiness decision makes it required. Checksums, SPDX SBOMs, and GitHub attestations do not constitute independent publisher signing.

## Partial publication failure

GitHub Release and PowerShell Gallery are separate services and cannot be updated atomically. The workflow performs all local validation and both duplicate checks before either publication. It publishes PSGallery first and the GitHub Release second.

If Gallery publication succeeds but GitHub Release creation subsequently fails, do not overwrite or republish the Gallery version. Investigate the failure and use an explicitly reviewed recovery procedure. The normal workflow intentionally fails closed on duplicate versions rather than silently repairing a partially published release.

If a stable tag already exists but resolves to a different commit than the exact approved `main` SHA, normal publication must stop. Do not move or recreate the tag as part of an ordinary release retry; use the release incident/recovery process to decide the appropriate versioned correction.
