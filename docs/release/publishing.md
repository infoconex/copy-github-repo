# Publishing to PowerShell Gallery

PowerShell Gallery is the primary public package channel for stable CopyGitHubRepo releases. The repository-hosted installers remain available as bootstrap and pinned-release alternatives.

## Release contract

Stable publication is performed by `.github/workflows/publish-release.yml`, displayed in GitHub Actions as **Publish Release**. The workflow supports two deliberate entry points:

- pushing an exact stable semantic-version tag in the form `vMAJOR.MINOR.PATCH`; or
- manually running **Publish Release** from the `main` branch with the intended stable tag and the `confirm_publish` checkbox selected.

In both cases the requested tag must exactly match `ModuleVersion` in `src/CopyGitHubRepo/CopyGitHubRepo.psd1`.

### Clean same-name publication must happen before the release tag

When the repository itself is being converted to a clean same-name Snapshot publication, do not create the stable tag or GitHub Release on the historical repository first. Snapshot does not copy historical tags or GitHub Releases. The renamed archive retains those records, while the fresh replacement repository starts with the new unrelated root commit.

Use this order for the first stable publication:

```text
clean same-name Snapshot replacement
-> verify the clean replacement and exact candidate commit
-> run release readiness and cross-platform quality validation
-> build release artifacts, SBOM, and attestations
-> verify PowerShell Gallery and GitHub Release do not already contain the version
-> create the stable tag on the approved replacement commit
-> publish the PowerShell Gallery package
-> create/publish the GitHub Release and release assets
```

For `v0.1.0`, the `v0.1.0` tag must therefore resolve to the final qualified clean replacement commit, not to a commit in the archived historical repository. Existing historical tags/releases stay with the archive and are not automatically recreated on the replacement.

Before any release artifacts are built, `build/Test-ReleaseReadiness.ps1` validates the stable-release metadata contract. It requires the tag to match the manifest version exactly, requires a dated changelog entry for that version, requires the `Unreleased` section to be empty, validates the module manifest, and confirms the release-critical build, installer, uninstaller, workflow, and publishing files exist.

For manual dispatch, the workflow additionally requires that the run is started from `main` and that the workflow's exact commit SHA is still the current `main` SHA. This prevents a stale browser tab or an older branch revision from becoming the release source. The exact commit then passes the same reusable cross-platform **Validate Project Quality** workflow used elsewhere in CI.

The publication workflow builds the deterministic GitHub release ZIP and checksum, stages a clean Gallery package under `dist/PSGallery/CopyGitHubRepo`, validates the packaged manifest and exports, generates the SPDX SBOM and GitHub attestations, checks both PSGallery and GitHub for an existing version, ensures the stable tag resolves to the approved release commit, publishes the Gallery package, and then creates the GitHub Release.

A manual run creates an annotated tag only after project-quality validation, release-readiness validation, artifact creation, attestation, and duplicate destination checks have succeeded. If that tag already exists, the workflow reuses it only when it resolves to the exact approved release commit; otherwise publication stops. This makes a safe rerun possible after a failure that occurred after tag creation but before publication.

The workflow does not publish from ordinary branch pushes or pull requests. It does not change versions automatically.

## GitHub configuration

Create a protected GitHub Actions environment named `powershell-gallery`. Store the PowerShell Gallery API key in that environment as a secret named:

```text
PSGALLERY_API_KEY
```

The release job references the secret only in the Gallery publication step. Do not store the key in repository files, workflow variables, command-line examples containing a real value, comments, or logs.

Where practical, configure the `powershell-gallery` environment with required reviewers so a version tag or manual release request cannot immediately consume the production publishing credential without maintainer approval.

## Creating and rotating the Gallery API key

Sign in to PowerShell Gallery with the account that owns or is authorized to publish `CopyGitHubRepo`, then create an API key with only the permissions needed to push the module. Store the value directly in the `powershell-gallery` environment secret.

For rotation, create a replacement key, update the GitHub environment secret, confirm a subsequent controlled release can authenticate, and revoke the old key. Revoke a key immediately if exposure is suspected. Never commit a replacement key while responding to an incident.

## Release-readiness validation

Before creating or requesting a stable release, run:

```powershell
./build/Test-ReleaseReadiness.ps1 -Tag v0.1.0 -RequireEmptyUnreleased
```

Replace `v0.1.0` with the intended release tag. The command must succeed before publication. The `Unreleased` section should contain only changes that are not part of the release commit; because a stable release includes the entire commit, any entries describing code already present in that commit must be moved into the matching version section first.

This check intentionally does not create, move, or publish a tag. **Publish Release** remains the deliberate publication boundary.

## Phone-friendly release from GitHub web

A maintainer can publish a stable release without a local Git checkout by using the GitHub Actions web interface, including from a phone:

1. Open the repository on GitHub.
2. Open **Actions**.
3. Select **Publish Release**.
4. Choose **Run workflow**.
5. Ensure the branch selector is **main**.
6. Enter the intended stable tag, for example `v0.1.0`.
7. Select `confirm_publish`.
8. Run the workflow.

The workflow refuses to continue if the selected ref is not `main`, if the captured commit is no longer the current `main` SHA, if the tag does not match the manifest version, if `Unreleased` is not empty, if **Validate Project Quality** fails, or if the version already exists in PowerShell Gallery or as a GitHub Release.

For a successful manual run, the workflow creates an annotated tag for the exact validated commit immediately before publication. The tag is then used by the GitHub Release created later in the same workflow run. Do not separately draft or publish a GitHub Release from the Releases page; the workflow owns that operation.

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

For a manual fallback, run both local quality/package commands before publication:

```powershell
./build/Test-Project.ps1
./build/New-PowerShellGalleryPackage.ps1
```

A change is not release-ready merely because the source module imports successfully; the exact staged package must also pass validation.

## Manual publication fallback

Automation is preferred. If GitHub Actions is unavailable and a maintainer must publish manually, use the exact approved source revision and the same staged package produced by `New-PowerShellGalleryPackage.ps1`.

First validate without publishing:

```powershell
./build/Test-Project.ps1
./build/Test-ReleaseReadiness.ps1 -Tag v0.1.0 -RequireEmptyUnreleased
./build/New-PowerShellGalleryPackage.ps1
Test-ModuleManifest ./dist/PSGallery/CopyGitHubRepo/CopyGitHubRepo.psd1
Find-PSResource CopyGitHubRepo -Version 0.1.0 -Repository PSGallery
Publish-PSResource `
    -Path ./dist/PSGallery/CopyGitHubRepo `
    -Repository PSGallery `
    -ApiKey $apiKey `
    -WhatIf
```

Replace `0.1.0` and `v0.1.0` with the manifest version and tag being released. If `Find-PSResource` returns that exact version, stop; released versions are treated as immutable and must not be overwritten. If `Find-PSResource` reports that the exact package/version cannot be found, that is the expected pre-publication state. Other lookup errors should be investigated rather than treated as proof that the version is absent.

When the dry run and all validation are satisfactory, rerun `Publish-PSResource` without `-WhatIf`. Keep the API key in memory or a secure secret store and do not echo it. The legacy PowerShellGet compatibility command is `Publish-Module`, but new project automation uses `Publish-PSResource` from `Microsoft.PowerShell.PSResourceGet`.

## Prereleases

Prerelease Gallery publication is intentionally not enabled for the initial release process. Tags such as `v0.2.0-beta1` are rejected rather than guessed or published as stable. If prerelease support is added later, the manifest prerelease metadata, tag convention, Gallery lookup, documentation, and workflow tests must be introduced together.

## Signing policy

Authenticode signing is optional for the initial PSGallery release and is not a `v0.1.0` blocker. Initial packages may be unsigned. Signing can be added later for stronger publisher identity or enterprise trust requirements, but certificate and private-key handling must be implemented as a separate security-sensitive change and must not weaken CI secret handling.

## Partial publication failure

GitHub Release and PowerShell Gallery are separate services and cannot be updated atomically. The workflow performs all local validation and both duplicate checks before either publication. It publishes PSGallery first and the GitHub Release second.

If Gallery publication succeeds but GitHub Release creation subsequently fails, do not overwrite or republish the Gallery version. Investigate the failure and use an explicitly reviewed recovery procedure. The normal workflow intentionally fails closed on duplicate versions rather than silently repairing a partially published release.
