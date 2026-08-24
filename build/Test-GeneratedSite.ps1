#requires -Version 7.4

[CmdletBinding()]
param(
    [string]$SitePath = (Join-Path (Split-Path -Parent $PSScriptRoot) '_site'),
    [string]$BaseUrlPath = '/copy-github-repo'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$siteRoot = [System.IO.Path]::GetFullPath($SitePath)
if (-not (Test-Path -LiteralPath $siteRoot -PathType Container)) {
    throw "Generated site directory was not found: $siteRoot"
}

$basePath = '/' + $BaseUrlPath.Trim('/')
$referencePattern = '(?i)(?:href|src)\s*=\s*["''](?<value>[^"'']+)["'']'
$failures = [System.Collections.Generic.List[string]]::new()
$htmlFiles = @(Get-ChildItem -LiteralPath $siteRoot -Filter '*.html' -File -Recurse)

if ($htmlFiles.Count -eq 0) {
    throw "No generated HTML files were found beneath $siteRoot"
}

function Resolve-GeneratedReference {
    param(
        [Parameter(Mandatory)]
        [string]$Reference,
        [Parameter(Mandatory)]
        [string]$SourceDirectory
    )

    $candidate = $Reference.Trim()
    if ([string]::IsNullOrWhiteSpace($candidate) -or $candidate.StartsWith('#')) {
        return $null
    }

    if ($candidate -match '^(?i)(?:https?:|mailto:|tel:|javascript:|data:|//)') {
        return $null
    }

    $candidate = ($candidate -split '[?#]', 2)[0]
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        return $null
    }

    $candidate = [Uri]::UnescapeDataString($candidate)

    if ($candidate -eq $basePath -or $candidate -eq "$basePath/") {
        return Join-Path $siteRoot 'index.html'
    }

    if ($candidate.StartsWith("$basePath/", [StringComparison]::Ordinal)) {
        $relativePath = $candidate.Substring($basePath.Length).TrimStart('/')
        $resolved = Join-Path $siteRoot $relativePath
    }
    elseif ($candidate.StartsWith('/')) {
        $resolved = Join-Path $siteRoot $candidate.TrimStart('/')
    }
    else {
        $resolved = Join-Path $SourceDirectory $candidate
    }

    $resolved = [System.IO.Path]::GetFullPath($resolved)
    if (-not $resolved.StartsWith($siteRoot, [StringComparison]::Ordinal)) {
        return $null
    }

    return $resolved
}

function Add-GeneratedSiteFailure {
    param(
        [Parameter(Mandatory)]
        [string]$Source,
        [Parameter(Mandatory)]
        [string]$Message
    )

    $failures.Add("$Source -> $Message")
}

foreach ($htmlFile in $htmlFiles) {
    $html = Get-Content -LiteralPath $htmlFile.FullName -Raw
    $relativeSource = [System.IO.Path]::GetRelativePath($siteRoot, $htmlFile.FullName)

    foreach ($match in [regex]::Matches($html, $referencePattern)) {
        $reference = $match.Groups['value'].Value
        $target = Resolve-GeneratedReference -Reference $reference -SourceDirectory $htmlFile.DirectoryName
        if ($null -eq $target) {
            continue
        }

        $exists = Test-Path -LiteralPath $target
        if (-not $exists -and [string]::IsNullOrEmpty([System.IO.Path]::GetExtension($target))) {
            $htmlTarget = "$target.html"
            $indexTarget = Join-Path $target 'index.html'
            $exists = (Test-Path -LiteralPath $htmlTarget -PathType Leaf) -or (Test-Path -LiteralPath $indexTarget -PathType Leaf)
        }
        elseif ($exists -and (Test-Path -LiteralPath $target -PathType Container)) {
            $exists = Test-Path -LiteralPath (Join-Path $target 'index.html') -PathType Leaf
        }

        if (-not $exists) {
            Add-GeneratedSiteFailure -Source $relativeSource -Message "unresolved reference: $reference"
        }
    }

    $idMatches = [regex]::Matches($html, '(?i)\bid\s*=\s*["''](?<id>[^"'']+)["'']')
    $ids = @($idMatches | ForEach-Object { $_.Groups['id'].Value })
    foreach ($duplicateId in @($ids | Group-Object | Where-Object Count -gt 1 | Select-Object -ExpandProperty Name)) {
        Add-GeneratedSiteFailure -Source $relativeSource -Message "duplicate id: $duplicateId"
    }

    $idSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($id in $ids) {
        [void]$idSet.Add($id)
    }

    foreach ($match in [regex]::Matches($html, '(?is)<[^>]+\baria-controls\s*=\s*["''](?<targets>[^"'']+)["''][^>]*>')) {
        foreach ($targetId in @($match.Groups['targets'].Value -split '\s+' | Where-Object { $_ })) {
            if (-not $idSet.Contains($targetId)) {
                Add-GeneratedSiteFailure -Source $relativeSource -Message "aria-controls references missing id: $targetId"
            }
        }
    }

    foreach ($imageMatch in [regex]::Matches($html, '(?is)<img\b[^>]*>')) {
        if ($imageMatch.Value -notmatch '(?i)\balt\s*=') {
            Add-GeneratedSiteFailure -Source $relativeSource -Message 'image missing alt attribute'
        }
    }

    $headingMatches = @([regex]::Matches($html, '(?is)<h(?<level>[1-6])\b[^>]*>'))
    $h1Count = @($headingMatches | Where-Object { $_.Groups['level'].Value -eq '1' }).Count
    if ($h1Count -ne 1) {
        Add-GeneratedSiteFailure -Source $relativeSource -Message "expected exactly one h1, found $h1Count"
    }

    $previousHeadingLevel = 0
    foreach ($headingMatch in $headingMatches) {
        $headingLevel = [int]$headingMatch.Groups['level'].Value
        if ($previousHeadingLevel -gt 0 -and $headingLevel -gt ($previousHeadingLevel + 1)) {
            Add-GeneratedSiteFailure -Source $relativeSource -Message "heading hierarchy skips from h$previousHeadingLevel to h$headingLevel"
        }
        $previousHeadingLevel = $headingLevel
    }

    foreach ($inputMatch in [regex]::Matches($html, '(?is)<input\b[^>]*\baria-expanded\s*=\s*["''][^"'']+["''][^>]*>')) {
        if ($inputMatch.Value -notmatch '(?i)\brole\s*=\s*["'']combobox["'']') {
            Add-GeneratedSiteFailure -Source $relativeSource -Message 'input uses aria-expanded without role="combobox"'
        }
    }
}

if ($failures.Count -gt 0) {
    $details = $failures | Sort-Object -Unique | ForEach-Object { " - $_" }
    throw "Generated site contains $($failures.Count) integrity/accessibility issue(s):`n$($details -join "`n")"
}

Write-Output "Validated $($htmlFiles.Count) generated HTML page(s); internal references and deterministic accessibility semantics passed."
