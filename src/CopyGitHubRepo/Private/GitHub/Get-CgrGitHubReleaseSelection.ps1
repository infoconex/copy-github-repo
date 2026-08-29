function Get-CgrGitHubReleaseSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Repository,

        [string[]] $ReleaseTag,

        [string[]] $ReleaseExcludeTag,

        [switch] $IncludePrerelease,

        [switch] $IncludeDraftReleases,

        [ValidateRange(1, [int]::MaxValue)]
        [int] $ReleaseCount,

        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com'
    )

    $listResult = Invoke-CgrGitHubApiReadRequest `
        -ArgumentList @(
            'api', '--hostname', $HostName,
            '--paginate', '--slurp',
            "repos/$($Repository.FullName)/releases?per_page=100"
        )

    if ($listResult.ExitCode -ne 0) {
        $diagnostic = Protect-CgrDiagnosticText -Text ([string] $listResult.ErrorText)
        $message = "GitHub CLI failed to enumerate releases for '$($Repository.FullName)'. $diagnostic"
        $exception = [System.InvalidOperationException]::new($message.Trim())
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'SourceGitHubReleaseEnumerationFailed',
            [System.Management.Automation.ErrorCategory]::ReadError,
            $Repository.FullName
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $json = ($listResult.Output | ForEach-Object { [string] $_ }) -join "`n"
    $pages = if ([string]::IsNullOrWhiteSpace($json)) { @() } else { @($json | ConvertFrom-Json -Depth 100) }
    $available = [System.Collections.Generic.List[object]]::new()
    foreach ($page in $pages) {
        foreach ($release in @($page)) {
            if ($null -ne $release) {
                $available.Add($release)
            }
        }
    }

    $latestReleaseId = $null
    $latestReleaseTag = $null
    $latestResult = Invoke-CgrGitHubApiReadRequest `
        -ArgumentList @('api', '--hostname', $HostName, "repos/$($Repository.FullName)/releases/latest")
    if ($latestResult.ExitCode -eq 0) {
        $latestJson = ($latestResult.Output | ForEach-Object { [string] $_ }) -join "`n"
        if (-not [string]::IsNullOrWhiteSpace($latestJson)) {
            $latestRelease = $latestJson | ConvertFrom-Json -Depth 100
            $latestReleaseId = $latestRelease.id
            $latestReleaseTag = [string] $latestRelease.tag_name
        }
    }
    elseif ([string] $latestResult.ErrorText -notmatch '(?i)404|not found') {
        $diagnostic = Protect-CgrDiagnosticText -Text ([string] $latestResult.ErrorText)
        $message = "GitHub CLI failed to determine the latest release for '$($Repository.FullName)'. $diagnostic"
        $exception = [System.InvalidOperationException]::new($message.Trim())
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'SourceGitHubLatestReleaseReadFailed',
            [System.Management.Automation.ErrorCategory]::ReadError,
            $Repository.FullName
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $selected = @($available)
    if (-not $IncludeDraftReleases) {
        $selected = @($selected | Where-Object { -not [bool] $_.draft })
    }
    if (-not $IncludePrerelease) {
        $selected = @($selected | Where-Object { -not [bool] $_.prerelease })
    }

    if ($ReleaseTag -and $ReleaseTag.Count -gt 0) {
        $selected = @($selected | Where-Object {
                $tagName = [string] $_.tag_name
                foreach ($pattern in $ReleaseTag) {
                    if ($tagName -like $pattern) { return $true }
                }
                return $false
            })
    }

    if ($ReleaseExcludeTag -and $ReleaseExcludeTag.Count -gt 0) {
        $selected = @($selected | Where-Object {
                $tagName = [string] $_.tag_name
                foreach ($pattern in $ReleaseExcludeTag) {
                    if ($tagName -like $pattern) { return $false }
                }
                return $true
            })
    }

    $selected = @($selected | Sort-Object -Property @{ Expression = {
                    if ($_.published_at) { [datetimeoffset] $_.published_at }
                    elseif ($_.created_at) { [datetimeoffset] $_.created_at }
                    else { [datetimeoffset]::MinValue }
                }; Descending = $true }, @{ Expression = { [string] $_.tag_name }; Descending = $false })

    if ($PSBoundParameters.ContainsKey('ReleaseCount')) {
        $selected = @($selected | Select-Object -First $ReleaseCount)
    }

    $normalized = [System.Collections.Generic.List[object]]::new()
    foreach ($release in $selected) {
        $tagName = [string] $release.tag_name
        if ([string]::IsNullOrWhiteSpace($tagName)) {
            $message = "Source release id '$($release.id)' does not have a tag name and cannot be selected safely."
            $exception = [System.InvalidOperationException]::new($message)
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'SourceGitHubReleaseTagMissing',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $release.id
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $commitResult = Invoke-CgrGitHubApiReadRequest `
            -ArgumentList @('api', '--hostname', $HostName, "repos/$($Repository.FullName)/commits/$([uri]::EscapeDataString($tagName))", '--jq', '.sha')
        if ($commitResult.ExitCode -ne 0) {
            $diagnostic = Protect-CgrDiagnosticText -Text ([string] $commitResult.ErrorText)
            $message = "Source release tag '$tagName' does not resolve to a commit and cannot be selected safely. $diagnostic"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'SourceGitHubReleaseTagResolutionFailed',
                [System.Management.Automation.ErrorCategory]::InvalidResult,
                $tagName
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $assets = @($release.assets | ForEach-Object {
                [pscustomobject] @{
                    Id = $_.id
                    Name = [string] $_.name
                    Label = [string] $_.label
                    Size = [long] $_.size
                    ContentType = [string] $_.content_type
                    Digest = [string] $_.digest
                }
            })

        $normalized.Add([pscustomobject] @{
                ReleaseId = $release.id
                TagName = $tagName
                Name = [string] $release.name
                Body = [string] $release.body
                Draft = [bool] $release.draft
                Prerelease = [bool] $release.prerelease
                IsLatest = [bool] ($null -ne $latestReleaseId -and [long] $release.id -eq [long] $latestReleaseId)
                CreatedAt = $release.created_at
                PublishedAt = $release.published_at
                TargetCommitSha = [string] @($commitResult.Output)[0]
                Assets = $assets
            })
    }

    $selectedAssetCount = if ($normalized.Count -eq 0) {
        0
    }
    else {
        [int] (($normalized | ForEach-Object { @($_.Assets).Count } | Measure-Object -Sum).Sum)
    }

    [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.ReleaseSelection'
        Repository = $Repository.FullName
        AvailableReleaseCount = $available.Count
        SelectedReleaseCount = $normalized.Count
        SelectedAssetCount = $selectedAssetCount
        SourceLatestReleaseId = $latestReleaseId
        SourceLatestTag = $latestReleaseTag
        SourceLatestSelected = [bool] ($normalized | Where-Object { $_.IsLatest } | Select-Object -First 1)
        IncludePatterns = @($ReleaseTag)
        ExcludePatterns = @($ReleaseExcludeTag)
        IncludePrerelease = [bool] $IncludePrerelease
        IncludeDraftReleases = [bool] $IncludeDraftReleases
        ReleaseCount = if ($PSBoundParameters.ContainsKey('ReleaseCount')) { $ReleaseCount } else { $null }
        Releases = $normalized.ToArray()
    }
}
