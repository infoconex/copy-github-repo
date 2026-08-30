function Invoke-CgrPostVerificationConfigurationRestore {
    <#
    .SYNOPSIS
    Restores supported repository configuration after content verification.

    .DESCRIPTION
    Centralizes the shared execution contract for supported repository settings and
    repository protection restoration. Content-mode orchestrators retain ownership of
    copy, verification, release, final result, and recovery sequencing. This boundary
    records each completed configuration stage so recovery evidence remains precise.
    Planned repository-protection evidence remains authoritative when present.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'The calling migration orchestrator has already passed the public ShouldProcess boundary.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $Plan,
        [Parameter(Mandatory)] [psobject] $SourceRepository,
        [Parameter(Mandatory)] [psobject] $DestinationRepository,
        [Parameter(Mandatory)] [psobject] $Verification,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $VerificationFailureReason,
        [Parameter(Mandatory)] [System.Collections.IList] $CompletedSteps,
        [Parameter(Mandatory)] [ref] $FailureStage,
        [ValidateNotNullOrEmpty()] [string] $HostName = 'github.com'
    )

    # PSScriptAnalyzer does not count closure-only parameter references as usage.
    $sourceRepositoryForRestore = $SourceRepository
    $destinationRepositoryForRestore = $DestinationRepository
    $verificationFailureReasonForRestore = $VerificationFailureReason
    $hostNameForRestore = $HostName

    $FailureStage.Value = 'RestoreSupportedSettings'
    $settings = Invoke-CgrActivityStage -Name 'RestoreSupportedSettings' -Message 'Restore supported repository settings' -Action {
        if (-not $Verification.IsSuccessful) {
            return [pscustomobject] @{
                PSTypeName = 'CopyGitHubRepo.SettingsRestoreResult'
                Repository = $destinationRepositoryForRestore.FullName
                Restored = @()
                Skipped = @($verificationFailureReasonForRestore)
                Unsupported = @()
                IsSuccessful = $false
            }
        }
        if ($Plan.SkipSettings) {
            return [pscustomobject] @{
                PSTypeName = 'CopyGitHubRepo.SettingsRestoreResult'
                Repository = $destinationRepositoryForRestore.FullName
                Restored = @()
                Skipped = @('AllSettings')
                Unsupported = @()
                IsSuccessful = $true
            }
        }

        Set-CgrGitHubRepositorySetting `
            -SourceRepository $sourceRepositoryForRestore `
            -DestinationRepository $destinationRepositoryForRestore `
            -HostName $hostNameForRestore
    }
    $CompletedSteps.Add([pscustomobject] @{
            Order = $CompletedSteps.Count + 1
            Name = 'RestoreSupportedSettings'
            MutatedGitHub = -not $Plan.SkipSettings
            Verified = $settings.IsSuccessful
        })

    $FailureStage.Value = 'RestoreRepositoryProtection'
    $planProtectionProperty = $Plan.PSObject.Properties['Protection']
    $planProtection = if ($null -ne $planProtectionProperty) { $planProtectionProperty.Value } else { $null }
    $protection = Invoke-CgrActivityStage -Name 'RestoreRepositoryProtection' -Message 'Restore transferable repository protection' -Action {
        if (-not $Verification.IsSuccessful) {
            return [pscustomobject] @{
                PSTypeName = 'CopyGitHubRepo.RepositoryProtectionRestoreResult'
                Repository = $destinationRepositoryForRestore.FullName
                Status = 'Failed'
                Restored = @()
                Skipped = @($verificationFailureReasonForRestore)
                IsSuccessful = $false
                IsComplete = $false
            }
        }
        if ($Plan.SkipSettings) {
            return [pscustomobject] @{
                PSTypeName = 'CopyGitHubRepo.RepositoryProtectionRestoreResult'
                Repository = $destinationRepositoryForRestore.FullName
                Status = 'Skipped'
                Restored = @()
                Skipped = @('AllSettings')
                IsSuccessful = $true
                IsComplete = $true
            }
        }
        if ($null -eq $planProtectionProperty) {
            return Set-CgrRepositoryProtectionConfiguration `
                -SourceRepository $sourceRepositoryForRestore `
                -DestinationRepository $destinationRepositoryForRestore `
                -HostName $hostNameForRestore
        }
        if ((Get-CgrObjectProperty -InputObject $planProtection -Name 'Status') -eq 'Captured') {
            return Set-CgrRepositoryProtectionConfiguration `
                -SourceRepository $sourceRepositoryForRestore `
                -DestinationRepository $destinationRepositoryForRestore `
                -SourceConfiguration (Get-CgrObjectProperty -InputObject $planProtection -Name 'Configuration') `
                -HostName $hostNameForRestore
        }

        $planningStatus = [string] (Get-CgrObjectProperty -InputObject $planProtection -Name 'Status')
        if ([string]::IsNullOrWhiteSpace($planningStatus)) {
            $planningStatus = 'Invalid'
        }
        [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.RepositoryProtectionRestoreResult'
            Repository = $destinationRepositoryForRestore.FullName
            Status = 'Unsupported'
            Restored = @()
            Skipped = @("ProtectionPlanning:$planningStatus")
            IsSuccessful = $true
            IsComplete = $false
        }
    }
    $CompletedSteps.Add([pscustomobject] @{
            Order = $CompletedSteps.Count + 1
            Name = 'RestoreRepositoryProtection'
            MutatedGitHub = [bool] ($Verification.IsSuccessful -and -not $Plan.SkipSettings)
            Verified = $protection.IsSuccessful
        })

    $settingsRestored = [bool] ($Verification.IsSuccessful -and -not $Plan.SkipSettings -and $settings.IsSuccessful)
    $protectionRestored = [bool] ($Verification.IsSuccessful -and -not $Plan.SkipSettings -and $protection.IsSuccessful -and $protection.IsComplete)

    [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.PostVerificationConfigurationRestoreResult'
        Settings = $settings
        Protection = $protection
        SettingsRestored = $settingsRestored
        ProtectionRestored = $protectionRestored
        IsSuccessful = [bool] ($settings.IsSuccessful -and $protection.IsSuccessful)
        IsComplete = [bool] ($settings.IsSuccessful -and $protection.IsSuccessful -and $protection.IsComplete)
    }
}
