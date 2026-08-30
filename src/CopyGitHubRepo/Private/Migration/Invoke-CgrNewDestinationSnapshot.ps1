function Invoke-CgrNewDestinationSnapshot {
    <#
    .SYNOPSIS
    Orchestrates verified Snapshot publication to a newly created destination.

    .DESCRIPTION
    Publishes the approved clean Snapshot, reloads and verifies destination content,
    restores supported settings and protection only after verification, records
    provenance, and emits recovery evidence when a later stage fails. Configuration
    restoration is deliberately blocked after content-verification failure.

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
    $verifiedDestination = $null
    $sourceState = Get-CgrObjectProperty -InputObject $Plan -Name 'SourceState'

    try {
        $snapshot = @(Copy-CgrRepositorySnapshot -SourceRepository $SourceRepository -DestinationRepository $DestinationRepository -BranchName $Plan.SourceDefaultBranch -CommitMessage $Plan.CommitMessage -ApprovedSourceState $sourceState)[-1]
        $completedSteps.Add([pscustomobject] @{ Order = 2; Name = 'CopySnapshot'; MutatedGitHub = $true; Verified = $snapshot.Verified })

        $failureStage = 'ReloadDestination'
        $verifiedDestination = Get-CgrRepository -Repository $DestinationRepository.FullName -HostName $HostName

        $failureStage = 'VerifySnapshot'
        $verification = Invoke-CgrActivityStage -Name 'VerifyDestinationContent' -Message 'Verify destination content' -Action {
            Invoke-CgrRepositorySnapshotVerification -SourceRepository $SourceRepository -DestinationRepository $verifiedDestination -ApprovedSourceState $sourceState
        }
        $completedSteps.Add([pscustomobject] @{ Order = 3; Name = 'VerifySnapshot'; MutatedGitHub = $false; Verified = $verification.IsSuccessful })

        $failureStage = 'RestoreSupportedSettings'
        $settings = Invoke-CgrActivityStage -Name 'RestoreSupportedSettings' -Message 'Restore supported repository settings' -Action {
            if (-not $verification.IsSuccessful) {
                return [pscustomobject] @{ PSTypeName = 'CopyGitHubRepo.SettingsRestoreResult'; Repository = $DestinationRepository.FullName; Restored = @(); Skipped = @('SnapshotVerificationFailed'); Unsupported = @(); IsSuccessful = $false }
            }
            if ($Plan.SkipSettings) {
                return [pscustomobject] @{ PSTypeName = 'CopyGitHubRepo.SettingsRestoreResult'; Repository = $DestinationRepository.FullName; Restored = @(); Skipped = @('AllSettings'); Unsupported = @(); IsSuccessful = $true }
            }
            Set-CgrGitHubRepositorySetting -SourceRepository $SourceRepository -DestinationRepository $verifiedDestination -HostName $HostName
        }
        $completedSteps.Add([pscustomobject] @{ Order = 4; Name = 'RestoreSupportedSettings'; MutatedGitHub = -not $Plan.SkipSettings; Verified = $settings.IsSuccessful })

        $failureStage = 'RestoreRepositoryProtection'
        $planProtectionProperty = $Plan.PSObject.Properties['Protection']
        $planProtection = if ($null -ne $planProtectionProperty) { $planProtectionProperty.Value } else { $null }
        $protection = Invoke-CgrActivityStage -Name 'RestoreRepositoryProtection' -Message 'Restore transferable repository protection' -Action {
            if (-not $verification.IsSuccessful) {
                return [pscustomobject] @{ PSTypeName = 'CopyGitHubRepo.RepositoryProtectionRestoreResult'; Repository = $DestinationRepository.FullName; Status = 'Failed'; Restored = @(); Skipped = @('SnapshotVerificationFailed'); IsSuccessful = $false; IsComplete = $false }
            }
            if ($Plan.SkipSettings) {
                return [pscustomobject] @{ PSTypeName = 'CopyGitHubRepo.RepositoryProtectionRestoreResult'; Repository = $DestinationRepository.FullName; Status = 'Skipped'; Restored = @(); Skipped = @('AllSettings'); IsSuccessful = $true; IsComplete = $true }
            }
            if ($null -eq $planProtectionProperty) {
                return Set-CgrRepositoryProtectionConfiguration -SourceRepository $SourceRepository -DestinationRepository $verifiedDestination -HostName $HostName
            }
            if ((Get-CgrObjectProperty -InputObject $planProtection -Name 'Status') -eq 'Captured') {
                return Set-CgrRepositoryProtectionConfiguration -SourceRepository $SourceRepository -DestinationRepository $verifiedDestination -SourceConfiguration (Get-CgrObjectProperty -InputObject $planProtection -Name 'Configuration') -HostName $HostName
            }

            $planningStatus = [string] (Get-CgrObjectProperty -InputObject $planProtection -Name 'Status')
            if ([string]::IsNullOrWhiteSpace($planningStatus)) { $planningStatus = 'Invalid' }
            [pscustomobject] @{ PSTypeName = 'CopyGitHubRepo.RepositoryProtectionRestoreResult'; Repository = $DestinationRepository.FullName; Status = 'Unsupported'; Restored = @(); Skipped = @("ProtectionPlanning:$planningStatus"); IsSuccessful = $true; IsComplete = $false }
        }
        $completedSteps.Add([pscustomobject] @{ Order = 5; Name = 'RestoreRepositoryProtection'; MutatedGitHub = [bool] ($verification.IsSuccessful -and -not $Plan.SkipSettings); Verified = $protection.IsSuccessful })

        $snapshotSourceCommit = if ($sourceState) { Get-CgrObjectProperty -InputObject $sourceState -Name 'CommitSha' } else { Get-CgrObjectProperty -InputObject $snapshot -Name 'SourceCommitSha' }
        $snapshotTree = if ($sourceState) { Get-CgrObjectProperty -InputObject $sourceState -Name 'TreeSha' } else { Get-CgrObjectProperty -InputObject $snapshot -Name 'TreeSha' }
        if ($null -eq $snapshotTree) { $snapshotTree = Get-CgrObjectProperty -InputObject $verification -Name 'SourceTree' }
        $destinationTree = Get-CgrObjectProperty -InputObject $verification -Name 'DestinationTree'
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
            DestinationRootCommitSha = Get-CgrObjectProperty -InputObject $snapshot -Name 'CommitSha'
            DestinationTreeSha = $destinationTree
            VerificationSuccessful = [bool] $verification.IsSuccessful
        }

        $executionResult = [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.MigrationExecutionResult'; SchemaVersion = 1
            Status = if (-not $verification.IsSuccessful) { 'SnapshotVerificationFailed' } elseif ($Plan.SkipSettings) { 'SnapshotVerifiedSettingsSkipped' } elseif ($settings.IsSuccessful -and $protection.IsSuccessful) { 'CompletedWithSupportedSettings' } elseif (-not $settings.IsSuccessful) { 'SettingsRestoreFailed' } else { 'ProtectionRestoreFailed' }
            SourceRepository = $Plan.SourceRepository; ApprovedSourceState = $sourceState; DestinationRepository = $DestinationRepository.FullName
            SourceVisibility = $Plan.SourceVisibility; DestinationVisibility = $Plan.DestinationVisibility; DestinationHtmlUrl = $DestinationRepository.HtmlUrl
            DestinationBranch = Get-CgrObjectProperty -InputObject $snapshot -Name 'BranchName'; SnapshotCommitSha = Get-CgrObjectProperty -InputObject $snapshot -Name 'CommitSha'; SourceTreeSha = $snapshotTree
            Provenance = $provenance; IsVerified = $verification.IsSuccessful; Verification = $verification; Settings = $settings; Protection = $protection; Plan = $Plan; CompletedSteps = @($completedSteps)
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
                DestinationRootCommitSha = if ($snapshot) { Get-CgrObjectProperty -InputObject $snapshot -Name 'CommitSha' } else { $null }
                DestinationTreeSha = if ($snapshot) { Get-CgrObjectProperty -InputObject $snapshot -Name 'TreeSha' } else { $null }
            }
            $recoveryReportPath = Write-CgrMigrationRecoveryReport -Plan $Plan -DestinationRepository $DestinationRepository -FailureStage $failureStage -ErrorRecord $_ -CompletedSteps @($completedSteps) -Provenance $recoveryProvenance -PreferredReportPath $ReportPath
        }
        catch { Write-Warning "Migration failed after destination creation, and the recovery report could not be written. Recovery reporting error: $($_.Exception.Message)" }
        if ($recoveryReportPath) { Write-Warning "Migration failed after destination creation. Recovery report: $recoveryReportPath" }
        throw
    }
}
