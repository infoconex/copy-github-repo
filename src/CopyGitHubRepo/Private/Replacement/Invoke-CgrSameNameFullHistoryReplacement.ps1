function Invoke-CgrSameNameFullHistoryReplacement {
    <#
    .SYNOPSIS
    Replaces a repository at the same name while preserving its full Git history in an archive.

    .DESCRIPTION
    Validates the reviewed source state, renames the original repository to its
    approved archive name, verifies that archived source evidence still matches,
    creates a fresh repository at the original name, proves the replacement has a
    distinct GitHub identity, copies FullHistory, verifies it, and only then restores
    supported settings and protection. Partial failure produces recovery evidence.

    .NOTES
    This is a destructive-name-change orchestration boundary. Exact user confirmation
    and ShouldProcess are completed by Copy-GitHubRepository before entry. The archive
    is intentionally preserved rather than deleted or overwritten.
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
    $sourceRepositoryId = Get-CgrObjectProperty -InputObject $SourceRepository -Name 'Id'
    $sourceRepositoryNodeId = Get-CgrObjectProperty -InputObject $SourceRepository -Name 'NodeId'
    $failureStage = 'ValidateApprovedSourceState'

    try {
        Assert-CgrApprovedSourceState -Repository $SourceRepository -SourceState $sourceState | Out-Null

        $failureStage = 'PreserveSourceAsArchive'
        $archive = Rename-CgrGitHubRepository -SourceRepository $SourceRepository -ArchiveRepository $Plan.ArchiveRepository -HostName $HostName
        $completedSteps.Add([pscustomobject] @{ Order = 1; Name = 'PreserveSourceAsArchive'; MutatedGitHub = $true; Verified = $true })

        $failureStage = 'VerifyArchivedSourceFullHistory'
        Assert-CgrApprovedSourceState -Repository $archive -SourceState $sourceState -AllowRepositoryNameChange | Out-Null
        $completedSteps.Add([pscustomobject] @{ Order = 2; Name = 'VerifyArchivedSourceFullHistory'; MutatedGitHub = $false; Verified = $true })

        $failureStage = 'CreateReplacementRepository'
        $destination = New-CgrGitHubRepository -Repository $Plan.DestinationRepository -Visibility $Plan.DestinationVisibility -HostName $HostName
        $completedSteps.Add([pscustomobject] @{ Order = 3; Name = 'CreateReplacementRepository'; MutatedGitHub = $true; Verified = $true })

        $failureStage = 'VerifyReplacementRepositoryIdentity'
        $repositoryIdentity = Assert-CgrReplacementRepositoryIdentity -SourceRepository $SourceRepository -ArchiveRepository $archive -ReplacementRepository $destination
        $completedSteps.Add([pscustomobject] @{ Order = 4; Name = 'VerifyReplacementRepositoryIdentity'; MutatedGitHub = $false; Verified = $true })

        $failureStage = 'CopyFullHistory'
        $copyResult = Copy-CgrRepositoryFullHistory -SourceRepository $archive -DestinationRepository $destination -HostName $HostName -ApprovedSourceState $sourceState
        $completedSteps.Add([pscustomobject] @{ Order = 5; Name = 'CopyFullHistory'; MutatedGitHub = $true; Verified = $copyResult.IsSuccessful })

        $failureStage = 'ReloadReplacement'
        $verifiedDestination = Get-CgrRepository -Repository $destination.FullName -HostName $HostName
        $failureStage = 'VerifyFullHistory'
        $verification = Invoke-CgrActivityStage -Name 'VerifyDestinationContent' -Message 'Verify destination content' -Action {
            Invoke-CgrApprovedFullHistoryVerification -SourceRepository $archive -DestinationRepository $verifiedDestination -ApprovedSourceState $sourceState
        }
        $completedSteps.Add([pscustomobject] @{ Order = 6; Name = 'VerifyFullHistory'; MutatedGitHub = $false; Verified = $verification.IsSuccessful })

        $failureStage = 'RestoreSupportedSettings'
        $settings = Invoke-CgrActivityStage -Name 'RestoreSupportedSettings' -Message 'Restore supported repository settings' -Action {
            if (-not $verification.IsSuccessful) {
                return [pscustomobject] @{ PSTypeName = 'CopyGitHubRepo.SettingsRestoreResult'; Repository = $destination.FullName; Restored = @(); Skipped = @('FullHistoryVerificationFailed'); Unsupported = @(); IsSuccessful = $false }
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
                return [pscustomobject] @{ PSTypeName = 'CopyGitHubRepo.RepositoryProtectionRestoreResult'; Repository = $destination.FullName; Status = 'Failed'; Restored = @(); Skipped = @('FullHistoryVerificationFailed'); IsSuccessful = $false; IsComplete = $false }
            }
            if ($Plan.SkipSettings) {
                return [pscustomobject] @{ PSTypeName = 'CopyGitHubRepo.RepositoryProtectionRestoreResult'; Repository = $destination.FullName; Status = 'Skipped'; Restored = @(); Skipped = @('AllSettings'); IsSuccessful = $true; IsComplete = $true }
            }
            if ($planProtection -and (Get-CgrObjectProperty -InputObject $planProtection -Name 'Status') -eq 'Captured') {
                return Set-CgrRepositoryProtectionConfiguration -SourceRepository $SourceRepository -DestinationRepository $verifiedDestination -SourceConfiguration (Get-CgrObjectProperty -InputObject $planProtection -Name 'Configuration') -HostName $HostName
            }
            Set-CgrRepositoryProtectionConfiguration -SourceRepository $SourceRepository -DestinationRepository $verifiedDestination -HostName $HostName
        }
        $completedSteps.Add([pscustomobject] @{ Order = 8; Name = 'RestoreRepositoryProtection'; MutatedGitHub = [bool] ($verification.IsSuccessful -and -not $Plan.SkipSettings); Verified = $protection.IsSuccessful })

        $archiveRepositoryNodeId = Get-CgrObjectProperty -InputObject $archive -Name 'NodeId'
        $destinationRepositoryNodeId = Get-CgrObjectProperty -InputObject $verifiedDestination -Name 'NodeId'
        $copiedSourceEvidence = Get-CgrObjectProperty -InputObject $copyResult -Name 'CopiedSourceEvidence'
        $executionResult = [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.MigrationExecutionResult'
            SchemaVersion = 1
            Status = if (-not $verification.IsSuccessful) { 'FullHistoryVerificationFailed' } elseif ($Plan.SkipSettings) { 'SameNameFullHistoryVerifiedSettingsSkipped' } elseif ($settings.IsSuccessful -and $protection.IsSuccessful) { 'SameNameReplacementCompleted' } elseif (-not $settings.IsSuccessful) { 'SettingsRestoreFailed' } else { 'ProtectionRestoreFailed' }
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
            $recoveryReportPath = Write-CgrSameNameRecoveryReport -Plan $Plan -SourceRepositoryId $sourceRepositoryId -ArchiveRepository $archive -DestinationRepository $destination -FailureStage $failureStage -ErrorRecord $_ -CompletedSteps @($completedSteps) -SourceFullHistoryRefCount $(if ($sourceState) { @($sourceState.Refs).Count } else { $null }) -SourceReachableCommitCount $(if ($sourceState) { $sourceState.ReachableCommitCount } else { $null }) -PreferredReportPath $ReportPath
        } catch { Write-Warning "Same-name FullHistory replacement failed after mutation began, and the recovery report could not be written. Recovery reporting error: $($_.Exception.Message)" }
        if ($recoveryReportPath) { Write-Warning "Same-name FullHistory replacement failed. Recovery report: $recoveryReportPath" }
        throw
    }
}
