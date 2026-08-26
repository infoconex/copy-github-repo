#requires -Version 7.4

[CmdletBinding()]
param(
    [ValidatePattern('^v(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)$')]
    [string] $Tag,

    [switch] $RequireEmptyUnreleased
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
$changelogPath = Join-Path $repositoryRoot 'CHANGELOG.md'
$publishingPath = Join-Path $repositoryRoot 'docs/release/publishing.md'
$releaseWorkflowPath = Join-Path $repositoryRoot '.github/workflows/publish-release.yml'
$galleryPackageBuilderPath = Join-Path $repositoryRoot 'build/New-PowerShellGalleryPackage.ps1'
$galleryReleaseNotesPath = Join-Path $repositoryRoot 'build/Set-PowerShellGalleryReleaseNotes.ps1'
$releaseArtifactBuilderPath = Join-Path $repositoryRoot 'build/New-ReleaseArtifact.ps1'
$installerPath = Join-Path $repositoryRoot 'install.ps1'
$uninstallerPath = Join-Path $repositoryRoot 'uninstall.ps1'

$requiredPaths = @(
    $manifestPath
    $changelogPath
    $publishingPath
    $releaseWorkflowPath
    $galleryPackageBuilderPath
    $galleryReleaseNotesPath
    $releaseArtifactBuilderPath
    $installerPath
    $uninstallerPath
)

foreach ($requiredPath in $requiredPaths) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Release readiness validation requires '$requiredPath'."
    }
}

$manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
$version = [string] $manifest.Version
if ($version -notmatch '^(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)$') {
    throw "Module version '$version' is not a supported stable semantic version."
}

$expectedTag = "v$version"
if (-not [string]::IsNullOrWhiteSpace($Tag) -and $Tag -cne $expectedTag) {
    throw "Release tag '$Tag' does not match module version '$version'. Expected '$expectedTag'."
}

$changelog = Get-Content -LiteralPath $changelogPath -Raw
$escapedVersion = [regex]::Escape($version)
$releaseHeadingPattern = "(?m)^## \[$escapedVersion\] - (?<ReleaseDate>\d{4}-\d{2}-\d{2})\r?$"
$releaseHeading = [regex]::Match($changelog, $releaseHeadingPattern)
if (-not $releaseHeading.Success) {
    throw "CHANGELOG.md must contain a dated release heading for version '$version' in the form '## [$version] - YYYY-MM-DD'."
}

$releaseDateText = $releaseHeading.Groups['ReleaseDate'].Value
$releaseDate = [datetime]::MinValue
if (-not [datetime]::TryParseExact(
        $releaseDateText,
        'yyyy-MM-dd',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref] $releaseDate
    )) {
    throw "CHANGELOG.md release date '$releaseDateText' is not a valid calendar date."
}

if ($releaseDate.Date -gt [datetime]::UtcNow.Date) {
    throw "CHANGELOG.md release date '$releaseDateText' is in the future."
}

$unreleasedHeading = [regex]::Match($changelog, '(?m)^## \[Unreleased\]\r?$')
if (-not $unreleasedHeading.Success) {
    throw 'CHANGELOG.md must contain an Unreleased section before versioned releases.'
}
if ($unreleasedHeading.Index -gt $releaseHeading.Index) {
    throw 'CHANGELOG.md must place the Unreleased section before the current versioned release section.'
}

if ($RequireEmptyUnreleased) {
    $unreleasedBodyStart = $unreleasedHeading.Index + $unreleasedHeading.Length
    $unreleasedBodyLength = $releaseHeading.Index - $unreleasedBodyStart
    $unreleasedBody = $changelog.Substring($unreleasedBodyStart, $unreleasedBodyLength).Trim()
    $emptyUnreleasedSentinel = 'No unreleased product changes.'
    $hasUnreleasedEntries = -not [string]::IsNullOrWhiteSpace($unreleasedBody) -and
        $unreleasedBody -cne $emptyUnreleasedSentinel

    if ($hasUnreleasedEntries) {
        throw "CHANGELOG.md contains Unreleased entries that would ship in '$expectedTag'. Move those entries into the '$version' release section before tagging."
    }
}

[pscustomobject] @{
    PSTypeName = 'CopyGitHubRepo.ReleaseReadiness'
    Version = $version
    ExpectedTag = $expectedTag
    ReleaseDate = $releaseDateText
    ManifestPath = $manifestPath
    ChangelogPath = $changelogPath
    IsReady = $true
}
