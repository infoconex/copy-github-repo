#requires -Version 7.4

<#
.SYNOPSIS
Checks release-sensitive documentation for stale literal CopyGitHubRepo versions.

.DESCRIPTION
Reads the intended version from the module manifest (not the published Gallery
or GitHub Release). Verifies executable stable installation examples and related
release operator guidance. Historical releases, dependency versions, third-party
standards, and test fixture versions are intentionally not reinterpreted as the
current CopyGitHubRepo release. Does not access the network or modify files.

.PARAMETER RepositoryRoot
Repository root; defaults to the parent of this build directory. An alternate
root allows isolated negative contract tests without changing repository files.
#>
[CmdletBinding()]
param(
    [string] $RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath $RepositoryRoot -ErrorAction Stop).ProviderPath
$manifestRelative = 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
$installationRelative = 'docs/security/installation-security.md'
$generalGuides = @('README.md', 'docs/user/user-guide.md')
$publishingRelative = 'docs/release/publishing.md'
$workflowRelative = '.github/workflows/publish-release.yml'
$requiredFiles = @($manifestRelative, $installationRelative, $publishingRelative, $workflowRelative) + $generalGuides

foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        throw "Documentation version audit requires '$relativePath'."
    }
}

$manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $root $manifestRelative)
$version = [string] $manifest.ModuleVersion
if ($version -notmatch '^(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)$') {
    throw "Documentation version audit requires a stable manifest ModuleVersion; got '$version'."
}

$violations = [System.Collections.Generic.List[string]]::new()
$installationLines = @(Get-Content -LiteralPath (Join-Path $root $installationRelative))
$inPowerShell = $false
$galleryPins = 0
$hostedPins = 0
$pinnedZipVersions = 0
$pinnedSection = $false

for ($i = 0; $i -lt $installationLines.Count; $i++) {
    $line = [string] $installationLines[$i]
    if ($line -match '^## Pinned release installation\s*$') {
        $pinnedSection = $true
    }
    elseif ($line -match '^## Independent signing decision\s*$') {
        $pinnedSection = $false
    }

    if ($line -match '^\s*\x60{3}(?:powershell|pwsh)\s*$') {
        $inPowerShell = $true
        continue
    }
    if ($line -match '^\s*\x60{3}\s*$') {
        $inPowerShell = $false
        continue
    }
    if (-not $inPowerShell) {
        continue
    }

    $observed = $null
    $kind = $null
    if ($line -match 'Install-PSResource\s+CopyGitHubRepo\s+-Version\s+(?<Version>\d+\.\d+\.\d+)') {
        $galleryPins++
        $observed = $Matches.Version
        $kind = 'Gallery install'
    }
    elseif ($line -match 'install-release\.ps1.*-Version\s+(?<Version>\d+\.\d+\.\d+)') {
        $hostedPins++
        $observed = $Matches.Version
        $kind = 'hosted stable bootstrap'
    }
    elseif ($pinnedSection -and $line -match '^\s*\$version\s*=\s*''(?<Version>\d+\.\d+\.\d+)''') {
        $pinnedZipVersions++
        $observed = $Matches.Version
        $kind = 'pinned ZIP procedure'
    }

    if ($null -ne $observed -and $observed -cne $version) {
        $violations.Add(('{0}:{1} stale {2} version {3}; manifest requires {4}' -f $installationRelative, ($i + 1), $kind, $observed, $version))
    }
}

if ($galleryPins -ne 1) {
    $violations.Add("$installationRelative expected one explicit candidate-version Gallery example; found $galleryPins.")
}
if ($hostedPins -ne 2) {
    $violations.Add("$installationRelative expected stable hosted examples with and without -Force; found $hostedPins.")
}
if ($pinnedZipVersions -ne 1) {
    $violations.Add("$installationRelative expected one pinned ZIP version assignment; found $pinnedZipVersions.")
}

foreach ($relativePath in $generalGuides) {
    $lines = @(Get-Content -LiteralPath (Join-Path $root $relativePath))
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match 'Install-PSResource\s+CopyGitHubRepo\s+-Version\s+\d+\.\d+\.\d+') {
            $violations.Add(('{0}:{1} ordinary installation guidance must be version-neutral; link to the pinned-install guide.' -f $relativePath, ($i + 1)))
        }
    }
}

$workflowLines = @(Get-Content -LiteralPath (Join-Path $root $workflowRelative))
$genericTagHelp = 0
for ($i = 0; $i -lt $workflowLines.Count; $i++) {
    $line = [string] $workflowLines[$i]
    if ($line -match '^\s*description:\s*Stable release tag to create, for example ') {
        $genericTagHelp++
        if ($line -notmatch 'vX\.Y\.Z\s*$' -or $line -match '\bv\d+\.\d+\.\d+\b') {
            $violations.Add(('{0}:{1} release-dispatch tag help must use vX.Y.Z, not a fixed version.' -f $workflowRelative, ($i + 1)))
        }
    }
}
if ($genericTagHelp -ne 1) {
    $violations.Add("$workflowRelative expected exactly one generic stable-release tag input description; found $genericTagHelp.")
}

$publishingLines = @(Get-Content -LiteralPath (Join-Path $root $publishingRelative))
for ($i = 0; $i -lt $publishingLines.Count; $i++) {
    if ($publishingLines[$i] -match '(?:Test-ReleaseReadiness\.ps1\s+-Tag\s+v\d+\.\d+\.\d+|Find-PSResource\s+CopyGitHubRepo\s+-Version\s+\d+\.\d+\.\d+)') {
        $violations.Add(('{0}:{1} publication commands must derive the candidate version from ModuleVersion.' -f $publishingRelative, ($i + 1)))
    }
}

if ($violations.Count -gt 0) {
    throw ("Documentation version audit failed for intended version '$version':" +
        [Environment]::NewLine + ($violations -join [Environment]::NewLine))
}

[pscustomobject] @{
    PSTypeName = 'CopyGitHubRepo.DocumentationVersionAudit'
    IntendedVersion = $version
    CheckedFiles = $requiredFiles.Count
    GalleryExamples = $galleryPins
    HostedStableExamples = $hostedPins
    PinnedZipExamples = $pinnedZipVersions
    IsValid = $true
}
