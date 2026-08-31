function Invoke-CgrNewDestinationSnapshot {
    <#
    .SYNOPSIS
    Orchestrates verified Snapshot publication to a newly created destination.

    .DESCRIPTION
    Publishes the approved clean Snapshot, reloads and verifies destination content,
    optionally restores the exact GitHub Releases approved during planning against
    generated Snapshot release tags, then restores supported settings and protection.
    Configuration restoration is deliberately blocked after content-verification failure.

    .NOTES
    The destination repository exists before entry. Copy-GitHubRepository owns the
    public ShouldProcess decision; this layer owns mutation ordering, provenance,
    verification gating, and recovery reporting after mutation begins.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'The public Copy-GitHubRepository command performs ShouldProcess before calling this orchestration boundary.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $Plan,
        [Parameter(Mandatory)] [psobject] $SourceRepository,
        [Parameter(Mandatory)] [psobject] $DestinationRepository,
        [ValidateNotNullOrEmpty()] [string] $HostName = 'github.com',
        [string] $ReportPath
    )

    $completedSteps = [System.Collections.Generic.List[object]]::new()
    $completedSteps.Add([pscustomobject] @{ Order = 1; Name = 'CreateDestinationRepository'; MutatedGitHub = $true; Verified = $true })
    $failureStage = 'CopySnapshot'
    $snapshot = $null
    $snapshotRootCommitSha = $null
    $verifiedDestination = $null
    $sourceState = Get-CgrObjectProperty -InputObject $Plan -Name 'SourceState'
    $releaseCheckpointPlan = Get-CgrObjectProperty -InputObject $Plan -Name 'ReleaseCheckpointPlan'
    $includeReleases = [bool] (Get-CgrObjectProperty -InputObject $Plan -Name 'IncludeReleases')
    $releaseSelection = Get-CgrObjectProperty -InputObject $Plan -Name 'ReleaseSelection'
    $releases = [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.ReleaseMigrationResult'
        SourceRepository = $SourceRepository.FullName
        DestinationRepository = $DestinationRepository.FullName
        ApprovedReleaseCount = 0
        DestinationReleaseCount = 0
        Releases = @()
        Unsupported = @()
        IsSuccessful = $true
        Status = 'NotRequested'
    }

    try {
        $snapshot = @(Copy-CgrRepositorySnapshot -SourceRepository $SourceRepository -DestinationRepository $DestinationRepository -BranchName $Plan.SourceDefaultBranch -CommitMessage $Plan.CommitMessage -ApprovedSourceState $sourceState -ReleaseCheckpointPlan $releaseCheckpointPlan)[-1]
        $snapshotRootCommitSha = Get-CgrObjectProperty -InputObject $snapshot -Name 'RootCommitSha'
        if ($null -eq $snapshotRootCommitSha) { $snapshotRootCommitSha = Get-CgrObjectProperty -InputObject $snapshot -Name 'CommitSha' }
        $completedSteps.Add([pscustomobject] @{ Order = 2; Name = 'CopySnapshot'; MutatedGitHub = $true; Verified = $snapshot.Verified })

        $failureStage = 'ReloadDestination'
        $verifiedDestination = Get-CgrRepository -Repository $DestinationRepository.FullName -HostName $HostName

        $failureStage = 'VerifySnapshot'
        $verification = Invoke-CgrActivityStage -Name 'VerifyDestinationContent' -Message 'Verify destination content' -Action {
            if ($releaseCheckpointPlan) {
                Invoke-CgrApprovedSnapshotReleaseVerification `
                    -SourceRepository $SourceRepository `
                    -DestinationRepository $verifiedDestination `
                    -ReleaseCheckpointPlan $releaseCheckpointPlan
            }
            else {
                Invoke-CgrRepositorySnapshotVerification `
                    -SourceRepository $SourceRepository `
                    -DestinationRepository $verifiedDestination `
                    -ApprovedSourceState $sourceState
            }
        }
        $completedSteps.Add([pscustomobject] @{ Order = 3; Name = 'VerifySnapshot'; MutatedGitHub = $false; Verified = $verification.IsSuccessful })

        if ($includeReleases) {
            $failureStage = 'RestoreGitHubReleases'
            if (-not $verification.IsSuccessful) {
                $releases = [pscustomobject] @{
                    PSTypeName = 'CopyGitHubRepo.ReleaseMigrationResult'
                    SourceRepository = $SourceRepository.FullName
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
                        -SourceRepository $SourceRepository `
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
            -SourceRepository $SourceRepository `
            -DestinationRepository $verifiedDestination `
            -Verification $verification `
            -VerificationFailureReason 'SnapshotVerificationFailed' `
            -CompletedSteps $completedSteps `
            -FailureStage ([ref] $failureStage) `
            -HostName $HostName
        $settings = $configuration.Settings
        $protection = $configuration.Protection

        $snapshotSourceCommit = if ($sourceState) { Get-CgrObjectProperty -InputObject $sourceState -Name 'CommitSha' } else { Get-CgrObjectProperty -InputObject $snapshot -Name 'SourceCommitSha' }
        $snapshotTree = if ($sourceState) { Get-CgrObjectProperty -InputObject $sourceState -Name 'TreeSha' } else { Get-CgrObjectProperty -InputObject $snapshot -Name 'TreeSha' }
        if ($null -eq $snapshotTree) { $snapshotTree = Get-CgrObjectProperty -InputObject $verification -Name 'SourceTree' }
        $destinationTree = Get-CgrObjectProperty -InputObject $verification -Name 'DestinationTree'
        if ($null -eq $destinationTree) { $destinationTree = Get-CgrObjectProperty -InputObject $verification -Name 'DestinationHeadTreeSha' }
        if ($null -eq $destinationTree) { $destinationTree = $snapshotTree }

        $provenance = [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.SnapshotPublicationProvenance'
            RecordedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
            ContentMode = 'Snapshot'
            SourceRepository = $Plan.SourceRepository
            SourceRepositoryId = if ($sourceState) { Get-CgrObjectProperty -InputObject $sourceState -Name 'RepositoryId' } else { Get-CgrObjectProperty -InputObject $SourceRepository -Name 'Id' }
            SourceRepositoryNodeId = if ($sourceState) { Get-CgrObjectProperty -InputObject $sourceState -Name 'RepositoryNodeId' } else { Get-CgrObjectProperty -InputObject $SourceRepository -Name 'NodeId' }
            SourceDefaultBranch = $Plan.SourceDefaultBranch
            SourceCommitSha = $snapshotSourceCommit
            SourceTreeSha = $snapshotTree
            PlannedSourceState = $sourceState
            CopiedSourceCommitSha = Get-CgrObjectProperty -InputObject $snapshot -Name 'SourceCommitSha'
            CopiedSourceTreeSha = Get-CgrObjectProperty -InputObject $snapshot -Name 'TreeSha'
            DestinationRepository = $verifiedDestination.FullName
            DestinationRepositoryId = Get-CgrObjectProperty -InputObject $verifiedDestination -Name 'Id'
            DestinationRepositoryNodeId = Get-CgrObjectProperty -InputObject $verifiedDestination -Name 'NodeId'
            DestinationRootCommitSha = $snapshotRootCommitSha
            DestinationTreeSha = $destinationTree
            VerificationSuccessful = [bool] $verification.IsSuccessful
        }

        $releaseSuccessful = -not $includeReleases -or $releases.IsSuccessful
        $executionResult = [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.MigrationExecutionResult'; SchemaVersion = 1
            Status = if (-not $verification.IsSuccessful) { 'SnapshotVerificationFailed' } elseif (-not $releaseSuccessful) { 'ReleaseRestoreFailed' } elseif ($Plan.SkipSettings) { 'SnapshotVerifiedSettingsSkipped' } elseif ($settings.IsSuccessful -and $protection.IsSuccessful) { 'CompletedWithSupportedSettings' } elseif (-not $settings.IsSuccessful) { 'SettingsRestoreFailed' } else { 'ProtectionRestoreFailed' }
            SourceRepository = $Plan.SourceRepository; ApprovedSourceState = $sourceState; DestinationRepository = $DestinationRepository.FullName
            SourceVisibility = $Plan.SourceVisibility; DestinationVisibility = $Plan.DestinationVisibility; DestinationHtmlUrl = $DestinationRepository.HtmlUrl
            DestinationBranch = Get-CgrObjectProperty -InputObject $snapshot -Name 'BranchName'; SnapshotCommitSha = Get-CgrObjectProperty -InputObject $snapshot -Name 'CommitSha'; SourceTreeSha = $snapshotTree
            Provenance = $provenance; IsVerified = $verification.IsSuccessful -and $releaseSuccessful; Verification = $verification; Releases = $releases; Settings = $settings; Protection = $protection; Plan = $Plan; CompletedSteps = @($completedSteps)
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
            $recoveryProvenance = [pscustomobject] @{
                ContentMode = 'Snapshot'; SourceRepository = $Plan.SourceRepository
                SourceRepositoryId = if ($sourceState) { Get-CgrObjectProperty -InputObject $sourceState -Name 'RepositoryId' } else { Get-CgrObjectProperty -InputObject $SourceRepository -Name 'Id' }
                SourceRepositoryNodeId = if ($sourceState) { Get-CgrObjectProperty -InputObject $sourceState -Name 'RepositoryNodeId' } else { Get-CgrObjectProperty -InputObject $SourceRepository -Name 'NodeId' }
                SourceDefaultBranch = $Plan.SourceDefaultBranch
                SourceCommitSha = if ($sourceState) { Get-CgrObjectProperty -InputObject $sourceState -Name 'CommitSha' } elseif ($snapshot) { Get-CgrObjectProperty -InputObject $snapshot -Name 'SourceCommitSha' } else { $null }
                SourceTreeSha = if ($sourceState) { Get-CgrObjectProperty -InputObject $sourceState -Name 'TreeSha' } elseif ($snapshot) { Get-CgrObjectProperty -InputObject $snapshot -Name 'TreeSha' } else { $null }
                PlannedSourceState = $sourceState
                DestinationRepository = $DestinationRepository.FullName
                DestinationRepositoryId = if ($verifiedDestination) { Get-CgrObjectProperty -InputObject $verifiedDestination -Name 'Id' } else { Get-CgrObjectProperty -InputObject $DestinationRepository -Name 'Id' }
                DestinationRepositoryNodeId = if ($verifiedDestination) { Get-CgrObjectProperty -InputObject $verifiedDestination -Name 'NodeId' } else { Get-CgrObjectProperty -InputObject $DestinationRepository -Name 'NodeId' }
                DestinationRootCommitSha = $snapshotRootCommitSha
                DestinationTreeSha = if ($snapshot) { Get-CgrObjectProperty -InputObject $snapshot -Name 'TreeSha' } else { $null }
            }
            $recoveryReportPath = Write-CgrMigrationRecoveryReport -Plan $Plan -DestinationRepository $DestinationRepository -FailureStage $failureStage -ErrorRecord $_ -CompletedSteps @($completedSteps) -Provenance $recoveryProvenance -PreferredReportPath $ReportPath
        }
        catch { Write-Warning "Migration failed after destination creation, and the recovery report could not be written. Recovery reporting error: $($_.Exception.Message)" }
        if ($recoveryReportPath) { Write-Warning "Migration failed after destination creation. Recovery report: $recoveryReportPath" }
        throw
    }
}
