function Invoke-CgrSameNameFullHistoryReplacement {
    <#
    .SYNOPSIS
    Replaces a repository at the same name while preserving its full Git history in an archive.

    .DESCRIPTION
    Validates the reviewed source state, archives the original repository, verifies
    immutable identity, creates the replacement, copies and verifies FullHistory,
    optionally restores the exact GitHub Releases approved during planning, then
    restores supported settings and protection. Partial failure preserves recovery
    evidence instead of automatically rolling repositories back.
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
    $copyResult = $null
    $repositoryIdentity = $null
    $sourceState = Get-CgrObjectProperty -InputObject $Plan -Name 'SourceState'
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
        $completedSteps.Add([pscustomobject] @{ Order = $completedSteps.Count + 1; Name = 'PreserveSourceAsArchive'; MutatedGitHub = $true; Verified = $true })

        $failureStage = 'VerifyArchivedSourceFullHistory'
        Assert-CgrApprovedSourceState -Repository $archive -SourceState $sourceState -AllowRepositoryNameChange | Out-Null
        $completedSteps.Add([pscustomobject] @{ Order = $completedSteps.Count + 1; Name = 'VerifyArchivedSourceFullHistory'; MutatedGitHub = $false; Verified = $true })

        $failureStage = 'CreateReplacementRepository'
        $destination = New-CgrGitHubRepository -Repository $Plan.DestinationRepository -Visibility $Plan.DestinationVisibility -HostName $HostName
        $completedSteps.Add([pscustomobject] @{ Order = $completedSteps.Count + 1; Name = 'CreateReplacementRepository'; MutatedGitHub = $true; Verified = $true })

        $failureStage = 'VerifyReplacementRepositoryIdentity'
        $repositoryIdentity = Assert-CgrReplacementRepositoryIdentity -SourceRepository $SourceRepository -ArchiveRepository $archive -ReplacementRepository $destination
        $completedSteps.Add([pscustomobject] @{ Order = $completedSteps.Count + 1; Name = 'VerifyReplacementRepositoryIdentity'; MutatedGitHub = $false; Verified = $true })

        $failureStage = 'CopyFullHistory'
        $copyResult = Copy-CgrRepositoryFullHistory -SourceRepository $archive -DestinationRepository $destination -HostName $HostName -ApprovedSourceState $sourceState
        $completedSteps.Add([pscustomobject] @{ Order = $completedSteps.Count + 1; Name = 'CopyFullHistory'; MutatedGitHub = $true; Verified = $copyResult.IsSuccessful })

        $failureStage = 'ReloadReplacement'
        $verifiedDestination = Get-CgrRepository -Repository $destination.FullName -HostName $HostName

        $failureStage = 'VerifyFullHistory'
        $verification = Invoke-CgrActivityStage -Name 'VerifyDestinationContent' -Message 'Verify destination content' -Action {
            Invoke-CgrApprovedFullHistoryVerification -SourceRepository $archive -DestinationRepository $verifiedDestination -ApprovedSourceState $sourceState
        }
        $completedSteps.Add([pscustomobject] @{ Order = $completedSteps.Count + 1; Name = 'VerifyFullHistory'; MutatedGitHub = $false; Verified = $verification.IsSuccessful })

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
                    Status = 'FullHistoryVerificationFailed'
                }
            }
            else {
                $releases = Invoke-CgrActivityStage -Name 'RestoreGitHubReleases' -Message 'Restore approved GitHub Releases and assets' -Action {
                    Copy-CgrApprovedGitHubRelease `
                        -SourceRepository $archive `
                        -DestinationRepository $verifiedDestination `
                        -ApprovedSelection $releaseSelection `
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
            -SourceRepository $SourceRepository `
            -DestinationRepository $verifiedDestination `
            -Verification $verification `
            -VerificationFailureReason 'FullHistoryVerificationFailed' `
            -CompletedSteps $completedSteps `
            -FailureStage ([ref] $failureStage) `
            -HostName $HostName
        $settings = $configuration.Settings
        $protection = $configuration.Protection

        $archiveRepositoryNodeId = Get-CgrObjectProperty -InputObject $archive -Name 'NodeId'
        $destinationRepositoryNodeId = Get-CgrObjectProperty -InputObject $verifiedDestination -Name 'NodeId'
        $copiedSourceEvidence = Get-CgrObjectProperty -InputObject $copyResult -Name 'CopiedSourceEvidence'
        $releaseSuccessful = -not $includeReleases -or $releases.IsSuccessful
        $executionResult = [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.MigrationExecutionResult'
            SchemaVersion = 1
            Status = if (-not $verification.IsSuccessful) { 'FullHistoryVerificationFailed' } elseif (-not $releaseSuccessful) { 'ReleaseRestoreFailed' } elseif ($Plan.SkipSettings) { 'SameNameFullHistoryVerifiedSettingsSkipped' } elseif ($settings.IsSuccessful -and $protection.IsSuccessful) { 'SameNameReplacementCompleted' } elseif (-not $settings.IsSuccessful) { 'SettingsRestoreFailed' } else { 'ProtectionRestoreFailed' }
            SourceRepository = $Plan.SourceRepository
            ApprovedSourceState = $sourceState
            ActualCopiedSourceState = $copiedSourceEvidence
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
            DestinationBranch = $copyResult.DefaultBranch
            SnapshotCommitSha = $null
            SourceFullHistoryRefCount = @($sourceState.Refs).Count
            SourceReachableCommitCount = $sourceState.ReachableCommitCount
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
            $recoveryReportPath = Write-CgrSameNameRecoveryReport `
                -Plan $Plan `
                -SourceRepositoryId $sourceRepositoryId `
                -ArchiveRepository $archive `
                -DestinationRepository $destination `
                -FailureStage $failureStage `
                -ErrorRecord $_ `
                -CompletedSteps @($completedSteps) `
                -SourceFullHistoryRefCount $(if ($sourceState) { @($sourceState.Refs).Count } else { $null }) `
                -SourceReachableCommitCount $(if ($sourceState) { $sourceState.ReachableCommitCount } else { $null }) `
                -PreferredReportPath $ReportPath
        }
        catch { Write-Warning "Same-name FullHistory replacement failed after mutation began, and the recovery report could not be written. Recovery reporting error: $($_.Exception.Message)" }
        if ($recoveryReportPath) { Write-Warning "Same-name FullHistory replacement failed. Recovery report: $recoveryReportPath" }
        throw
    }
}
