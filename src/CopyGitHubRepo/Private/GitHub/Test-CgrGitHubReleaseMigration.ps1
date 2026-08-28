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

        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com'
    )

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

    $sourceSelection = Get-CgrGitHubReleaseSelection @selectionParameters
    $releaseResults = [System.Collections.Generic.List[object]]::new()
    $checks = [System.Collections.Generic.List[object]]::new()

    foreach ($sourceRelease in @($sourceSelection.Releases)) {
        $tagName = [string] $sourceRelease.TagName
        $escapedTag = [uri]::EscapeDataString($tagName)
        $mismatches = [System.Collections.Generic.List[string]]::new()

        $destinationCommitResult = Invoke-CgrNativeCommand -FilePath 'gh' -ArgumentList @(
            'api', '--hostname', $HostName,
            "repos/$($DestinationRepository.FullName)/commits/$escapedTag", '--jq', '.sha'
        )
        $destinationCommitSha = if ($destinationCommitResult.ExitCode -eq 0) {
            [string] @($destinationCommitResult.Output)[0]
        }
        else {
            $null
        }

        if ([string]::IsNullOrWhiteSpace($destinationCommitSha)) {
            $mismatches.Add('DestinationTagMissing')
        }
        elseif ($destinationCommitSha -ne [string] $sourceRelease.TargetCommitSha) {
            $mismatches.Add('TagTarget')
        }

        $destinationReleaseResult = Invoke-CgrNativeCommand -FilePath 'gh' -ArgumentList @(
            'api', '--hostname', $HostName,
            "repos/$($DestinationRepository.FullName)/releases/tags/$escapedTag"
        )

        $destinationRelease = $null
        if ($destinationReleaseResult.ExitCode -ne 0) {
            $mismatches.Add('DestinationReleaseMissing')
        }
        else {
            $destinationReleaseJson = ($destinationReleaseResult.Output | ForEach-Object { [string] $_ }) -join "`n"
            try {
                $destinationRelease = $destinationReleaseJson | ConvertFrom-Json -Depth 100
            }
            catch {
                $message = "Destination GitHub Release '$tagName' returned invalid JSON during verification. $($_.Exception.Message)"
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
            if ([string] $destinationRelease.name -ne [string] $sourceRelease.Name) { $mismatches.Add('Name') }
            if ([string] $destinationRelease.body -ne [string] $sourceRelease.Body) { $mismatches.Add('Body') }
            if ([bool] $destinationRelease.draft -ne [bool] $sourceRelease.Draft) { $mismatches.Add('Draft') }
            if ([bool] $destinationRelease.prerelease -ne [bool] $sourceRelease.Prerelease) { $mismatches.Add('Prerelease') }

            $destinationAssets = @($destinationRelease.assets)
            if ($destinationAssets.Count -ne @($sourceRelease.Assets).Count) {
                $mismatches.Add('AssetCount')
            }

            foreach ($sourceAsset in @($sourceRelease.Assets)) {
                $destinationAsset = @($destinationAssets | Where-Object { [string] $_.name -eq [string] $sourceAsset.Name }) | Select-Object -First 1
                if ($null -eq $destinationAsset) {
                    $mismatches.Add("AssetMissing:$($sourceAsset.Name)")
                    continue
                }
                if ([string] $destinationAsset.label -ne [string] $sourceAsset.Label) { $mismatches.Add("AssetLabel:$($sourceAsset.Name)") }
                if ([long] $destinationAsset.size -ne [long] $sourceAsset.Size) { $mismatches.Add("AssetSize:$($sourceAsset.Name)") }
                if ([string] $destinationAsset.content_type -ne [string] $sourceAsset.ContentType) { $mismatches.Add("AssetContentType:$($sourceAsset.Name)") }
                if (-not [string]::IsNullOrWhiteSpace([string] $sourceAsset.Digest) -and
                    [string] $destinationAsset.digest -ne [string] $sourceAsset.Digest) {
                    $mismatches.Add("AssetDigest:$($sourceAsset.Name)")
                }
            }
        }

        $releasePassed = $mismatches.Count -eq 0
        $releaseResults.Add([pscustomobject] @{
                TagName = $tagName
                SourceReleaseId = $sourceRelease.ReleaseId
                DestinationReleaseId = if ($destinationRelease) { $destinationRelease.id } else { $null }
                SourceCommitSha = $sourceRelease.TargetCommitSha
                DestinationCommitSha = $destinationCommitSha
                IsLatest = [bool] $sourceRelease.IsLatest
                SourceAssetCount = @($sourceRelease.Assets).Count
                DestinationAssetCount = if ($destinationRelease) { @($destinationRelease.assets).Count } else { 0 }
                Mismatches = $mismatches.ToArray()
                IsSuccessful = $releasePassed
            })
        $checks.Add([pscustomobject] @{
                Name = "GitHubRelease:$tagName"
                Passed = $releasePassed
                Expected = 'Selected source release metadata, tag target, and assets'
                Actual = if ($releasePassed) { 'Matched' } else { $mismatches.ToArray() }
            })
    }

    $destinationLatestTag = $null
    $latestPassed = $true
    if ($sourceSelection.SourceLatestSelected) {
        $destinationLatestResult = Invoke-CgrNativeCommand -FilePath 'gh' -ArgumentList @(
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
                $destinationLatestTag = $null
            }
        }

        $latestPassed = $destinationLatestTag -eq [string] $sourceSelection.SourceLatestTag
        $checks.Add([pscustomobject] @{
                Name = 'GitHubLatestReleaseMatches'
                Passed = $latestPassed
                Expected = $sourceSelection.SourceLatestTag
                Actual = $destinationLatestTag
            })
    }

    $successfulReleaseCount = @($releaseResults | Where-Object { $_.IsSuccessful }).Count
    [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.ReleaseVerificationResult'
        SchemaVersion = 1
        SourceRepository = $SourceRepository.FullName
        DestinationRepository = $DestinationRepository.FullName
        AvailableSourceReleaseCount = $sourceSelection.AvailableReleaseCount
        SelectedReleaseCount = $sourceSelection.SelectedReleaseCount
        VerifiedReleaseCount = $successfulReleaseCount
        SelectedAssetCount = $sourceSelection.SelectedAssetCount
        SourceLatestTag = $sourceSelection.SourceLatestTag
        SourceLatestSelected = $sourceSelection.SourceLatestSelected
        DestinationLatestTag = $destinationLatestTag
        LatestReleaseMatches = if ($sourceSelection.SourceLatestSelected) { $latestPassed } else { $null }
        IncludePatterns = @($sourceSelection.IncludePatterns)
        ExcludePatterns = @($sourceSelection.ExcludePatterns)
        IncludePrerelease = $sourceSelection.IncludePrerelease
        IncludeDraftReleases = $sourceSelection.IncludeDraftReleases
        ReleaseCount = $sourceSelection.ReleaseCount
        Releases = $releaseResults.ToArray()
        Checks = $checks.ToArray()
        IsSuccessful = -not ($checks | Where-Object { -not $_.Passed })
    }
}
