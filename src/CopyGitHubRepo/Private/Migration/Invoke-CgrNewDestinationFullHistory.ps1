function Invoke-CgrNewDestinationFullHistory {
    <#
    .SYNOPSIS
    Orchestrates verified FullHistory publication to a newly created destination.

    .DESCRIPTION
    Copies approved history, reloads and verifies the destination, optionally
    restores the exact GitHub Releases approved during planning, then restores
    supported settings and protection. Release restoration never runs before
    FullHistory verification succeeds.

    .NOTES
    The destination repository has already been created when this function begins.
    Public ShouldProcess consent is owned by Copy-GitHubRepository; this boundary
    owns fail-safe sequencing and recovery reporting after mutation has started.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'The public Copy-GitHubRepository command performs ShouldProcess before calling this orchestration boundary.')]
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
    $failureStage = 'CopyFullHistory'
    $sourceState = Get-CgrObjectProperty -InputObject $Plan -Name 'SourceState'
    $copyResult = $null
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
        $copyResult = Copy-CgrRepositoryFullHistory -SourceRepository $SourceRepository -DestinationRepository $DestinationRepository -HostName $HostName -ApprovedSourceState $sourceState
        $completedSteps.Add([pscustomobject] @{ Order = $completedSteps.Count + 1; Name = 'CopyFullHistory'; MutatedGitHub = $true; Verified = $copyResult.IsSuccessful })

        $failureStage = 'ReloadDestination'
        $verifiedDestination = Get-CgrRepository -Repository $DestinationRepository.FullName -HostName $HostName

        $failureStage = 'VerifyFullHistory'
        $verification = Invoke-CgrActivityStage -Name 'VerifyDestinationContent' -Message 'Verify destination content' -Action {
            if ($sourceState) {
                return Invoke-CgrApprovedFullHistoryVerification -SourceRepository $SourceRepository -DestinationRepository $verifiedDestination -ApprovedSourceState $sourceState
            }
            Invoke-CgrRepositoryFullHistoryVerification -SourceRepository $SourceRepository -DestinationRepository $verifiedDestination
        }
        $completedSteps.Add([pscustomobject] @{ Order = $completedSteps.Count + 1; Name = 'VerifyFullHistory'; MutatedGitHub = $false; Verified = $verification.IsSuccessful })

        if ($Plan.IncludeReleases) {
            $failureStage = 'RestoreGitHubReleases'
            if (-not $verification.IsSuccessful) {
                $releases = [pscustomobject] @{
                    PSTypeName = 'CopyGitHubRepo.ReleaseMigrationResult'
                    SourceRepository = $SourceRepository.FullName
                    DestinationRepository = $verifiedDestination.FullName
                    ApprovedReleaseCount = @($Plan.ReleaseSelection.Releases).Count
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
                        -SourceRepository $SourceRepository `
                        -DestinationRepository $verifiedDestination `
                        -ApprovedSelection $Plan.ReleaseSelection `
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

        $failureStage = 'RestoreSupportedSettings'
        $settings = Invoke-CgrActivityStage -Name 'RestoreSupportedSettings' -Message 'Restore supported repository settings' -Action {
            if (-not $verification.IsSuccessful) {
                return [pscustomobject] @{ PSTypeName = 'CopyGitHubRepo.SettingsRestoreResult'; Repository = $DestinationRepository.FullName; Restored = @(); Skipped = @('FullHistoryVerificationFailed'); Unsupported = @(); IsSuccessful = $false }
            }
            if ($Plan.SkipSettings) {
                return [pscustomobject] @{ PSTypeName = 'CopyGitHubRepo.SettingsRestoreResult'; Repository = $DestinationRepository.FullName; Restored = @(); Skipped = @('AllSettings'); Unsupported = @(); IsSuccessful = $true }
            }
            Set-CgrGitHubRepositorySetting -SourceRepository $SourceRepository -DestinationRepository $verifiedDestination -HostName $HostName
        }
        $completedSteps.Add([pscustomobject] @{ Order = $completedSteps.Count + 1; Name = 'RestoreSupportedSettings'; MutatedGitHub = -not $Plan.SkipSettings; Verified = $settings.IsSuccessful })

        $failureStage = 'RestoreRepositoryProtection'
        $planProtection = Get-CgrObjectProperty -InputObject $Plan -Name 'Protection'
        $protection = Invoke-CgrActivityStage -Name 'RestoreRepositoryProtection' -Message 'Restore transferable repository protection' -Action {
            if (-not $verification.IsSuccessful) {
                return [pscustomobject] @{ PSTypeName = 'CopyGitHubRepo.RepositoryProtectionRestoreResult'; Repository = $DestinationRepository.FullName; Status = 'Failed'; Restored = @(); Skipped = @('FullHistoryVerificationFailed'); IsSuccessful = $false; IsComplete = $false }
            }
            if ($Plan.SkipSettings) {
                return [pscustomobject] @{ PSTypeName = 'CopyGitHubRepo.RepositoryProtectionRestoreResult'; Repository = $DestinationRepository.FullName; Status = 'Skipped'; Restored = @(); Skipped = @('AllSettings'); IsSuccessful = $true; IsComplete = $true }
            }
            if ($planProtection -and (Get-CgrObjectProperty -InputObject $planProtection -Name 'Status') -eq 'Captured') {
                return Set-CgrRepositoryProtectionConfiguration -SourceRepository $SourceRepository -DestinationRepository $verifiedDestination -SourceConfiguration (Get-CgrObjectProperty -InputObject $planProtection -Name 'Configuration') -HostName $HostName
            }
            Set-CgrRepositoryProtectionConfiguration -SourceRepository $SourceRepository -DestinationRepository $verifiedDestination -HostName $HostName
        }
        $completedSteps.Add([pscustomobject] @{ Order = $completedSteps.Count + 1; Name = 'RestoreRepositoryProtection'; MutatedGitHub = [bool] ($verification.IsSuccessful -and -not $Plan.SkipSettings); Verified = $protection.IsSuccessful })

        $copiedSourceEvidence = Get-CgrObjectProperty -InputObject $copyResult -Name 'CopiedSourceEvidence'
        $releaseSuccessful = -not $Plan.IncludeReleases -or $releases.IsSuccessful
        $executionResult = [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.MigrationExecutionResult'
            SchemaVersion = 1
            Status = if (-not $verification.IsSuccessful) { 'FullHistoryVerificationFailed' } elseif (-not $releaseSuccessful) { 'ReleaseRestoreFailed' } elseif ($Plan.SkipSettings) { 'FullHistoryVerifiedSettingsSkipped' } elseif ($settings.IsSuccessful -and $protection.IsSuccessful) { 'CompletedWithSupportedSettings' } elseif (-not $settings.IsSuccessful) { 'SettingsRestoreFailed' } else { 'ProtectionRestoreFailed' }
            SourceRepository = $Plan.SourceRepository
            ApprovedSourceState = $sourceState
            ActualCopiedSourceState = $copiedSourceEvidence
            DestinationRepository = $DestinationRepository.FullName
            SourceVisibility = $Plan.SourceVisibility
            DestinationVisibility = $Plan.DestinationVisibility
            DestinationHtmlUrl = $DestinationRepository.HtmlUrl
            DestinationBranch = $copyResult.DefaultBranch
            SnapshotCommitSha = $null
            IsVerified = $verification.IsSuccessful -and $releaseSuccessful
            Verification = $verification
            Releases = $releases
            Settings = $settings
            Protection = $protection
            Plan = $Plan
            CompletedSteps = @($completedSteps)
            StoppedBeforeSettingsRestore = -not $verification.IsSuccessful
            ReleasesRestored = [bool] ($Plan.IncludeReleases -and $releases.IsSuccessful)
            SettingsRestored = [bool] ($verification.IsSuccessful -and -not $Plan.SkipSettings -and $settings.IsSuccessful)
            ProtectionRestored = [bool] ($verification.IsSuccessful -and -not $Plan.SkipSettings -and $protection.IsSuccessful -and $protection.IsComplete)
        }

        if ($ReportPath) {
            $failureStage = 'WriteCompletionReport'
            Write-CgrMigrationExecutionReport -Result $executionResult -Path $ReportPath | Out-Null
        }
        return $executionResult
    }
    catch {
        $recoveryReportPath = $null
        try {
            $recoveryProvenance = [pscustomobject] @{
                ContentMode = 'FullHistory'
                PlannedSourceState = $sourceState
                PlannedReleaseSelection = Get-CgrObjectProperty -InputObject $Plan -Name 'ReleaseSelection'
                ReleaseRestoreResult = $releases
                ActualCopiedSourceState = if ($copyResult) { Get-CgrObjectProperty -InputObject $copyResult -Name 'CopiedSourceEvidence' } else { $null }
            }
            $recoveryReportPath = Write-CgrMigrationRecoveryReport -Plan $Plan -DestinationRepository $DestinationRepository -FailureStage $failureStage -ErrorRecord $_ -CompletedSteps @($completedSteps) -Provenance $recoveryProvenance -PreferredReportPath $ReportPath
        }
        catch { Write-Warning "FullHistory copy failed after destination creation, and the recovery report could not be written. Recovery reporting error: $($_.Exception.Message)" }
        if ($recoveryReportPath) { Write-Warning "FullHistory copy failed after destination creation. Recovery report: $recoveryReportPath" }
        throw
    }
}
