function Invoke-CgrSameNameSnapshotReplacement {
    <#
    .SYNOPSIS
    Replaces a repository at the same name with a clean Snapshot while preserving the original as an archive.

    .DESCRIPTION
    Revalidates approved source evidence, renames the original repository to the
    reviewed archive name, verifies the archived source, creates a fresh repository
    at the original name, proves distinct replacement identity, publishes and
    verifies the clean Snapshot, optionally restores the exact approved GitHub Releases
    against generated Snapshot tags, then restores supported settings and protection.
    Partial failure produces recovery evidence rather than hiding mutation state.

    .NOTES
    Same-name replacement is the highest-risk Snapshot path. Exact confirmation and
    ShouldProcess are completed by Copy-GitHubRepository before entry. The archived
    original is intentionally retained and is never silently overwritten or deleted.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'The public Copy-GitHubRepository command performs ShouldProcess and exact same-name confirmation before calling this orchestration boundary.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $Plan,
        [Parameter(Mandatory)] [psobject] $SourceRepository,
        [ValidateNotNullOrEmpty()] [string] $HostName = 'github.com',
        [string] $ReportPath
    )

    $completedSteps = [System.Collections.Generic.List[object]]::new()
    $archive = $null
    $destination = $null
    $snapshot = $null
    $snapshotRootCommitSha = $null
    $repositoryIdentity = $null
    $sourceState = Get-CgrObjectProperty -InputObject $Plan -Name 'SourceState'
    $releaseCheckpointPlan = Get-CgrObjectProperty -InputObject $Plan -Name 'ReleaseCheckpointPlan'
    $includeReleases = [bool] (Get-CgrObjectProperty -InputObject $Plan -Name 'IncludeReleases')
    $releaseSelection = Get-CgrObjectProperty -InputObject $Plan -Name 'ReleaseSelection'
    $sourceRepositoryId = Get-CgrObjectProperty -InputObject $SourceRepository -Name 'Id'
    $sourceRepositoryNodeId = Get-CgrObjectProperty -InputObject $SourceRepository -Name 'NodeId'
    $failureStage = 'ValidateApprovedSourceState'
    $releases = [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.ReleaseMigrationResult'
        SourceRepository = $SourceRepository.FullName
        DestinationRepository = $Plan.DestinationRepository
        ApprovedReleaseCount = 0
        DestinationReleaseCount = 0
        Releases = @()
        Unsupported = @()
        IsSuccessful = $true
        Status = 'NotRequested'
    }

    try {
        Assert-CgrApprovedSourceState -Repository $SourceRepository -SourceState $sourceState | Out-Null

        $failureStage = 'PreserveSourceAsArchive'
        $archive = Rename-CgrGitHubRepository -SourceRepository $SourceRepository -ArchiveRepository $Plan.ArchiveRepository -HostName $HostName
        $completedSteps.Add([pscustomobject] @{ Order = 1; Name = 'PreserveSourceAsArchive'; MutatedGitHub = $true; Verified = $true })

        $failureStage = 'VerifyArchivedSource'
        Assert-CgrApprovedSourceState -Repository $archive -SourceState $sourceState -AllowRepositoryNameChange | Out-Null
        $completedSteps.Add([pscustomobject] @{ Order = 2; Name = 'VerifyArchivedSource'; MutatedGitHub = $false; Verified = $true })

        $failureStage = 'CreateReplacementRepository'
        $destination = New-CgrGitHubRepository -Repository $Plan.DestinationRepository -Visibility $Plan.DestinationVisibility -HostName $HostName
        $completedSteps.Add([pscustomobject] @{ Order = 3; Name = 'CreateReplacementRepository'; MutatedGitHub = $true; Verified = $true })

        $failureStage = 'VerifyReplacementRepositoryIdentity'
        $repositoryIdentity = Assert-CgrReplacementRepositoryIdentity -SourceRepository $SourceRepository -ArchiveRepository $archive -ReplacementRepository $destination
        $completedSteps.Add([pscustomobject] @{ Order = 4; Name = 'VerifyReplacementRepositoryIdentity'; MutatedGitHub = $false; Verified = $true })

        $failureStage = 'CopySnapshot'
        $snapshot = @(Copy-CgrRepositorySnapshot -SourceRepository $archive -DestinationRepository $destination -BranchName $Plan.SourceDefaultBranch -CommitMessage $Plan.CommitMessage -ApprovedSourceState $sourceState -ReleaseCheckpointPlan $releaseCheckpointPlan)[-1]
        $snapshotRootCommitSha = Get-CgrObjectProperty -InputObject $snapshot -Name 'RootCommitSha'
        if ($null -eq $snapshotRootCommitSha) { $snapshotRootCommitSha = Get-CgrObjectProperty -InputObject $snapshot -Name 'CommitSha' }
        $completedSteps.Add([pscustomobject] @{ Order = 5; Name = 'CopySnapshot'; MutatedGitHub = $true; Verified = $snapshot.Verified })

        $failureStage = 'ReloadReplacement'
        $verifiedDestination = Get-CgrRepository -Repository $destination.FullName -HostName $HostName
        $failureStage = 'VerifySnapshot'
        $verification = Invoke-CgrActivityStage -Name 'VerifyDestinationContent' -Message 'Verify destination content' -Action {
            if ($releaseCheckpointPlan) {
                Invoke-CgrApprovedSnapshotReleaseVerification `
                    -SourceRepository $archive `
                    -DestinationRepository $verifiedDestination `
                    -ReleaseCheckpointPlan $releaseCheckpointPlan
            }
            else {
                Invoke-CgrRepositorySnapshotVerification `
                    -SourceRepository $archive `
                    -DestinationRepository $verifiedDestination `
                    -ApprovedSourceState $sourceState
            }
        }
        $completedSteps.Add([pscustomobject] @{ Order = 6; Name = 'VerifySnapshot'; MutatedGitHub = $false; Verified = $verification.IsSuccessful })

        if ($includeReleases) {
            $failureStage = 'RestoreGitHubReleases'
            if (-not $verification.IsSuccessful) {
                $releases = [pscustomobject] @{
                    PSTypeName = 'CopyGitHubRepo.ReleaseMigrationResult'
                    SourceRepository = $archive.FullName
                    DestinationRepository = $verifiedDestination.FullName
                    ApprovedReleaseCount = @($releaseSelection.Releases).Count
                    DestinationReleaseCount = 0
                    Releases = @()
                    Unsupported = @()
                    IsSuccessful = $false
                    Status = 'SnapshotVerificationFailed'
                }
            }
            else {
                $releases = Invoke-CgrActivityStage -Name 'RestoreGitHubReleases' -Message 'Restore approved GitHub Releases and assets' -Action {
                    Copy-CgrApprovedGitHubRelease `
                        -SourceRepository $archive `
                        -DestinationRepository $verifiedDestination `
                        -ApprovedSelection $releaseSelection `
                        -DestinationTagTargets @($snapshot.ReleaseTags) `
                        -HostName $HostName
                }
                $releases | Add-Member -NotePropertyName Status -NotePropertyValue 'Restored' -Force
            }
            $completedSteps.Add([pscustomobject] @{
                    Order = $completedSteps.Count + 1
                    Name = 'RestoreGitHubReleases'
                    MutatedGitHub = [bool] $verification.IsSuccessful
                    Verified = $releases.IsSuccessful
                })
        }

        $configuration = Invoke-CgrPostVerificationConfigurationRestore `
            -Plan $Plan `
            -SourceRepository $archive `
            -DestinationRepository $verifiedDestination `
            -Verification $verification `
            -VerificationFailureReason 'SnapshotVerificationFailed' `
            -CompletedSteps $completedSteps `
            -FailureStage ([ref] $failureStage) `
            -HostName $HostName
        $settings = $configuration.Settings
        $protection = $configuration.Protection

        $sourceCommitSha = Get-CgrObjectProperty -InputObject $sourceState -Name 'CommitSha'
        $sourceTreeSha = Get-CgrObjectProperty -InputObject $sourceState -Name 'TreeSha'
        $snapshotTreeSha = Get-CgrObjectProperty -InputObject $snapshot -Name 'TreeSha'
        if ($null -eq $snapshotTreeSha) { $snapshotTreeSha = Get-CgrObjectProperty -InputObject $verification -Name 'DestinationTree' }
        if ($null -eq $snapshotTreeSha) { $snapshotTreeSha = Get-CgrObjectProperty -InputObject $verification -Name 'DestinationHeadTreeSha' }
        $archiveRepositoryNodeId = Get-CgrObjectProperty -InputObject $archive -Name 'NodeId'
        $destinationRepositoryNodeId = Get-CgrObjectProperty -InputObject $verifiedDestination -Name 'NodeId'
        $releasePreservation = Get-CgrSnapshotReleasePreservationEvidence `
            -Plan $Plan `
            -DestinationRepository $verifiedDestination `
            -SnapshotCopyResult $snapshot `
            -ReleaseRestoreResult $releases `
            -HostName $HostName
        $provenance = [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.SnapshotPublicationProvenance'
            RecordedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
            ContentMode = 'Snapshot'
            SourceRepository = $Plan.SourceRepository
            SourceRepositoryId = $repositoryIdentity.SourceRepositoryId
            SourceRepositoryNodeId = $sourceRepositoryNodeId
            SourceDefaultBranch = $Plan.SourceDefaultBranch
            SourceCommitSha = $sourceCommitSha
            SourceTreeSha = $sourceTreeSha
            PlannedSourceState = $sourceState
            CopiedSourceCommitSha = Get-CgrObjectProperty -InputObject $snapshot -Name 'SourceCommitSha'
            CopiedSourceTreeSha = Get-CgrObjectProperty -InputObject $snapshot -Name 'TreeSha'
            ArchiveRepository = $archive.FullName
            ArchiveRepositoryId = $repositoryIdentity.ArchiveRepositoryId
            ArchiveRepositoryNodeId = $archiveRepositoryNodeId
            DestinationRepository = $verifiedDestination.FullName
            DestinationRepositoryId = $repositoryIdentity.ReplacementRepositoryId
            DestinationRepositoryNodeId = $destinationRepositoryNodeId
            DestinationRootCommitSha = $snapshotRootCommitSha
            DestinationTreeSha = $snapshotTreeSha
            VerificationSuccessful = [bool] $verification.IsSuccessful
            ReleasePreservation = $releasePreservation
        }

        $releaseSuccessful = -not $includeReleases -or $releases.IsSuccessful
        $executionResult = [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.MigrationExecutionResult'
            SchemaVersion = 1
            Status = if (-not $verification.IsSuccessful) { 'SnapshotVerificationFailed' } elseif (-not $releaseSuccessful) { 'ReleaseRestoreFailed' } elseif ($Plan.SkipSettings) { 'SameNameSnapshotVerifiedSettingsSkipped' } elseif ($settings.IsSuccessful -and $protection.IsSuccessful) { 'SameNameReplacementCompleted' } elseif (-not $settings.IsSuccessful) { 'SettingsRestoreFailed' } else { 'ProtectionRestoreFailed' }
            SourceRepository = $Plan.SourceRepository
            ApprovedSourceState = $sourceState
            ActualCopiedSourceState = [pscustomobject] @{ CommitSha = Get-CgrObjectProperty -InputObject $snapshot -Name 'SourceCommitSha'; TreeSha = Get-CgrObjectProperty -InputObject $snapshot -Name 'TreeSha' }
            SourceRepositoryId = $repositoryIdentity.SourceRepositoryId
            SourceRepositoryNodeId = $sourceRepositoryNodeId
            OriginalRepository = $Plan.SourceRepository
            OriginalRepositoryId = $repositoryIdentity.SourceRepositoryId
            OriginalRepositoryNodeId = $sourceRepositoryNodeId
            ArchiveRepository = $archive.FullName
            ArchiveRepositoryId = $repositoryIdentity.ArchiveRepositoryId
            ArchiveRepositoryNodeId = $archiveRepositoryNodeId
            ArchivedOriginalIdentityPreserved = $repositoryIdentity.ArchiveRepositoryId -eq $repositoryIdentity.SourceRepositoryId
            DestinationRepository = $destination.FullName
            DestinationRepositoryId = $repositoryIdentity.ReplacementRepositoryId
            DestinationRepositoryNodeId = $destinationRepositoryNodeId
            ReplacementDestinationRepository = $destination.FullName
            ReplacementDestinationRepositoryId = $repositoryIdentity.ReplacementRepositoryId
            ReplacementDestinationRepositoryNodeId = $destinationRepositoryNodeId
            ReplacementHasDistinctIdentity = $repositoryIdentity.ReplacementRepositoryId -ne $repositoryIdentity.SourceRepositoryId
            SourceVisibility = $Plan.SourceVisibility
            DestinationVisibility = $Plan.DestinationVisibility
            DestinationHtmlUrl = $destination.HtmlUrl
            DestinationBranch = Get-CgrObjectProperty -InputObject $snapshot -Name 'BranchName'
            SnapshotCommitSha = Get-CgrObjectProperty -InputObject $snapshot -Name 'CommitSha'
            SourceTreeSha = $sourceTreeSha
            Provenance = $provenance
            IsVerified = $verification.IsSuccessful -and $releaseSuccessful
            Verification = $verification
            Releases = $releases
            Settings = $settings
            Protection = $protection
            Plan = $Plan
            CompletedSteps = @($completedSteps)
            StoppedBeforeSettingsRestore = -not $verification.IsSuccessful
            ReleasesRestored = [bool] ($includeReleases -and $releases.IsSuccessful)
            SettingsRestored = $configuration.SettingsRestored
            ProtectionRestored = $configuration.ProtectionRestored
        }

        if ($ReportPath) { $failureStage = 'WriteCompletionReport'; Write-CgrMigrationExecutionReport -Result $executionResult -Path $ReportPath | Out-Null }
        return $executionResult
    }
    catch {
        $recoveryReportPath = $null
        try {
            $recoveryDestination = if ($verifiedDestination) { $verifiedDestination } else { $destination }
            $releasePreservation = Get-CgrSnapshotReleasePreservationEvidence `
                -Plan $Plan `
                -DestinationRepository $recoveryDestination `
                -SnapshotCopyResult $snapshot `
                -ReleaseRestoreResult $releases `
                -HostName $HostName
            $recoveryReportPath = Write-CgrSameNameRecoveryReport -Plan $Plan -SourceRepositoryId $sourceRepositoryId -ArchiveRepository $archive -DestinationRepository $destination -FailureStage $failureStage -ErrorRecord $_ -CompletedSteps @($completedSteps) -SourceCommitSha $(if ($sourceState) { Get-CgrObjectProperty -InputObject $sourceState -Name 'CommitSha' } else { $null }) -SourceTreeSha $(if ($sourceState) { Get-CgrObjectProperty -InputObject $sourceState -Name 'TreeSha' } else { $null }) -DestinationRootCommitSha $snapshotRootCommitSha -DestinationTreeSha $(if ($snapshot) { Get-CgrObjectProperty -InputObject $snapshot -Name 'TreeSha' } else { $null }) -ReleasePreservation $releasePreservation -PreferredReportPath $ReportPath
        }
        catch { Write-Warning "Same-name replacement failed after mutation began, and the recovery report could not be written. Recovery reporting error: $($_.Exception.Message)" }
        if ($recoveryReportPath) { Write-Warning "Same-name replacement failed. Recovery report: $recoveryReportPath" }
        throw
    }
}
