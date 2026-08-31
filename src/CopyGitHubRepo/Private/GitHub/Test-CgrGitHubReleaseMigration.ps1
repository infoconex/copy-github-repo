function Test-CgrGitHubReleaseMigration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $SourceRepository,

        [Parameter(Mandatory)]
        [psobject] $DestinationRepository,

        [string[]] $ReleaseTag,

        [string[]] $ReleaseExcludeTag,

        [switch] $IncludePrerelease,

        [switch] $IncludeDraftReleases,

        [ValidateRange(1, [int]::MaxValue)]
        [int] $ReleaseCount,

        [psobject] $ApprovedSelection,

        [object[]] $DestinationTagTargets,

        [switch] $RequireExactDestinationReleaseSet,

        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com'
    )

    $sourceSelection = if ($ApprovedSelection) {
        $ApprovedSelection
    }
    else {
        $selectionParameters = @{
            Repository = $SourceRepository
            ReleaseTag = $ReleaseTag
            ReleaseExcludeTag = $ReleaseExcludeTag
            IncludePrerelease = $IncludePrerelease
            IncludeDraftReleases = $IncludeDraftReleases
            HostName = $HostName
        }
        if ($PSBoundParameters.ContainsKey('ReleaseCount')) {
            $selectionParameters.ReleaseCount = $ReleaseCount
        }
        Get-CgrGitHubReleaseSelection @selectionParameters
    }

    $approvedReleases = @(Get-CgrObjectProperty -InputObject $sourceSelection -Name 'Releases')
    $expectedDestinationTargetByTag = @{}
    if ($PSBoundParameters.ContainsKey('DestinationTagTargets')) {
        $targetEvidence = @($DestinationTagTargets)
        $approvedTags = @($approvedReleases | ForEach-Object { [string] (Get-CgrObjectProperty -InputObject $_ -Name 'TagName') } | Sort-Object)
        $targetTags = @($targetEvidence | ForEach-Object { [string] (Get-CgrObjectProperty -InputObject $_ -Name 'TagName') } | Sort-Object)
        if (($approvedTags -join "`n") -ne ($targetTags -join "`n")) {
            $message = 'Destination release-tag target evidence does not exactly match the approved release selection.'
            $exception = [System.InvalidOperationException]::new($message)
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'ApprovedReleaseDestinationTagEvidenceInvalid',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $DestinationRepository.FullName
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        foreach ($target in $targetEvidence) {
            $tagName = [string] (Get-CgrObjectProperty -InputObject $target -Name 'TagName')
            $destinationCommitSha = [string] (Get-CgrObjectProperty -InputObject $target -Name 'DestinationCommitSha')
            if ([string]::IsNullOrWhiteSpace($tagName) -or
                [string]::IsNullOrWhiteSpace($destinationCommitSha) -or
                $expectedDestinationTargetByTag.ContainsKey($tagName)) {
                $message = "Destination release-tag target evidence for '$tagName' is missing or ambiguous."
                $exception = [System.InvalidOperationException]::new($message)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'ApprovedReleaseDestinationTagEvidenceInvalid',
                    [System.Management.Automation.ErrorCategory]::InvalidData,
                    $tagName
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
            $expectedDestinationTargetByTag[$tagName] = $destinationCommitSha
        }
    }

    $releaseResults = [System.Collections.Generic.List[object]]::new()
    $checks = [System.Collections.Generic.List[object]]::new()

    if ($RequireExactDestinationReleaseSet) {
        $listResult = Invoke-CgrGitHubApiReadRequest -ArgumentList @(
            'api', '--hostname', $HostName,
            '--paginate', '--slurp',
            "repos/$($DestinationRepository.FullName)/releases?per_page=100"
        )
        if ($listResult.ExitCode -ne 0) {
            $diagnostic = Protect-CgrDiagnosticText -Text ([string] $listResult.ErrorText)
            $message = "Unable to enumerate destination GitHub Releases during verification. $diagnostic"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'DestinationGitHubReleaseEnumerationFailed',
                [System.Management.Automation.ErrorCategory]::ReadError,
                $DestinationRepository.FullName
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $destinationReleaseJson = ($listResult.Output | ForEach-Object { [string] $_ }) -join "`n"
        try {
            $pages = if ([string]::IsNullOrWhiteSpace($destinationReleaseJson)) { @() } else { @($destinationReleaseJson | ConvertFrom-Json -Depth 100) }
        }
        catch {
            $diagnostic = Protect-CgrDiagnosticText -Text $_.Exception.Message
            $message = "Destination GitHub Release enumeration returned invalid JSON. $diagnostic"
            $exception = [System.InvalidOperationException]::new($message)
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'DestinationGitHubReleaseEnumerationResponseInvalid',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $DestinationRepository.FullName
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $actualReleaseTags = [System.Collections.Generic.List[string]]::new()
        foreach ($page in $pages) {
            foreach ($release in @($page)) {
                if ($null -ne $release) {
                    $actualReleaseTags.Add([string] $release.tag_name)
                }
            }
        }
        $expectedReleaseTags = @($approvedReleases | ForEach-Object { [string] (Get-CgrObjectProperty -InputObject $_ -Name 'TagName') } | Sort-Object)
        $actualReleaseTagsSorted = @($actualReleaseTags.ToArray() | Sort-Object)
        $checks.Add([pscustomobject] @{
                Name = 'GitHubReleaseSetMatchesReviewedSelection'
                Passed = ($actualReleaseTagsSorted -join "`n") -eq ($expectedReleaseTags -join "`n")
                Expected = $expectedReleaseTags
                Actual = $actualReleaseTagsSorted
            })
    }

    foreach ($sourceRelease in $approvedReleases) {
        $tagName = [string] (Get-CgrObjectProperty -InputObject $sourceRelease -Name 'TagName')
        $escapedTag = [uri]::EscapeDataString($tagName)
        $mismatches = [System.Collections.Generic.List[string]]::new()

        $destinationCommitResult = Invoke-CgrGitHubApiReadRequest -ArgumentList @(
            'api', '--hostname', $HostName,
            "repos/$($DestinationRepository.FullName)/commits/$escapedTag", '--jq', '.sha'
        )
        $destinationCommitSha = if ($destinationCommitResult.ExitCode -eq 0) {
            [string] @($destinationCommitResult.Output)[0]
        }
        elseif ([string] $destinationCommitResult.ErrorText -match '(?i)404|not found') {
            $null
        }
        else {
            $diagnostic = Protect-CgrDiagnosticText -Text ([string] $destinationCommitResult.ErrorText)
            $message = "Unable to read destination tag commit '$tagName' while verifying GitHub Releases. $diagnostic"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'DestinationGitHubReleaseTagReadFailed',
                [System.Management.Automation.ErrorCategory]::ReadError,
                $tagName
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $expectedDestinationCommitSha = if ($expectedDestinationTargetByTag.ContainsKey($tagName)) {
            [string] $expectedDestinationTargetByTag[$tagName]
        }
        else {
            [string] (Get-CgrObjectProperty -InputObject $sourceRelease -Name 'TargetCommitSha')
        }

        if ([string]::IsNullOrWhiteSpace($destinationCommitSha)) {
            $mismatches.Add('DestinationTagMissing')
        }
        elseif ($destinationCommitSha -ne $expectedDestinationCommitSha) {
            $mismatches.Add('TagTarget')
        }

        $destinationReleaseResult = Invoke-CgrGitHubApiReadRequest -ArgumentList @(
            'api', '--hostname', $HostName,
            "repos/$($DestinationRepository.FullName)/releases/tags/$escapedTag"
        )

        $destinationRelease = $null
        if ($destinationReleaseResult.ExitCode -ne 0) {
            if ([string] $destinationReleaseResult.ErrorText -match '(?i)404|not found') {
                $mismatches.Add('DestinationReleaseMissing')
            }
            else {
                $diagnostic = Protect-CgrDiagnosticText -Text ([string] $destinationReleaseResult.ErrorText)
                $message = "Unable to read destination GitHub Release '$tagName' during verification. $diagnostic"
                $exception = [System.InvalidOperationException]::new($message.Trim())
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'DestinationGitHubReleaseVerificationReadFailed',
                    [System.Management.Automation.ErrorCategory]::ReadError,
                    $tagName
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
        }
        else {
            $destinationReleaseJson = ($destinationReleaseResult.Output | ForEach-Object { [string] $_ }) -join "`n"
            try {
                $destinationRelease = $destinationReleaseJson | ConvertFrom-Json -Depth 100
            }
            catch {
                $diagnostic = Protect-CgrDiagnosticText -Text $_.Exception.Message
                $message = "Destination GitHub Release '$tagName' returned invalid JSON during verification. $diagnostic"
                $exception = [System.InvalidOperationException]::new($message)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'DestinationGitHubReleaseVerificationResponseInvalid',
                    [System.Management.Automation.ErrorCategory]::InvalidData,
                    $tagName
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
        }

        if ($destinationRelease) {
            if ([string] $destinationRelease.tag_name -ne $tagName) { $mismatches.Add('TagName') }
            if ([string] $destinationRelease.name -ne [string] (Get-CgrObjectProperty -InputObject $sourceRelease -Name 'Name')) { $mismatches.Add('Name') }
            if ([string] $destinationRelease.body -ne [string] (Get-CgrObjectProperty -InputObject $sourceRelease -Name 'Body')) { $mismatches.Add('Body') }
            if ([bool] $destinationRelease.draft -ne [bool] (Get-CgrObjectProperty -InputObject $sourceRelease -Name 'Draft')) { $mismatches.Add('Draft') }
            if ([bool] $destinationRelease.prerelease -ne [bool] (Get-CgrObjectProperty -InputObject $sourceRelease -Name 'Prerelease')) { $mismatches.Add('Prerelease') }

            $sourceAssets = @(Get-CgrObjectProperty -InputObject $sourceRelease -Name 'Assets')
            $destinationAssets = @($destinationRelease.assets)
            if ($destinationAssets.Count -ne $sourceAssets.Count) {
                $mismatches.Add('AssetCount')
            }

            foreach ($sourceAsset in $sourceAssets) {
                $assetName = [string] (Get-CgrObjectProperty -InputObject $sourceAsset -Name 'Name')
                $destinationAsset = @($destinationAssets | Where-Object { [string] $_.name -eq $assetName }) | Select-Object -First 1
                if ($null -eq $destinationAsset) {
                    $mismatches.Add("AssetMissing:$assetName")
                    continue
                }
                if ([string] $destinationAsset.label -ne [string] (Get-CgrObjectProperty -InputObject $sourceAsset -Name 'Label')) { $mismatches.Add("AssetLabel:$assetName") }
                if ([long] $destinationAsset.size -ne [long] (Get-CgrObjectProperty -InputObject $sourceAsset -Name 'Size')) { $mismatches.Add("AssetSize:$assetName") }
                if ([string] $destinationAsset.content_type -ne [string] (Get-CgrObjectProperty -InputObject $sourceAsset -Name 'ContentType')) { $mismatches.Add("AssetContentType:$assetName") }
                $sourceDigest = [string] (Get-CgrObjectProperty -InputObject $sourceAsset -Name 'Digest')
                if (-not [string]::IsNullOrWhiteSpace($sourceDigest) -and [string] $destinationAsset.digest -ne $sourceDigest) {
                    $mismatches.Add("AssetDigest:$assetName")
                }
            }
        }

        $releasePassed = $mismatches.Count -eq 0
        $sourceAssetsForResult = @(Get-CgrObjectProperty -InputObject $sourceRelease -Name 'Assets')
        $releaseResults.Add([pscustomobject] @{
                TagName = $tagName
                SourceReleaseId = Get-CgrObjectProperty -InputObject $sourceRelease -Name 'ReleaseId'
                DestinationReleaseId = if ($destinationRelease) { $destinationRelease.id } else { $null }
                SourceCommitSha = Get-CgrObjectProperty -InputObject $sourceRelease -Name 'TargetCommitSha'
                ExpectedDestinationCommitSha = $expectedDestinationCommitSha
                DestinationCommitSha = $destinationCommitSha
                IsLatest = [bool] (Get-CgrObjectProperty -InputObject $sourceRelease -Name 'IsLatest')
                SourceAssetCount = $sourceAssetsForResult.Count
                DestinationAssetCount = if ($destinationRelease) { @($destinationRelease.assets).Count } else { 0 }
                Mismatches = $mismatches.ToArray()
                IsSuccessful = $releasePassed
            })
        $checks.Add([pscustomobject] @{
                Name = "GitHubRelease:$tagName"
                Passed = $releasePassed
                Expected = 'Reviewed release metadata, expected destination tag target, and assets'
                Actual = if ($releasePassed) { 'Matched' } else { $mismatches.ToArray() }
            })
    }

    $sourceLatestSelected = [bool] (Get-CgrObjectProperty -InputObject $sourceSelection -Name 'SourceLatestSelected')
    $sourceLatestTag = [string] (Get-CgrObjectProperty -InputObject $sourceSelection -Name 'SourceLatestTag')
    $destinationLatestTag = $null
    $latestPassed = $true
    if ($sourceLatestSelected) {
        $destinationLatestResult = Invoke-CgrGitHubApiReadRequest -ArgumentList @(
            'api', '--hostname', $HostName,
            "repos/$($DestinationRepository.FullName)/releases/latest"
        )
        if ($destinationLatestResult.ExitCode -eq 0) {
            $destinationLatestJson = ($destinationLatestResult.Output | ForEach-Object { [string] $_ }) -join "`n"
            try {
                $destinationLatest = $destinationLatestJson | ConvertFrom-Json -Depth 100
                $destinationLatestTag = [string] $destinationLatest.tag_name
            }
            catch {
                $diagnostic = Protect-CgrDiagnosticText -Text $_.Exception.Message
                $message = "Destination latest GitHub Release returned invalid JSON during verification. $diagnostic"
                $exception = [System.InvalidOperationException]::new($message)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'DestinationGitHubLatestReleaseVerificationResponseInvalid',
                    [System.Management.Automation.ErrorCategory]::InvalidData,
                    $DestinationRepository.FullName
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
        }
        elseif ([string] $destinationLatestResult.ErrorText -notmatch '(?i)404|not found') {
            $diagnostic = Protect-CgrDiagnosticText -Text ([string] $destinationLatestResult.ErrorText)
            $message = "Unable to read the destination latest GitHub Release during verification. $diagnostic"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'DestinationGitHubLatestReleaseVerificationReadFailed',
                [System.Management.Automation.ErrorCategory]::ReadError,
                $DestinationRepository.FullName
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $latestPassed = $destinationLatestTag -eq $sourceLatestTag
        $checks.Add([pscustomobject] @{
                Name = 'GitHubLatestReleaseMatches'
                Passed = $latestPassed
                Expected = $sourceLatestTag
                Actual = $destinationLatestTag
            })
    }

    $successfulReleaseCount = @($releaseResults | Where-Object { $_.IsSuccessful }).Count
    [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.ReleaseVerificationResult'
        SchemaVersion = 1
        SourceRepository = $SourceRepository.FullName
        DestinationRepository = $DestinationRepository.FullName
        UsedApprovedSelection = [bool] $ApprovedSelection
        AvailableSourceReleaseCount = Get-CgrObjectProperty -InputObject $sourceSelection -Name 'AvailableReleaseCount'
        SelectedReleaseCount = Get-CgrObjectProperty -InputObject $sourceSelection -Name 'SelectedReleaseCount'
        VerifiedReleaseCount = $successfulReleaseCount
        SelectedAssetCount = Get-CgrObjectProperty -InputObject $sourceSelection -Name 'SelectedAssetCount'
        SourceLatestTag = $sourceLatestTag
        SourceLatestSelected = $sourceLatestSelected
        DestinationLatestTag = $destinationLatestTag
        LatestReleaseMatches = if ($sourceLatestSelected) { $latestPassed } else { $null }
        IncludePatterns = @(Get-CgrObjectProperty -InputObject $sourceSelection -Name 'IncludePatterns')
        ExcludePatterns = @(Get-CgrObjectProperty -InputObject $sourceSelection -Name 'ExcludePatterns')
        IncludePrerelease = [bool] (Get-CgrObjectProperty -InputObject $sourceSelection -Name 'IncludePrerelease')
        IncludeDraftReleases = [bool] (Get-CgrObjectProperty -InputObject $sourceSelection -Name 'IncludeDraftReleases')
        ReleaseCount = Get-CgrObjectProperty -InputObject $sourceSelection -Name 'ReleaseCount'
        Releases = $releaseResults.ToArray()
        Checks = $checks.ToArray()
        IsSuccessful = -not ($checks | Where-Object { -not $_.Passed })
    }
}
