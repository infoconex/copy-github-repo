# Versioning and releases

Copy GitHub Repository follows Semantic Versioning 2.0.0. Version `0.1.0` is the initial stable release.

- `MAJOR` changes indicate incompatible public command, report, or behavior contracts.
- `MINOR` changes add backward-compatible capabilities.
- `PATCH` changes contain backward-compatible fixes and documentation updates.

Before version `1.0.0`, the project is under active development and may make incompatible changes in minor versions. Such changes must be documented in the changelog and follow the notice/migration rules in [Support, compatibility, and deprecation policy](../user/support-policy.md).

The support policy is authoritative for which released version receives fixes, PowerShell/platform/prerequisite compatibility expectations, deprecation notice, and end-of-support decisions. Versioning defines release-number semantics; it does not create a separate support matrix.

The module manifest is the source of truth for the package version. Releases must include:

- A versioned, dated changelog entry that matches `ModuleVersion`
- An empty `Unreleased` section at the stable tag boundary
- Passing Windows, Ubuntu, and macOS quality gates
- Passing controlled end-to-end validation for advertised migration contracts
- Documented known limitations
- A deterministic versioned ZIP and SHA-256 checksum
- A validated PowerShell Gallery module package

Snapshot, FullHistory, same-name replacement/recovery, and supported repository-settings restoration have controlled live end-to-end harnesses. The expanded repository-settings restoration contract is live-validated and is not pending validation.

## Release-readiness validation

`build/Test-ReleaseReadiness.ps1` is the single release-metadata validation boundary. Before a stable tag is created, run it with the intended tag and `-RequireEmptyUnreleased`.

The check validates the module manifest, stable semantic version, tag/version match, versioned changelog heading and date, `Unreleased` placement/content, and presence of release-critical build, workflow, installer, uninstaller, and publishing files. It reports readiness but never creates or publishes a tag.

Keeping `Unreleased` empty at the stable publication boundary avoids a misleading changelog state in which changes physically present in the tagged commit are described as if they were excluded from that release.

## Tagged-commit validation

Publication is tag-only. Stable tags must use exactly `vMAJOR.MINOR.PATCH` and must exactly match `v<ModuleVersion>`. Prerelease tags are rejected until prerelease publication is deliberately implemented.

The release workflow first invokes the reusable cross-platform quality gate against the exact release commit. Validation jobs run with read-only repository permissions and check out `${{ github.sha }}` rather than mutable branch state.

Only after the Windows, Ubuntu, and macOS quality-gate jobs succeed can the publication job run. That job checks out the same SHA, runs the release-readiness validator with the exact tag, rebuilds the deterministic GitHub release artifact, builds and validates the clean PowerShell Gallery package, checks for duplicate versions, and then publishes.

## PowerShell Gallery publication

Stable releases publish `CopyGitHubRepo` to PSGallery with `Publish-PSResource`. The clean package is staged from `src/CopyGitHubRepo` into `dist/PSGallery/CopyGitHubRepo`; repository tests, build tooling, documentation, and workflow files are not part of the Gallery package.

Before publication, the workflow uses an exact-version `Find-PSResource` lookup. If that Gallery version already exists, publication fails. If the exact package/version is not found, publication may proceed; unexpected Gallery lookup errors fail closed. The workflow never increments a version automatically and never attempts to overwrite an existing Gallery package.

The production Gallery API key is stored in the protected `powershell-gallery` GitHub Actions environment as `PSGALLERY_API_KEY` and is referenced only by the publication step. See [Publishing to PowerShell Gallery](publishing.md) for maintainer setup, key rotation, manual fallback, signing policy, and partial-failure handling.

## Stable release immutability

Stable release assets are immutable in the normal publication workflow. Normal publication creates a GitHub release containing the versioned ZIP, SHA-256 file, and SPDX SBOM and publishes the corresponding module version to PSGallery. Both channels are treated as immutable from the project release perspective.

Before creating a release, the workflow checks whether that stable tag already has a GitHub release. If it does, publication fails. The workflow does not use `gh release upload`, does not use `--clobber`, and does not replace existing stable assets. A correction uses a new version and tag unless an explicitly separate repair process is deliberately established.

Creating the release tag remains the deliberate stable-publication boundary. No release is published merely by merging to `main` or opening a pull request.

## Prereleases

Prerelease Gallery publication is not enabled initially. A tag containing prerelease metadata is rejected before mutation. Future prerelease support must define matching tag, manifest, package, Gallery lookup, and installation semantics rather than inferring them from a stable workflow.

## Signing

Authenticode signing is optional and was not a `v0.1.0` blocker. The v0.1.0 release uses GitHub artifact attestations plus checksum verification for release provenance and integrity. If Authenticode signing is added later, certificate and private-key handling will be designed separately as a protected release capability.

## Installer trust

The packaged installer is validated by the cross-platform quality gate using an isolated module root, including overwrite refusal and explicit forced replacement.

The convenience `install-release.ps1` bootstrap installs the latest stable GitHub release by default or an exact stable release when `-Version X.Y.Z` is supplied. It downloads the selected release ZIP and checksum, verifies SHA-256 and GitHub artifact provenance before extraction, and then invokes the packaged installer. When that bootstrap is fetched from mutable `main`, the bootstrap itself is part of the trust boundary.

The separate `install-prerelease.ps1` bootstrap is intended for development and release-candidate testing of unreleased `main` content. It resolves `main` to an exact Git commit SHA and downloads the source archive for that commit before invoking the same repository `install.ps1`. Because that unreleased source build does not have its own immutable stable release artifact and matching checksum, the prerelease path does not provide the stable release artifact contract.

The documented pinned installation path avoids executing `main` by downloading a specific stable release ZIP and checksum directly. A matching SHA-256 proves that the ZIP matches the compared checksum; GitHub artifact attestation additionally binds the artifact digest to the expected repository/workflow/source identity. See `docs/security/installation-security.md` for the complete trust model.
