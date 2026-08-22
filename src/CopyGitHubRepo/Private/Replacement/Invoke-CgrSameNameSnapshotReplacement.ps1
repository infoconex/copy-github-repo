function Invoke-CgrSameNameSnapshotReplacement {
    <#
    .SYNOPSIS
    Replaces a repository at the same name with a clean Snapshot while preserving the original as an archive.

    .DESCRIPTION
    Revalidates approved source evidence, renames the original repository to the
    reviewed archive name, verifies the archived source, creates a fresh repository
    at the original name, proves distinct replacement identity, publishes and
    verifies the clean Snapshot, then restores supported settings and protection.
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
    $repositoryIdentity = $null
    $sourceState = Get-CgrObjectProperty -InputObject $Plan -Name 'SourceState'
    $sourceRepositoryId = Get-CgrObjectProperty -InputObject $SourceRepository -Name 'Id'
    $sourceRepositoryNodeId = Get-CgrObjectProperty -InputObject $SourceRepository -Name 'NodeId'
    $failureStage = 'ValidateApprovedSourceState'

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
        $snapshot = @(Copy-CgrRepositorySnapshot -SourceRepository $archive -DestinationRepository $destination -BranchName $Plan.SourceDefaultBranch -CommitMessage $Plan.CommitMessage -ApprovedSourceState $sourceState)[-1]
        $completedSteps.Add([pscustomobject] @{ Order = 5; Name = 'CopySnapshot'; MutatedGitHub = $true; Verified = $snapshot.Verified })

        $failureStage = 'ReloadReplacement'
        $verifiedDestination = Get-CgrRepository -Repository $destination.FullName -HostName $HostName
        $failureStage = 'VerifySnapshot'
        $verification = Invoke-CgrActivityStage -Name 'VerifyDestinationContent' -Message 'Verify destination content' -Action {
            Invoke-CgrRepositorySnapshotVerification -SourceRepository $archive -DestinationRepository $verifiedDestination -ApprovedSourceState $sourceState
        }
        $completedSteps.Add([pscustomobject] @{ Order = 6; Name = 'VerifySnapshot'; MutatedGitHub = $false; Verified = $verification.IsSuccessful })

        $failureStage = 'RestoreSupportedSettings'
        $settings = Invoke-CgrActivityStage -Name 'RestoreSupportedSettings' -Message 'Restore supported repository settings' -Action {
            if (-not $verification.IsSuccessful) {
                return [pscustomobject] @{ PSTypeName = 'CopyGitHubRepo.SettingsRestoreResult'; Repository = $destination.FullName; Restored = @(); Skipped = @('SnapshotVerificationFailed'); Unsupported = @(); IsSuccessful = $false }
            }
            if ($Plan.SkipSettings) {
                return [pscustomobject] @{ PSTypeName = 'CopyGitHubRepo.SettingsRestoreResult'; Repository = $destination.FullName; Restored = @(); Skipped = @('AllSettings'); Unsupported = @(); IsSuccessful = $true }
            }
            Set-CgrGitHubRepositorySetting -SourceRepository $SourceRepository -DestinationRepository $verifiedDestination -HostName $HostName
        }
        $completedSteps.Add([pscustomobject] @{ Order = 7; Name = 'RestoreSupportedSettings'; MutatedGitHub = -not $Plan.SkipSettings; Verified = $settings.IsSuccessful })

        $failureStage = 'RestoreRepositoryProtection'
        $planProtection = Get-CgrObjectProperty -InputObject $Plan -Name 'Protection'
        $protection = Invoke-CgrActivityStage -Name 'RestoreRepositoryProtection' -Message 'Restore transferable repository protection' -Action {
            if (-not $verification.IsSuccessful) {
                return [pscustomobject] @{ PSTypeName = 'CopyGitHubRepo.RepositoryProtectionRestoreResult'; Repository = $destination.FullName; Status = 'Failed'; Restored = @(); Skipped = @('SnapshotVerificationFailed'); IsSuccessful = $false; IsComplete = $false }
            }
            if ($Plan.SkipSettings) {
                return [pscustomobject] @{ PSTypeName = 'CopyGitHubRepo.RepositoryProtectionRestoreResult'; Repository = $destination.FullName; Status = 'Skipped'; Restored = @(); Skipped = @('AllSettings'); IsSuccessful = $true; IsComplete = $true }
            }
            if ($null -eq $planProtection) {
                return Set-CgrRepositoryProtectionConfiguration -SourceRepository $SourceRepository -DestinationRepository $verifiedDestination -HostName $HostName
            }
            if ((Get-CgrObjectProperty -InputObject $planProtection -Name 'Status') -eq 'Captured') {
                return Set-CgrRepositoryProtectionConfiguration -SourceRepository $SourceRepository -DestinationRepository $verifiedDestination -SourceConfiguration (Get-CgrObjectProperty -InputObject $planProtection -Name 'Configuration') -HostName $HostName
            }

            $planningStatus = [string] (Get-CgrObjectProperty -InputObject $planProtection -Name 'Status')
            [pscustomobject] @{ PSTypeName = 'CopyGitHubRepo.RepositoryProtectionRestoreResult'; Repository = $destination.FullName; Status = 'Unsupported'; Restored = @(); Skipped = @("ProtectionPlanning:$planningStatus"); IsSuccessful = $true; IsComplete = $false }
        }
        $completedSteps.Add([pscustomobject] @{ Order = 8; Name = 'RestoreRepositoryProtection'; MutatedGitHub = [bool] ($verification.IsSuccessful -and -not $Plan.SkipSettings); Verified = $protection.IsSuccessful })

        $sourceCommitSha = Get-CgrObjectProperty -InputObject $sourceState -Name 'CommitSha'
        $sourceTreeSha = Get-CgrObjectProperty -InputObject $sourceState -Name 'TreeSha'
        $snapshotTreeSha = Get-CgrObjectProperty -InputObject $snapshot -Name 'TreeSha'
        if ($null -eq $snapshotTreeSha) { $snapshotTreeSha = Get-CgrObjectProperty -InputObject $verification -Name 'DestinationTree' }
        $archiveRepositoryNodeId = Get-CgrObjectProperty -InputObject $archive -Name 'NodeId'
        $destinationRepositoryNodeId = Get-CgrObjectProperty -InputObject $verifiedDestination -Name 'NodeId'
        $provenance = [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.SnapshotPublicationProvenance'
            RecordedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
            ContentMode = 'Snapshot'
            SourceRepository = $Plan.SourceRepository
            SourceRepositoryId = $repositoryIdentity.SourceRepositoryId
            SourceRepositoryNodeId = $sourceRepositoryNodeId
            SourceDefaultBranch = Get-CgrObjectProperty -InputObject $sourceState -Name 'DefaultBranch'
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
            DestinationRootCommitSha = Get-CgrObjectProperty -InputObject $snapshot -Name 'CommitSha'
            DestinationTreeSha = $snapshotTreeSha
            VerificationSuccessful = [bool] $verification.IsSuccessful
        }

        $executionResult = [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.MigrationExecutionResult'
            SchemaVersion = 1
            Status = if (-not $verification.IsSuccessful) { 'SnapshotVerificationFailed' } elseif ($Plan.SkipSettings) { 'SameNameSnapshotVerifiedSettingsSkipped' } elseif ($settings.IsSuccessful -and $protection.IsSuccessful) { 'SameNameReplacementCompleted' } elseif (-not $settings.IsSuccessful) { 'SettingsRestoreFailed' } else { 'ProtectionRestoreFailed' }
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
            IsVerified = $verification.IsSuccessful
            Verification = $verification
            Settings = $settings
            Protection = $protection
            Plan = $Plan
            CompletedSteps = @($completedSteps)
            StoppedBeforeSettingsRestore = -not $verification.IsSuccessful
            SettingsRestored = [bool] ($verification.IsSuccessful -and -not $Plan.SkipSettings -and $settings.IsSuccessful)
            ProtectionRestored = [bool] ($verification.IsSuccessful -and -not $Plan.SkipSettings -and $protection.IsSuccessful -and $protection.IsComplete)
        }

        if ($ReportPath) { $failureStage = 'WriteCompletionReport'; Write-CgrMigrationExecutionReport -Result $executionResult -Path $ReportPath | Out-Null }
        return $executionResult
    }
    catch {
        $recoveryReportPath = $null
        try {
            $recoveryReportPath = Write-CgrSameNameRecoveryReport -Plan $Plan -SourceRepositoryId $sourceRepositoryId -ArchiveRepository $archive -DestinationRepository $destination -FailureStage $failureStage -ErrorRecord $_ -CompletedSteps @($completedSteps) -SourceCommitSha $(if ($sourceState) { Get-CgrObjectProperty -InputObject $sourceState -Name 'CommitSha' } else { $null }) -SourceTreeSha $(if ($sourceState) { Get-CgrObjectProperty -InputObject $sourceState -Name 'TreeSha' } else { $null }) -DestinationRootCommitSha $(if ($snapshot) { Get-CgrObjectProperty -InputObject $snapshot -Name 'CommitSha' } else { $null }) -DestinationTreeSha $(if ($snapshot) { Get-CgrObjectProperty -InputObject $snapshot -Name 'TreeSha' } else { $null }) -PreferredReportPath $ReportPath
        }
        catch { Write-Warning "Same-name replacement failed after mutation began, and the recovery report could not be written. Recovery reporting error: $($_.Exception.Message)" }
        if ($recoveryReportPath) { Write-Warning "Same-name replacement failed. Recovery report: $recoveryReportPath" }
        throw
    }
}
