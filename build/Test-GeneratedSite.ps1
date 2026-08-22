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

foreach ($htmlFile in $htmlFiles) {
    $html = Get-Content -LiteralPath $htmlFile.FullName -Raw
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
            $relativeSource = [System.IO.Path]::GetRelativePath($siteRoot, $htmlFile.FullName)
            $failures.Add("$relativeSource -> $reference")
        }
    }
}

if ($failures.Count -gt 0) {
    $details = $failures | Sort-Object -Unique | ForEach-Object { " - $_" }
    throw "Generated site contains $($failures.Count) unresolved internal reference(s):`n$($details -join "`n")"
}

Write-Output "Validated $($htmlFiles.Count) generated HTML page(s); all internal page and asset references resolve."
