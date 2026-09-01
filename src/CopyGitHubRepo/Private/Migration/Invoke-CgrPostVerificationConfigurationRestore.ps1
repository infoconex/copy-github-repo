function Invoke-CgrPostVerificationConfigurationRestore {
    <#
    .SYNOPSIS
    Restores supported repository configuration after content verification.

    .DESCRIPTION
    Centralizes the shared execution contract for supported repository settings,
    reviewed GitHub Pages configuration, and repository protection restoration.
    Content-mode orchestrators retain ownership of copy, initial content verification,
    release restoration, final result, and recovery sequencing. For Snapshot release
    preservation this boundary performs the required independent post-release
    destination verification before any configuration mutation. Planned Pages,
    repository-protection, and release evidence remain authoritative.
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

    $contentMode = [string] (Get-CgrObjectProperty -InputObject $Plan -Name 'ContentMode')
    $includeReleases = [bool] (Get-CgrObjectProperty -InputObject $Plan -Name 'IncludeReleases')
    $restorePages = [bool] (Get-CgrObjectProperty -InputObject $Plan -Name 'RestorePages')
    if ($contentMode -eq 'Snapshot' -and $includeReleases -and $Verification.IsSuccessful) {
        $approvedSelection = Get-CgrObjectProperty -InputObject $Plan -Name 'ReleaseSelection'
        $destinationTagTargets = @(Get-CgrObjectProperty -InputObject $Verification -Name 'ReleaseTags')
        $FailureStage.Value = 'VerifyGitHubReleases'
        $releaseVerification = Invoke-CgrActivityStage -Name 'VerifyGitHubReleases' -Message 'Verify recreated GitHub Releases and assets' -Action {
            Test-CgrGitHubReleaseMigration `
                -SourceRepository $sourceRepositoryForRestore `
                -DestinationRepository $destinationRepositoryForRestore `
                -ApprovedSelection $approvedSelection `
                -DestinationTagTargets $destinationTagTargets `
                -RequireExactDestinationReleaseSet `
                -HostName $hostNameForRestore
        }
        $gitContentSuccessful = [bool] $Verification.IsSuccessful
        $Verification | Add-Member -NotePropertyName GitContentSuccessful -NotePropertyValue $gitContentSuccessful -Force
        $Verification | Add-Member -NotePropertyName ReleaseVerification -NotePropertyValue $releaseVerification -Force
        $Verification | Add-Member -NotePropertyName ReleasesVerified -NotePropertyValue ([bool] $releaseVerification.IsSuccessful) -Force
        $Verification | Add-Member -NotePropertyName IsSuccessful -NotePropertyValue ([bool] ($gitContentSuccessful -and $releaseVerification.IsSuccessful)) -Force
        $CompletedSteps.Add([pscustomobject] @{
                Order = $CompletedSteps.Count + 1
                Name = 'VerifyGitHubReleases'
                MutatedGitHub = $false
                Verified = [bool] $releaseVerification.IsSuccessful
            })
    }

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
            MutatedGitHub = [bool] ($Verification.IsSuccessful -and -not $Plan.SkipSettings)
            Verified = $settings.IsSuccessful
        })

    $pages = [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.PagesRestoreResult'
        Repository = $destinationRepositoryForRestore.FullName
        Status = 'NotRequested'
        Configured = $false
        Restored = $false
        Verified = $false
        GuardReleased = $false
        IsSuccessful = $true
        IsComplete = $true
    }

    if ($restorePages) {
        $FailureStage.Value = 'RestoreGitHubPages'
        $pages = Invoke-CgrActivityStage -Name 'RestoreGitHubPages' -Message 'Restore reviewed GitHub Pages configuration' -Action {
            if (-not $Verification.IsSuccessful) {
                return [pscustomobject] @{
                    PSTypeName = 'CopyGitHubRepo.PagesRestoreResult'
                    Repository = $destinationRepositoryForRestore.FullName
                    Status = 'ContentVerificationFailed'
                    Configured = $false
                    Restored = $false
                    Verified = $false
                    GuardReleased = $false
                    IsSuccessful = $false
                    IsComplete = $false
                }
            }
            if (-not $settings.IsSuccessful) {
                return [pscustomobject] @{
                    PSTypeName = 'CopyGitHubRepo.PagesRestoreResult'
                    Repository = $destinationRepositoryForRestore.FullName
                    Status = 'SettingsRestoreFailed'
                    Configured = $false
                    Restored = $false
                    Verified = $false
                    GuardReleased = $false
                    IsSuccessful = $false
                    IsComplete = $false
                }
            }

            $pagesSourceRepository = $sourceRepositoryForRestore
            $mode = [string] (Get-CgrObjectProperty -InputObject $Plan -Name 'Mode')
            $archiveRepository = [string] (Get-CgrObjectProperty -InputObject $Plan -Name 'ArchiveRepository')
            if ($mode -eq 'SameNameReplacement' -and
                $sourceRepositoryForRestore.FullName -eq (Get-CgrObjectProperty -InputObject $Plan -Name 'SourceRepository') -and
                -not [string]::IsNullOrWhiteSpace($archiveRepository)) {
                $pagesSourceRepository = [pscustomobject] @{ FullName = $archiveRepository }
            }

            Restore-CgrGitHubPagesConfiguration `
                -Plan $Plan `
                -SourceRepository $pagesSourceRepository `
                -DestinationRepository $destinationRepositoryForRestore `
                -HostName $hostNameForRestore
        }
        $Verification | Add-Member -NotePropertyName Pages -NotePropertyValue $pages -Force
        $CompletedSteps.Add([pscustomobject] @{
                Order = $CompletedSteps.Count + 1
                Name = 'RestoreGitHubPages'
                MutatedGitHub = [bool] ($Verification.IsSuccessful -and $settings.IsSuccessful -and $pages.Restored)
                Verified = [bool] $pages.Verified
            })
    }

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
        if ($restorePages -and -not $pages.IsSuccessful) {
            return [pscustomobject] @{
                PSTypeName = 'CopyGitHubRepo.RepositoryProtectionRestoreResult'
                Repository = $destinationRepositoryForRestore.FullName
                Status = 'Failed'
                Restored = @()
                Skipped = @('PagesRestoreFailed')
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
            MutatedGitHub = [bool] ($Verification.IsSuccessful -and (-not $restorePages -or $pages.IsSuccessful) -and -not $Plan.SkipSettings)
            Verified = $protection.IsSuccessful
        })

    $settingsRestored = [bool] ($Verification.IsSuccessful -and -not $Plan.SkipSettings -and $settings.IsSuccessful)
    $pagesRestored = [bool] ($restorePages -and $Verification.IsSuccessful -and $pages.Restored -and $pages.Verified -and $pages.GuardReleased)
    $protectionRestored = [bool] ($Verification.IsSuccessful -and (-not $restorePages -or $pages.IsSuccessful) -and -not $Plan.SkipSettings -and $protection.IsSuccessful -and $protection.IsComplete)

    [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.PostVerificationConfigurationRestoreResult'
        Settings = $settings
        Pages = $pages
        Protection = $protection
        SettingsRestored = $settingsRestored
        PagesRestored = $pagesRestored
        ProtectionRestored = $protectionRestored
        IsSuccessful = [bool] ($settings.IsSuccessful -and $pages.IsSuccessful -and $protection.IsSuccessful)
        IsComplete = [bool] ($settings.IsSuccessful -and $pages.IsComplete -and $protection.IsSuccessful -and $protection.IsComplete)
    }
}
