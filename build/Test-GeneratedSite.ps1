#requires -Version 7.4

[CmdletBinding()]
param(
    [string]$SitePath = (Join-Path (Split-Path -Parent $PSScriptRoot) '_site'),
    [string]$BaseUrlPath = '/copy-github-repo',
    [string]$SiteUrl = 'https://infoconex.github.io'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$siteRoot = [System.IO.Path]::GetFullPath($SitePath)
if (-not (Test-Path -LiteralPath $siteRoot -PathType Container)) {
    throw "Generated site directory was not found: $siteRoot"
}

$basePath = '/' + $BaseUrlPath.Trim('/')
$siteOrigin = $SiteUrl.TrimEnd('/')
$canonicalRoot = "$siteOrigin$basePath/"
$referencePattern = '(?i)(?:href|src)\s*=\s*["''](?<value>[^"'']+)["'']'
$failures = [System.Collections.Generic.List[string]]::new()
$htmlFiles = @(Get-ChildItem -LiteralPath $siteRoot -Filter '*.html' -File -Recurse)
$titleRecords = @()
$descriptionRecords = @()
$canonicalRecords = @()

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

function Get-HtmlAttributeValue {
    param(
        [Parameter(Mandatory)]
        [string]$Tag,
        [Parameter(Mandatory)]
        [string]$Name
    )

    $escapedName = [regex]::Escape($Name)
    $doubleQuotePattern = '(?is)\b{0}\s*=\s*"(?<value>[^"]*)"' -f $escapedName
    $singleQuotePattern = "(?is)\b{0}\s*=\s*'(?<value>[^']*)'" -f $escapedName

    $match = [regex]::Match($Tag, $doubleQuotePattern)
    if (-not $match.Success) {
        $match = [regex]::Match($Tag, $singleQuotePattern)
    }
    if (-not $match.Success) {
        return $null
    }

    return [System.Net.WebUtility]::HtmlDecode($match.Groups['value'].Value)
}

function Get-ExpectedCanonicalUrl {
    param(
        [Parameter(Mandatory)]
        [string]$RelativeSource
    )

    $relativeUrl = $RelativeSource -replace '\\', '/'
    if ($relativeUrl -eq 'index.html') {
        return $canonicalRoot
    }

    if ($relativeUrl.EndsWith('/index.html', [StringComparison]::Ordinal)) {
        $relativeUrl = $relativeUrl.Substring(0, $relativeUrl.Length - 'index.html'.Length)
    }

    return "$canonicalRoot$relativeUrl"
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

    $titleMatches = @([regex]::Matches($html, '(?is)<title\b[^>]*>(?<value>.*?)</title>'))
    if ($titleMatches.Count -ne 1) {
        Add-GeneratedSiteFailure -Source $relativeSource -Message "expected exactly one title element, found $($titleMatches.Count)"
    }
    else {
        $titleValue = [System.Net.WebUtility]::HtmlDecode(($titleMatches[0].Groups['value'].Value -replace '(?is)<[^>]+>', '').Trim())
        if ([string]::IsNullOrWhiteSpace($titleValue)) {
            Add-GeneratedSiteFailure -Source $relativeSource -Message 'title element is empty'
        }
        else {
            $titleRecords += [pscustomobject]@{ Source = $relativeSource; Value = $titleValue }
        }
    }

    $metaTags = @([regex]::Matches($html, '(?is)<meta\b[^>]*>') | ForEach-Object { $_.Value })
    $linkTags = @([regex]::Matches($html, '(?is)<link\b[^>]*>') | ForEach-Object { $_.Value })

    $descriptionTags = @($metaTags | Where-Object { (Get-HtmlAttributeValue -Tag $_ -Name 'name') -ieq 'description' })
    if ($descriptionTags.Count -ne 1) {
        Add-GeneratedSiteFailure -Source $relativeSource -Message "expected exactly one meta description, found $($descriptionTags.Count)"
    }
    else {
        $descriptionValue = (Get-HtmlAttributeValue -Tag $descriptionTags[0] -Name 'content').Trim()
        if ([string]::IsNullOrWhiteSpace($descriptionValue)) {
            Add-GeneratedSiteFailure -Source $relativeSource -Message 'meta description is empty'
        }
        else {
            $descriptionRecords += [pscustomobject]@{ Source = $relativeSource; Value = $descriptionValue }
        }
    }

    $canonicalTags = @($linkTags | Where-Object {
        $rel = Get-HtmlAttributeValue -Tag $_ -Name 'rel'
        $rel -and (@($rel -split '\s+') -icontains 'canonical')
    })
    $canonicalValue = $null
    if ($canonicalTags.Count -ne 1) {
        Add-GeneratedSiteFailure -Source $relativeSource -Message "expected exactly one canonical link, found $($canonicalTags.Count)"
    }
    else {
        $canonicalValue = (Get-HtmlAttributeValue -Tag $canonicalTags[0] -Name 'href').Trim()
        $expectedCanonical = Get-ExpectedCanonicalUrl -RelativeSource $relativeSource
        if ($canonicalValue -cne $expectedCanonical) {
            Add-GeneratedSiteFailure -Source $relativeSource -Message "canonical URL mismatch: expected $expectedCanonical but found $canonicalValue"
        }
        else {
            $canonicalRecords += [pscustomobject]@{ Source = $relativeSource; Value = $canonicalValue }
        }
    }

    foreach ($propertyName in @('og:title', 'og:description', 'og:url')) {
        $propertyTags = @($metaTags | Where-Object { (Get-HtmlAttributeValue -Tag $_ -Name 'property') -ieq $propertyName })
        if ($propertyTags.Count -ne 1) {
            Add-GeneratedSiteFailure -Source $relativeSource -Message "expected exactly one $propertyName meta element, found $($propertyTags.Count)"
            continue
        }

        $propertyValue = (Get-HtmlAttributeValue -Tag $propertyTags[0] -Name 'content').Trim()
        if ([string]::IsNullOrWhiteSpace($propertyValue)) {
            Add-GeneratedSiteFailure -Source $relativeSource -Message "$propertyName meta element is empty"
        }
        elseif ($propertyName -eq 'og:url' -and $canonicalValue -and $propertyValue -cne $canonicalValue) {
            Add-GeneratedSiteFailure -Source $relativeSource -Message "og:url does not match canonical URL: $propertyValue"
        }
    }

    $twitterCardTags = @($metaTags | Where-Object { (Get-HtmlAttributeValue -Tag $_ -Name 'name') -ieq 'twitter:card' })
    if ($twitterCardTags.Count -ne 1) {
        Add-GeneratedSiteFailure -Source $relativeSource -Message "expected exactly one twitter:card meta element, found $($twitterCardTags.Count)"
    }

    $robotsTags = @($metaTags | Where-Object { (Get-HtmlAttributeValue -Tag $_ -Name 'name') -ieq 'robots' })
    foreach ($robotsTag in $robotsTags) {
        $robotsContent = Get-HtmlAttributeValue -Tag $robotsTag -Name 'content'
        if ($robotsContent -match '(?i)(?:^|[,\s])noindex(?:$|[,\s])') {
            Add-GeneratedSiteFailure -Source $relativeSource -Message "page unexpectedly contains noindex robots directive: $robotsContent"
        }
    }

    $jsonLdMatches = @([regex]::Matches($html, '(?is)<script\b(?=[^>]*\btype\s*=\s*["'']application/ld\+json["''])[^>]*>(?<value>.*?)</script>'))
    if ($jsonLdMatches.Count -ne 1) {
        Add-GeneratedSiteFailure -Source $relativeSource -Message "expected exactly one JSON-LD block, found $($jsonLdMatches.Count)"
    }
    else {
        try {
            $jsonLd = $jsonLdMatches[0].Groups['value'].Value | ConvertFrom-Json -Depth 100
            if ($canonicalValue -and ([string]$jsonLd.url) -cne $canonicalValue) {
                Add-GeneratedSiteFailure -Source $relativeSource -Message "JSON-LD URL does not match canonical URL: $($jsonLd.url)"
            }
        }
        catch {
            Add-GeneratedSiteFailure -Source $relativeSource -Message "JSON-LD is not valid JSON: $($_.Exception.Message)"
        }
    }
}

foreach ($duplicateTitle in @($titleRecords | Group-Object Value | Where-Object Count -gt 1)) {
    $sources = @($duplicateTitle.Group.Source) -join ', '
    Add-GeneratedSiteFailure -Source 'SEO metadata' -Message "duplicate title '$($duplicateTitle.Name)' on: $sources"
}

foreach ($duplicateDescription in @($descriptionRecords | Group-Object Value | Where-Object Count -gt 1)) {
    $sources = @($duplicateDescription.Group.Source) -join ', '
    Add-GeneratedSiteFailure -Source 'SEO metadata' -Message "duplicate meta description on: $sources"
}

$sitemapPath = Join-Path $siteRoot 'sitemap.xml'
if (-not (Test-Path -LiteralPath $sitemapPath -PathType Leaf)) {
    Add-GeneratedSiteFailure -Source 'sitemap.xml' -Message 'sitemap was not generated'
}
else {
    $sitemapContent = Get-Content -LiteralPath $sitemapPath -Raw
    $sitemapUrls = @([regex]::Matches($sitemapContent, '(?is)<loc>\s*(?<value>[^<]+?)\s*</loc>') | ForEach-Object {
        [System.Net.WebUtility]::HtmlDecode($_.Groups['value'].Value.Trim())
    })

    $canonicalUrls = @($canonicalRecords.Value)
    foreach ($canonicalUrl in $canonicalUrls) {
        if ($sitemapUrls -cnotcontains $canonicalUrl) {
            Add-GeneratedSiteFailure -Source 'sitemap.xml' -Message "missing canonical page URL: $canonicalUrl"
        }
    }
    foreach ($sitemapUrl in $sitemapUrls) {
        if ($canonicalUrls -cnotcontains $sitemapUrl) {
            Add-GeneratedSiteFailure -Source 'sitemap.xml' -Message "contains URL without a generated HTML canonical: $sitemapUrl"
        }
    }
}

$robotsPath = Join-Path $siteRoot 'robots.txt'
$expectedSitemapReference = "Sitemap: $siteOrigin$basePath/sitemap.xml"
if (-not (Test-Path -LiteralPath $robotsPath -PathType Leaf)) {
    Add-GeneratedSiteFailure -Source 'robots.txt' -Message 'robots file was not generated'
}
else {
    $robotsContent = Get-Content -LiteralPath $robotsPath -Raw
    if ($robotsContent -cnotmatch [regex]::Escape($expectedSitemapReference)) {
        Add-GeneratedSiteFailure -Source 'robots.txt' -Message "expected sitemap reference was not found: $expectedSitemapReference"
    }
}

if ($failures.Count -gt 0) {
    $details = $failures | Sort-Object -Unique | ForEach-Object { " - $_" }
    throw "Generated site contains $($failures.Count) integrity/accessibility/SEO issue(s):`n$($details -join "`n")"
}

Write-Output "Validated $($htmlFiles.Count) generated HTML page(s); internal references, deterministic accessibility semantics, SEO metadata, canonicals, sitemap, and robots checks passed."
