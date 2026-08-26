#requires -Version 7.4

<#
.SYNOPSIS
Injects version-specific changelog text into a staged PowerShell Gallery manifest.

.DESCRIPTION
Reads the staged module version, extracts the matching dated section from CHANGELOG.md,
and replaces the staged manifest's PSData ReleaseNotes value with that section. The
source manifest remains stable in the repository while every published Gallery package
carries the release notes for its own immutable version.

.PARAMETER ManifestPath
Path to the staged CopyGitHubRepo.psd1 manifest.

.PARAMETER ChangelogPath
Path to CHANGELOG.md.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ManifestPath,

    [Parameter(Mandatory)]
    [string] $ChangelogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$manifestData = Import-PowerShellDataFile -LiteralPath $ManifestPath
$version = [string] $manifestData.ModuleVersion
if ([string]::IsNullOrWhiteSpace($version)) {
    throw "Staged manifest '$ManifestPath' does not define ModuleVersion."
}

$changelog = Get-Content -LiteralPath $ChangelogPath -Raw
$escapedVersion = [regex]::Escape($version)
$releasePattern = "(?ms)^## \[$escapedVersion\] - \d{4}-\d{2}-\d{2}\r?\n(?<Body>.*?)(?=^## \[|\z)"
$releaseMatch = [regex]::Match($changelog, $releasePattern)
if (-not $releaseMatch.Success) {
    throw "CHANGELOG.md does not contain a dated release section for version '$version'."
}

$releaseNotes = $releaseMatch.Groups['Body'].Value.Trim()
if ([string]::IsNullOrWhiteSpace($releaseNotes)) {
    throw "CHANGELOG.md release section for version '$version' does not contain release notes."
}

# Canonicalize line endings before writing the PSD1 value. Git may check out Markdown
# with CRLF on Windows, while the encoded PowerShell data-file string round-trips with
# LF line breaks. Normalizing here keeps staged release notes identical on every OS.
$releaseNotes = $releaseNotes.Replace("`r`n", "`n").Replace("`r", "`n")

# Store the notes in a double-quoted data-file string. Escape expandable-string
# characters and encode line breaks so arbitrary Markdown remains valid PSD1 data.
$escapedReleaseNotes = $releaseNotes.Replace('`', '``').Replace('$', '`$').Replace('"', '`"')
$escapedReleaseNotes = $escapedReleaseNotes.Replace("`n", '`n')

$manifestText = Get-Content -LiteralPath $ManifestPath -Raw
$releaseNotesPattern = '(?m)^(?<Indent>\s*)ReleaseNotes\s*=\s*.*$'
$replacementCount = [regex]::Matches($manifestText, $releaseNotesPattern).Count
if ($replacementCount -ne 1) {
    throw "Staged manifest '$ManifestPath' must contain exactly one ReleaseNotes assignment; found $replacementCount."
}

$manifestText = [regex]::Replace(
    $manifestText,
    $releaseNotesPattern,
    {
        param($match)
        return "$($match.Groups['Indent'].Value)ReleaseNotes = `"$escapedReleaseNotes`""
    }
)

Set-Content -LiteralPath $ManifestPath -Value $manifestText -Encoding utf8NoBOM

$updatedManifest = Import-PowerShellDataFile -LiteralPath $ManifestPath
if ([string] $updatedManifest.PrivateData.PSData.ReleaseNotes -cne $releaseNotes) {
    throw "Staged manifest release notes for version '$version' did not round-trip exactly."
}

[pscustomobject] @{
    PSTypeName = 'CopyGitHubRepo.PowerShellGalleryReleaseNotes'
    Version = $version
    ManifestPath = $ManifestPath
    ChangelogPath = $ChangelogPath
    ReleaseNotes = $releaseNotes
}
