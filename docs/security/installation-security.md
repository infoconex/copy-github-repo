# Installation security

Copy GitHub Repository has a primary stable PowerShell Gallery installation path plus repository-hosted stable, pinned-artifact, and prerelease alternatives with different trust properties.

> [!IMPORTANT]
> Version `v0.1.0` is the initial stable release. Use PowerShell Gallery for normal released installations. Use the repository-hosted or pinned procedures below only when their additional release-artifact verification properties are required, and use `install-prerelease.ps1` only when you intentionally want unreleased `main` content.

## PowerShell Gallery installation

PowerShell Gallery is the primary public package channel and the recommended normal installation path for stable releases:

```powershell
Install-PSResource CopyGitHubRepo
Import-Module CopyGitHubRepo
```

`Install-PSResource` installs the latest stable version available from PSGallery by default. To deliberately install the initial stable release:

```powershell
Install-PSResource CopyGitHubRepo -Version 0.1.0
```

For environments using the older PowerShellGet command surface, the compatible alternative is:

```powershell
Install-Module CopyGitHubRepo -Scope CurrentUser
```

A Gallery installation should normally be updated and removed through the same package-management channel:

```powershell
Update-PSResource CopyGitHubRepo
Uninstall-PSResource CopyGitHubRepo
```

PowerShell Gallery package installation and the GitHub Release artifact-verification procedures below are distinct trust paths. A normal `Install-PSResource` operation retrieves the published PSGallery package; it does not independently download the project's GitHub Release `.sha256` sidecar or run `gh attestation verify` against the GitHub Release ZIP. Organizations that require the project's checksum-and-GitHub-provenance verification contract should use the repository-hosted stable bootstrap or, for the strongest project-documented release-artifact path, the pinned release procedure below.

## Prerelease bootstrap

For development and release-candidate testing of unreleased `main` content, use:

```powershell
irm https://raw.githubusercontent.com/infoconex/copy-github-repo/main/install-prerelease.ps1 | iex
```

If the same module version is already installed and intentional replacement is required, supply `-Force`:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/infoconex/copy-github-repo/main/install-prerelease.ps1))) -Force
```

The prerelease bootstrap resolves `main` through the GitHub API, validates the returned 40-character commit SHA, then downloads the repository source archive for that exact commit. It invokes the repository's existing `install.ps1` and reports the resolved commit before installation.

This avoids downloading a moving `main.zip` after resolution, but the bootstrap itself is fetched from mutable repository content. An unreleased source build also has no published release ZIP, matching `.sha256` asset, or stable-release provenance attestation. It is intended for deliberate development and release-candidate testing, not as the long-term stable installation path.

## Repository-hosted stable bootstrap

The repository-hosted stable convenience bootstrap is an alternative to the normal PowerShell Gallery install when the GitHub Release ZIP checksum and provenance verification are desired:

```powershell
irm https://raw.githubusercontent.com/infoconex/copy-github-repo/main/install-release.ps1 | iex
```

Without parameters, the bootstrap resolves the latest stable GitHub release. A specific stable version can be requested from the same bootstrap:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/infoconex/copy-github-repo/main/install-release.ps1))) -Version 0.1.0
```

If the selected version is already installed and intentional replacement is required, supply `-Force`:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/infoconex/copy-github-repo/main/install-release.ps1))) -Version 0.1.0 -Force
```

The stable bootstrap requires GitHub CLI (`gh`) because it performs cryptographic provenance verification before extraction. It:

1. resolves the stable release and exact tag commit;
2. downloads the release ZIP and matching `.sha256` asset;
3. verifies the ZIP's SHA-256 checksum;
4. runs `gh attestation verify` against the ZIP, requiring:
   - repository `infoconex/copy-github-repo`;
   - signer workflow `infoconex/copy-github-repo/.github/workflows/publish-release.yml`; and
   - the exact source commit resolved from the selected release tag;
5. fails closed if GitHub CLI is unavailable, no matching provenance attestation exists, or cryptographic verification fails; and
6. only after both checksum and provenance verification succeed, extracts the ZIP and invokes packaged `install.ps1`.

`-Force` is forwarded only to the packaged installer and does not weaken checksum or provenance verification.

The release workflow creates the provenance attestation with GitHub Actions OIDC and GitHub artifact attestations. For this public repository, GitHub's attestation verification uses the Sigstore trust infrastructure and validates the signed artifact digest and workflow identity. The repository does not store a private signing key or certificate for this mechanism.

### What this improves

The provenance check is independent of the `.sha256` file. An attacker who could replace a release ZIP and its adjacent checksum would still need a valid attestation for that altered artifact from the required repository/workflow/source identity. A missing or invalid attestation stops installation before extraction.

The SHA-256 asset remains useful defense in depth for corruption detection and simple reproducibility checks.

### What this does not improve

The one-line convenience command still downloads `install-release.ps1` from mutable `main` and executes that bootstrap before any artifact verification code can protect it. Compromise of the repository/account content serving the bootstrap could alter the bootstrap itself.

Therefore the convenience bootstrap remains inside the trust boundary even though the release artifact it installs is now independently provenance-verified. Environments that need to avoid executing mutable branch content should use the pinned procedure below.

## Pinned release installation

For a higher-assurance stable install using the project's GitHub Release evidence, avoid executing mutable branch content. Pin a stable release and download its versioned artifact/checksum directly, then verify both checksum and GitHub artifact attestation before extraction.

The initial stable version is `v0.1.0`; the following pattern installs that release:

```powershell
$version = '0.1.0'
$repository = 'infoconex/copy-github-repo'
$tag = "v$version"
$releaseBase = "https://github.com/$repository/releases/download/$tag"
$artifact = "CopyGitHubRepo-$version.zip"
$checksum = "$artifact.sha256"

Invoke-WebRequest "$releaseBase/$artifact" -OutFile $artifact
Invoke-WebRequest "$releaseBase/$checksum" -OutFile $checksum

$checksumText = (Get-Content -LiteralPath $checksum -Raw).Trim()
if ($checksumText -notmatch '^(?<Hash>[a-fA-F0-9]{64})\s+\S+$') {
    throw 'Release checksum file is not in the expected SHA-256 format.'
}

$expectedHash = $Matches.Hash.ToLowerInvariant()
$actualHash = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $expectedHash) {
    throw 'Release artifact checksum validation failed.'
}

$releaseCommit = (irm "https://api.github.com/repos/$repository/commits/$tag").sha
if ($releaseCommit -notmatch '^[a-fA-F0-9]{40}$') {
    throw 'Unable to resolve the release tag to an exact commit.'
}

gh attestation verify $artifact `
    --repo $repository `
    --signer-workflow "$repository/.github/workflows/publish-release.yml" `
    --source-digest $releaseCommit
if ($LASTEXITCODE -ne 0) {
    throw 'Release artifact provenance verification failed.'
}

$extractPath = "./CopyGitHubRepo-$version"
Expand-Archive -LiteralPath $artifact -DestinationPath $extractPath
& "$extractPath/install.ps1"
Import-Module CopyGitHubRepo -RequiredVersion $version
```

This path avoids executing `install-release.ps1`, `install-prerelease.ps1`, or any other file from mutable `main`. It requires the selected artifact to match both its checksum and a cryptographically verified GitHub provenance attestation bound to the release workflow and exact tag commit.

Stable release publication in this repository is intentionally immutable in the normal release workflow: an existing stable release causes publication to fail rather than replacing assets. The release workflow also requires the exact release commit to pass the reusable Windows, Ubuntu, and macOS quality gate before publication and generates provenance/SBOM attestations before publishing release assets.

## Independent signing decision

For v0.1.0, the project uses GitHub artifact attestations as the independent release-authenticity mechanism rather than purchasing and managing an Authenticode code-signing certificate.

This choice avoids introducing a long-lived private signing key or certificate secret into project operations while still providing cryptographically verifiable artifact provenance. Verification is bound to the expected repository, release workflow, exact source commit, and downloaded artifact digest. GitHub CLI performs certificate, signature, timestamp/transparency, and trusted-root verification.

Authenticode signing may still be considered later for environments that specifically require operating-system publisher signatures. It is not required for the v0.1.0 trust contract because the artifact attestation is the selected authenticity control.

## Uninstall behavior

For a module installed from PowerShell Gallery, prefer the package manager that installed it:

```powershell
Uninstall-PSResource CopyGitHubRepo
```

`uninstall.ps1` is the supported removal entry point for installations created by this project's custom repository-hosted installer and for explicit local cleanup. It is interactive by default when neither `-Version` nor `-AllVersions` is supplied.

The convenient one-line form is:

```powershell
irm https://raw.githubusercontent.com/infoconex/copy-github-repo/main/uninstall.ps1 | iex
```

The script resolves the same default current-user module destination used by `install.ps1`, discovers validated `CopyGitHubRepo/<version>` installations, and shows exactly what it found. With one installed version it shows the version/path and asks for confirmation. With multiple versions it lets you remove one version, remove all validated versions, or cancel. Final destructive confirmation defaults to No, and cancellation is a successful no-change outcome.

For deterministic local execution, target a specific version:

```powershell
./uninstall.ps1 -Version 0.1.0
```

To remove every validated installed version under the resolved module root:

```powershell
./uninstall.ps1 -AllVersions
```

A custom install root is removed by supplying the same destination root used during installation:

```powershell
./uninstall.ps1 -Version 0.1.0 -DestinationRoot D:\PowerShell\Modules
```

Preview the exact removal with standard PowerShell `ShouldProcess` behavior:

```powershell
./uninstall.ps1 -Version 0.1.0 -WhatIf
```

For deliberate non-interactive automation, explicitly target a version or all versions and suppress PowerShell confirmation:

```powershell
./uninstall.ps1 -Version 0.1.0 -Confirm:$false
```

`-Version` and `-AllVersions` are mutually exclusive. Explicit targeting bypasses interactive selection, but it never bypasses module-identity, path-containment, or reparse-point checks. The script validates the expected manifest GUID, root module, and version before recursive deletion, unloads a matching loaded module when practical, and never removes sibling modules. If a requested version is already absent, it reports a no-change result rather than treating that as an exceptional failure.

Running a local or packaged `uninstall.ps1` does not require network access. The one-line uninstall bootstrap above is different: because it fetches and immediately executes `uninstall.ps1` from mutable `main`, it is inside the same trust boundary as the convenience install bootstraps. For higher-assurance removal, use the `uninstall.ps1` packaged in the versioned release artifact or another locally obtained trusted copy instead of executing mutable branch content.

Removing installed module files does not delete, rename, or otherwise change any GitHub repository, and it does not remove migration recovery artifacts created elsewhere.

## What SHA-256 and provenance prove

A matching SHA-256 value proves that the downloaded ZIP has the same bytes as the value represented by the checksum you compared it with. It is useful for integrity verification and detecting corruption or mismatched assets.

A checksum downloaded from the same release does **not**, by itself, prove who produced the artifact or protect against an attacker who can replace both the artifact and its checksum.

The GitHub provenance attestation adds a cryptographically verified identity statement for the artifact. The stable repository-hosted installer requires the artifact to verify as produced by this repository's release workflow from the exact selected release commit. This is stronger than trusting the adjacent checksum alone, but it is still provenance—not a claim that the code is vulnerability-free or that a mutable bootstrap cannot itself be compromised.

## Choosing a path

Use **PowerShell Gallery** with `Install-PSResource CopyGitHubRepo` for normal stable installation, `Update-PSResource CopyGitHubRepo` for normal updates, and `Uninstall-PSResource CopyGitHubRepo` for removal of Gallery-managed installations.

Use `install-release.ps1` when you specifically want the repository-hosted stable convenience path and its checksum/provenance verification of the GitHub Release ZIP. Remember that the convenience bootstrap itself is fetched from mutable `main` and remains inside the trust boundary.

Use the pinned release procedure when you want to avoid executing mutable branch content and explicitly verify the selected GitHub Release artifact against both its checksum and cryptographic provenance before extraction.

Use `install-prerelease.ps1` only when you intentionally want the current unreleased `main` build. Add `-Force` only when intentionally replacing the same installed version.