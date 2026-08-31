BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1') -Force
}

Describe 'Post-verification configuration restoration' {
    It 'restores settings and exact captured protection evidence in order' {
        InModuleScope CopyGitHubRepo {
            $plannedConfiguration = [pscustomobject] @{ Rulesets = @([pscustomobject] @{ Name = 'planned' }) }
            $plan = [pscustomobject] @{
                SkipSettings = $false
                Protection = [pscustomobject] @{ Status = 'Captured'; Configuration = $plannedConfiguration }
            }
            $source = [pscustomobject] @{ FullName = 'acme/source' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination' }
            $verification = [pscustomobject] @{ IsSuccessful = $true }
            $steps = [System.Collections.Generic.List[object]]::new()
            $failureStage = 'VerifySnapshot'

            Mock Set-CgrGitHubRepositorySetting {
                [pscustomobject] @{ Repository = $destination.FullName; Restored = @('Description'); Skipped = @(); Unsupported = @(); IsSuccessful = $true }
            }
            Mock Set-CgrRepositoryProtectionConfiguration {
                [pscustomobject] @{ Repository = $destination.FullName; Status = 'Restored'; Restored = @('Ruleset:planned'); Skipped = @(); IsSuccessful = $true; IsComplete = $true }
            }

            $result = Invoke-CgrPostVerificationConfigurationRestore `
                -Plan $plan `
                -SourceRepository $source `
                -DestinationRepository $destination `
                -Verification $verification `
                -VerificationFailureReason 'SnapshotVerificationFailed' `
                -CompletedSteps $steps `
                -FailureStage ([ref] $failureStage)

            $result.PSTypeNames | Should -Contain 'CopyGitHubRepo.PostVerificationConfigurationRestoreResult'
            $result.SettingsRestored | Should -BeTrue
            $result.ProtectionRestored | Should -BeTrue
            $result.IsSuccessful | Should -BeTrue
            $result.IsComplete | Should -BeTrue
            @($steps.Name) | Should -Be @('RestoreSupportedSettings', 'RestoreRepositoryProtection')
            @($steps.Order) | Should -Be @(1, 2)
            $failureStage | Should -Be 'RestoreRepositoryProtection'
            Should -Invoke Set-CgrRepositoryProtectionConfiguration -Times 1 -Exactly -ParameterFilter {
                $SourceConfiguration -eq $plannedConfiguration
            }
        }
    }

    It 'blocks both restoration stages when content verification failed' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{ SkipSettings = $false; Protection = [pscustomobject] @{ Status = 'Captured'; Configuration = [pscustomobject] @{} } }
            $source = [pscustomobject] @{ FullName = 'acme/source' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination' }
            $verification = [pscustomobject] @{ IsSuccessful = $false }
            $steps = [System.Collections.Generic.List[object]]::new()
            $failureStage = 'VerifySnapshot'

            Mock Set-CgrGitHubRepositorySetting { throw 'must not run' }
            Mock Set-CgrRepositoryProtectionConfiguration { throw 'must not run' }

            $result = Invoke-CgrPostVerificationConfigurationRestore -Plan $plan -SourceRepository $source -DestinationRepository $destination -Verification $verification -VerificationFailureReason 'SnapshotVerificationFailed' -CompletedSteps $steps -FailureStage ([ref] $failureStage)

            $result.Settings.Skipped | Should -Contain 'SnapshotVerificationFailed'
            $result.Protection.Skipped | Should -Contain 'SnapshotVerificationFailed'
            $result.IsSuccessful | Should -BeFalse
            $result.IsComplete | Should -BeFalse
            Should -Invoke Set-CgrGitHubRepositorySetting -Times 0 -Exactly
            Should -Invoke Set-CgrRepositoryProtectionConfiguration -Times 0 -Exactly
        }
    }

    It 'preserves SkipSettings as a complete deliberate skip' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{ SkipSettings = $true; Protection = [pscustomobject] @{ Status = 'Captured'; Configuration = [pscustomobject] @{} } }
            $source = [pscustomobject] @{ FullName = 'acme/source' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination' }
            $verification = [pscustomobject] @{ IsSuccessful = $true }
            $steps = [System.Collections.Generic.List[object]]::new()
            $failureStage = 'VerifySnapshot'

            Mock Set-CgrGitHubRepositorySetting { throw 'must not run' }
            Mock Set-CgrRepositoryProtectionConfiguration { throw 'must not run' }

            $result = Invoke-CgrPostVerificationConfigurationRestore -Plan $plan -SourceRepository $source -DestinationRepository $destination -Verification $verification -VerificationFailureReason 'SnapshotVerificationFailed' -CompletedSteps $steps -FailureStage ([ref] $failureStage)

            $result.Settings.Skipped | Should -Contain 'AllSettings'
            $result.Protection.Skipped | Should -Contain 'AllSettings'
            $result.IsSuccessful | Should -BeTrue
            $result.IsComplete | Should -BeTrue
            $result.SettingsRestored | Should -BeFalse
            $result.ProtectionRestored | Should -BeFalse
            @($steps.MutatedGitHub) | Should -Be @($false, $false)
        }
    }

    It 'treats explicit non-captured protection planning evidence as authoritative' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{ SkipSettings = $false; Protection = [pscustomobject] @{ Status = 'SkippedSourceIdentityUnavailable'; Configuration = $null } }
            $source = [pscustomobject] @{ FullName = 'acme/source' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination' }
            $verification = [pscustomobject] @{ IsSuccessful = $true }
            $steps = [System.Collections.Generic.List[object]]::new()
            $failureStage = 'VerifyFullHistory'

            Mock Set-CgrGitHubRepositorySetting { [pscustomobject] @{ Repository = $destination.FullName; Restored = @(); Skipped = @(); Unsupported = @(); IsSuccessful = $true } }
            Mock Set-CgrRepositoryProtectionConfiguration { throw 'must not rediscover protection' }

            $result = Invoke-CgrPostVerificationConfigurationRestore -Plan $plan -SourceRepository $source -DestinationRepository $destination -Verification $verification -VerificationFailureReason 'FullHistoryVerificationFailed' -CompletedSteps $steps -FailureStage ([ref] $failureStage)

            $result.Protection.Status | Should -Be 'Unsupported'
            $result.Protection.Skipped | Should -Contain 'ProtectionPlanning:SkippedSourceIdentityUnavailable'
            $result.ProtectionRestored | Should -BeFalse
            $result.IsComplete | Should -BeFalse
            Should -Invoke Set-CgrRepositoryProtectionConfiguration -Times 0 -Exactly
        }
    }

    It 'uses legacy protection discovery only when the Protection property is absent' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{ SkipSettings = $false }
            $source = [pscustomobject] @{ FullName = 'acme/source' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination' }
            $verification = [pscustomobject] @{ IsSuccessful = $true }
            $steps = [System.Collections.Generic.List[object]]::new()
            $failureStage = 'VerifySnapshot'

            Mock Set-CgrGitHubRepositorySetting { [pscustomobject] @{ Repository = $destination.FullName; Restored = @(); Skipped = @(); Unsupported = @(); IsSuccessful = $true } }
            Mock Set-CgrRepositoryProtectionConfiguration { [pscustomobject] @{ Repository = $destination.FullName; Status = 'NotApplicable'; Restored = @(); Skipped = @(); IsSuccessful = $true; IsComplete = $true } }

            $result = Invoke-CgrPostVerificationConfigurationRestore -Plan $plan -SourceRepository $source -DestinationRepository $destination -Verification $verification -VerificationFailureReason 'SnapshotVerificationFailed' -CompletedSteps $steps -FailureStage ([ref] $failureStage)

            $result.Protection.Status | Should -Be 'NotApplicable'
            $result.ProtectionRestored | Should -BeTrue
            Should -Invoke Set-CgrRepositoryProtectionConfiguration -Times 1 -Exactly -ParameterFilter {
                -not $PSBoundParameters.ContainsKey('SourceConfiguration')
            }
        }
    }

    It 'preserves settings completion evidence when protection restoration throws' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{ SkipSettings = $false }
            $source = [pscustomobject] @{ FullName = 'acme/source' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination' }
            $verification = [pscustomobject] @{ IsSuccessful = $true }
            $steps = [System.Collections.Generic.List[object]]::new()
            $failureStage = 'VerifySnapshot'

            Mock Set-CgrGitHubRepositorySetting { [pscustomobject] @{ Repository = $destination.FullName; Restored = @(); Skipped = @(); Unsupported = @(); IsSuccessful = $true } }
            Mock Set-CgrRepositoryProtectionConfiguration { throw 'protection failure' }

            { Invoke-CgrPostVerificationConfigurationRestore -Plan $plan -SourceRepository $source -DestinationRepository $destination -Verification $verification -VerificationFailureReason 'SnapshotVerificationFailed' -CompletedSteps $steps -FailureStage ([ref] $failureStage) } | Should -Throw

            $failureStage | Should -Be 'RestoreRepositoryProtection'
            @($steps.Name) | Should -Be @('RestoreSupportedSettings')
        }
    }
}
