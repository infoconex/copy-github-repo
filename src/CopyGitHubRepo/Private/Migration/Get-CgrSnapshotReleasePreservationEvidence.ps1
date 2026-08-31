function Get-CgrSnapshotReleasePreservationEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $Plan,
        [AllowNull()] [psobject] $DestinationRepository,
        [AllowNull()] [psobject] $SnapshotCopyResult,
        [AllowNull()] [psobject] $ReleaseRestoreResult,
        [ValidateNotNullOrEmpty()] [string] $HostName = 'github.com'
    )

    $includeReleases = [bool] (Get-CgrObjectProperty -InputObject $Plan -Name 'IncludeReleases')
    $checkpointPlan = Get-CgrObjectProperty -InputObject $Plan -Name 'ReleaseCheckpointPlan'
    $releaseSelection = Get-CgrObjectProperty -InputObject $Plan -Name 'ReleaseSelection'
    if (-not $includeReleases -or $null -eq $checkpointPlan) {
        return $null
    }

    $generatedCommits = if ($SnapshotCopyResult) { @(Get-CgrObjectProperty -InputObject $SnapshotCopyResult -Name 'GeneratedCommits') } else { @() }
    $recreatedTags = if ($SnapshotCopyResult) { @(Get-CgrObjectProperty -InputObject $SnapshotCopyResult -Name 'ReleaseTags') } else { @() }
    $destinationHeadCommitSha = if ($SnapshotCopyResult) { [string] (Get-CgrObjectProperty -InputObject $SnapshotCopyResult -Name 'CommitSha') } else { $null }
    $snapshotPublicationVerified = [bool] ($SnapshotCopyResult -and (Get-CgrObjectProperty -InputObject $SnapshotCopyResult -Name 'Verified'))

    if ($null -eq $SnapshotCopyResult -and $DestinationRepository) {
        $observedTags = [System.Collections.Generic.List[object]]::new()
        $observedCommits = [System.Collections.Generic.List[object]]::new()
        foreach ($releaseEvidence in @(Get-CgrObjectProperty -InputObject $checkpointPlan -Name 'ReleaseEvidence')) {
            $tagName = [string] (Get-CgrObjectProperty -InputObject $releaseEvidence -Name 'TagName')
            if ([string]::IsNullOrWhiteSpace($tagName)) { continue }

            $tagRead = Invoke-CgrGitHubApiReadRequest -ArgumentList @(
                'api', '--hostname', $HostName,
                "repos/$($DestinationRepository.FullName)/git/ref/tags/$([uri]::EscapeDataString($tagName))"
            )
            if ($tagRead.ExitCode -ne 0) { continue }

            $tagJson = ($tagRead.Output | ForEach-Object { [string] $_ }) -join "`n"
            $tag = $tagJson | ConvertFrom-Json -Depth 20
            $destinationCommitSha = [string] $tag.object.sha
            $sourceCommitSha = [string] (Get-CgrObjectProperty -InputObject $releaseEvidence -Name 'PeeledCommitSha')
            $checkpoint = @((Get-CgrObjectProperty -InputObject $checkpointPlan -Name 'Checkpoints') | Where-Object {
                    [string] (Get-CgrObjectProperty -InputObject $_ -Name 'SourceCommitSha') -eq $sourceCommitSha
                }) | Select-Object -First 1

            $observedTags.Add([pscustomobject] @{
                    TagName = $tagName
                    SourceTagObjectType = [string] (Get-CgrObjectProperty -InputObject $releaseEvidence -Name 'TagObjectType')
                    SourceTagObjectSha = [string] (Get-CgrObjectProperty -InputObject $releaseEvidence -Name 'TagObjectSha')
                    SourcePeeledCommitSha = $sourceCommitSha
                    DestinationCommitSha = $destinationCommitSha
                    DestinationTagType = [string] $tag.object.type
                    ObservedAfterFailure = $true
                    Verified = $false
                })

            if (@($observedCommits | Where-Object { $_.CommitSha -eq $destinationCommitSha }).Count -eq 0) {
                $observedCommits.Add([pscustomobject] @{
                        Kind = 'ReleaseCheckpoint'
                        Order = if ($checkpoint) { Get-CgrObjectProperty -InputObject $checkpoint -Name 'Order' } else { $null }
                        SourceCommitSha = $sourceCommitSha
                        SourceTreeSha = if ($checkpoint) { Get-CgrObjectProperty -InputObject $checkpoint -Name 'SourceTreeSha' } else { $null }
                        TagNames = if ($checkpoint) { @(Get-CgrObjectProperty -InputObject $checkpoint -Name 'TagNames') } else { @($tagName) }
                        CommitSha = $destinationCommitSha
                        TreeSha = $null
                        Message = $null
                        ObservedAfterFailure = $true
                        Verified = $false
                    })
            }
        }
        $recreatedTags = $observedTags.ToArray()
        $generatedCommits = $observedCommits.ToArray()

        $branchRead = Invoke-CgrGitHubApiReadRequest -ArgumentList @(
            'api', '--hostname', $HostName,
            "repos/$($DestinationRepository.FullName)/git/ref/heads/$([uri]::EscapeDataString([string] $Plan.SourceDefaultBranch))"
        )
        if ($branchRead.ExitCode -eq 0) {
            $branchJson = ($branchRead.Output | ForEach-Object { [string] $_ }) -join "`n"
            $branch = $branchJson | ConvertFrom-Json -Depth 20
            $destinationHeadCommitSha = [string] $branch.object.sha
        }
    }

    $restoredReleases = if ($ReleaseRestoreResult) { @(Get-CgrObjectProperty -InputObject $ReleaseRestoreResult -Name 'Releases') } else { @() }
    $releaseRestoreStatus = if ($ReleaseRestoreResult) { [string] (Get-CgrObjectProperty -InputObject $ReleaseRestoreResult -Name 'Status') } else { $null }
    $releaseRestoreSuccessful = [bool] ($ReleaseRestoreResult -and $releaseRestoreStatus -eq 'Restored' -and (Get-CgrObjectProperty -InputObject $ReleaseRestoreResult -Name 'IsSuccessful'))
    $observedReleaseEvidence = [System.Collections.Generic.List[object]]::new()

    if (-not $releaseRestoreSuccessful -and $DestinationRepository) {
        foreach ($approvedRelease in @(Get-CgrObjectProperty -InputObject $releaseSelection -Name 'Releases')) {
            $tagName = [string] (Get-CgrObjectProperty -InputObject $approvedRelease -Name 'TagName')
            if ([string]::IsNullOrWhiteSpace($tagName)) { continue }

            $releaseRead = Invoke-CgrGitHubApiReadRequest -ArgumentList @(
                'api', '--hostname', $HostName,
                "repos/$($DestinationRepository.FullName)/releases/tags/$([uri]::EscapeDataString($tagName))"
            )
            if ($releaseRead.ExitCode -ne 0) { continue }

            $releaseJson = ($releaseRead.Output | ForEach-Object { [string] $_ }) -join "`n"
            $release = $releaseJson | ConvertFrom-Json -Depth 100
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
            $observedReleaseEvidence.Add([pscustomobject] @{
                    TagName = $tagName
                    SourceReleaseId = Get-CgrObjectProperty -InputObject $approvedRelease -Name 'ReleaseId'
                    DestinationReleaseId = $release.id
                    Name = [string] $release.name
                    Body = [string] $release.body
                    Draft = [bool] $release.draft
                    Prerelease = [bool] $release.prerelease
                    Assets = $assets
                    AssetCount = $assets.Count
                    ObservedAfterFailure = $true
                    Verified = $false
                })
        }
        $restoredReleases = $observedReleaseEvidence.ToArray()
    }

    $approvedReleaseCount = @((Get-CgrObjectProperty -InputObject $releaseSelection -Name 'Releases')).Count
    $plannedCheckpointCount = @((Get-CgrObjectProperty -InputObject $checkpointPlan -Name 'Checkpoints')).Count
    $publishedCheckpointCount = @($generatedCommits | Where-Object { (Get-CgrObjectProperty -InputObject $_ -Name 'Kind') -eq 'ReleaseCheckpoint' }).Count

    return [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.SnapshotReleasePreservationEvidence'
        Planned = [pscustomobject] @{
            ReleaseCheckpointPlan = $checkpointPlan
            ReleaseSelection = $releaseSelection
            CheckpointCount = $plannedCheckpointCount
            ReleaseCount = $approvedReleaseCount
        }
        Actual = [pscustomobject] @{
            DestinationHeadCommitSha = $destinationHeadCommitSha
            GeneratedCommits = @($generatedCommits)
            ReleaseTags = @($recreatedTags)
            Releases = @($restoredReleases)
        }
        Verified = [pscustomobject] @{
            SnapshotPublication = $snapshotPublicationVerified
            ReleaseRestore = $releaseRestoreSuccessful
            VerifiedReleaseCount = @($restoredReleases | Where-Object { [bool] (Get-CgrObjectProperty -InputObject $_ -Name 'IsVerified') }).Count
        }
        Incomplete = [pscustomobject] @{
            CheckpointCount = [Math]::Max(0, $plannedCheckpointCount - $publishedCheckpointCount)
            TagCount = [Math]::Max(0, $approvedReleaseCount - @($recreatedTags).Count)
            ReleaseCount = [Math]::Max(0, $approvedReleaseCount - @($restoredReleases).Count)
        }
    }
}
