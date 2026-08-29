BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'FullHistory release orchestration' {
    It 'restores approved releases only after successful FullHistory verification' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                SourceState = [pscustomobject] @{ Refs = @(); ReachableCommitCount = 1 }
                IncludeReleases = $true
                ReleaseSelection = [pscustomobject] @{ Releases = @([pscustomobject] @{ TagName = 'v1.0.0' }) }
                SkipSettings = $true
                Protection = $null
            }
            $source = [pscustomobject] @{ FullName = 'acme/source'; HostName = 'github.com' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination'; HtmlUrl = 'https://github.com/acme/destination' }

            Mock Copy-CgrRepositoryFullHistory {
                [pscustomobject] @{ IsSuccessful = $true; DefaultBranch = 'main'; CopiedSourceEvidence = $plan.SourceState }
            }
            Mock Get-CgrRepository { $destination }
            Mock Invoke-CgrApprovedFullHistoryVerification {
                [pscustomobject] @{ IsSuccessful = $true }
            }
            Mock Copy-CgrApprovedGitHubRelease {
                [pscustomobject] @{
                    IsSuccessful = $true
                    ApprovedReleaseCount = 1
                    DestinationReleaseCount = 1
                    Releases = @([pscustomobject] @{ TagName = 'v1.0.0'; IsVerified = $true })
                    Unsupported = @()
                }
            }
            Mock Set-CgrGitHubRepositorySetting {}
            Mock Set-CgrRepositoryProtectionConfiguration {}

            $result = Invoke-CgrNewDestinationFullHistory -Plan $plan -SourceRepository $source -DestinationRepository $destination

            $result.IsVerified | Should -BeTrue
            $result.ReleasesRestored | Should -BeTrue
            $result.Releases.DestinationReleaseCount | Should -Be 1
            @($result.CompletedSteps.Name) | Should -Contain 'VerifyFullHistory'
            @($result.CompletedSteps.Name) | Should -Contain 'RestoreGitHubReleases'
            [array]::IndexOf(@($result.CompletedSteps.Name), 'VerifyFullHistory') |
                Should -BeLessThan ([array]::IndexOf(@($result.CompletedSteps.Name), 'RestoreGitHubReleases'))
            Should -Invoke Copy-CgrApprovedGitHubRelease -Times 1
        }
    }

    It 'does not invoke release restoration when releases were not requested' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                SourceState = [pscustomobject] @{ Refs = @(); ReachableCommitCount = 1 }
                IncludeReleases = $false
                ReleaseSelection = $null
                SkipSettings = $true
                Protection = $null
            }
            $source = [pscustomobject] @{ FullName = 'acme/source'; HostName = 'github.com' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination'; HtmlUrl = 'https://github.com/acme/destination' }

            Mock Copy-CgrRepositoryFullHistory {
                [pscustomobject] @{ IsSuccessful = $true; DefaultBranch = 'main'; CopiedSourceEvidence = $plan.SourceState }
            }
            Mock Get-CgrRepository { $destination }
            Mock Invoke-CgrApprovedFullHistoryVerification { [pscustomobject] @{ IsSuccessful = $true } }
            Mock Copy-CgrApprovedGitHubRelease { throw 'should not run' }

            $result = Invoke-CgrNewDestinationFullHistory -Plan $plan -SourceRepository $source -DestinationRepository $destination

            $result.IsVerified | Should -BeTrue
            $result.Releases.Status | Should -Be 'NotRequested'
            $result.ReleasesRestored | Should -BeFalse
            Should -Invoke Copy-CgrApprovedGitHubRelease -Times 0
        }
    }

    It 'does not restore same-name releases when FullHistory verification fails' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                DestinationRepository = 'acme/source'
                ArchiveRepository = 'acme/source-archive'
                SourceState = [pscustomobject] @{ Refs = @(); ReachableCommitCount = 1 }
                IncludeReleases = $true
                ReleaseSelection = [pscustomobject] @{ Releases = @([pscustomobject] @{ TagName = 'v1.0.0' }) }
                SkipSettings = $true
                Protection = $null
            }
            $source = [pscustomobject] @{
                FullName = 'acme/source'
                HostName = 'github.com'
                Id = 10
                NodeId = 'SRC'
            }
            $archive = [pscustomobject] @{
                FullName = 'acme/source-archive'
                HostName = 'github.com'
                Id = 10
                NodeId = 'SRC'
            }
            $destination = [pscustomobject] @{
                FullName = 'acme/source'
                HostName = 'github.com'
                HtmlUrl = 'https://github.com/acme/source'
                Id = 20
                NodeId = 'DST'
            }

            Mock Assert-CgrApprovedSourceState {}
            Mock Rename-CgrGitHubRepository { $archive }
            Mock New-CgrGitHubRepository { $destination }
            Mock Assert-CgrReplacementRepositoryIdentity {
                [pscustomobject] @{
                    SourceRepositoryId = 10
                    ArchiveRepositoryId = 10
                    ReplacementRepositoryId = 20
                }
            }
            Mock Copy-CgrRepositoryFullHistory {
                [pscustomobject] @{ IsSuccessful = $true; DefaultBranch = 'main'; CopiedSourceEvidence = $plan.SourceState }
            }
            Mock Get-CgrRepository { $destination }
            Mock Invoke-CgrApprovedFullHistoryVerification { [pscustomobject] @{ IsSuccessful = $false } }
            Mock Copy-CgrApprovedGitHubRelease { throw 'release restoration must not run' }

            $result = Invoke-CgrSameNameFullHistoryReplacement -Plan $plan -SourceRepository $source

            $result.IsVerified | Should -BeFalse
            $result.ReleasesRestored | Should -BeFalse
            $result.Releases.Status | Should -Be 'FullHistoryVerificationFailed'
            $result.StoppedBeforeSettingsRestore | Should -BeTrue
            @($result.CompletedSteps | Where-Object Name -eq 'RestoreGitHubReleases')[0].MutatedGitHub | Should -BeFalse
            @($result.CompletedSteps | Where-Object Name -eq 'RestoreGitHubReleases')[0].Verified | Should -BeFalse
            Should -Invoke Copy-CgrApprovedGitHubRelease -Times 0
        }
    }

    It 'records release selection evidence when release restoration fails after content verification' {
        InModuleScope CopyGitHubRepo {
            $releaseSelection = [pscustomobject] @{
                SelectedReleaseCount = 2
                Releases = @(
                    [pscustomobject] @{ TagName = 'v1.0.0' },
                    [pscustomobject] @{ TagName = 'v1.1.0' }
                )
            }
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                SourceState = [pscustomobject] @{ Refs = @(); ReachableCommitCount = 1 }
                IncludeReleases = $true
                ReleaseSelection = $releaseSelection
                SkipSettings = $true
                Protection = $null
            }
            $source = [pscustomobject] @{ FullName = 'acme/source'; HostName = 'github.com' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination'; HtmlUrl = 'https://github.com/acme/destination' }
            $script:recoveryFailureStage = $null
            $script:recoveryProvenance = $null

            Mock Copy-CgrRepositoryFullHistory {
                [pscustomobject] @{ IsSuccessful = $true; DefaultBranch = 'main'; CopiedSourceEvidence = $plan.SourceState }
            }
            Mock Get-CgrRepository { $destination }
            Mock Invoke-CgrApprovedFullHistoryVerification { [pscustomobject] @{ IsSuccessful = $true } }
            Mock Copy-CgrApprovedGitHubRelease { throw 'simulated second-release failure' }
            Mock Write-CgrMigrationRecoveryReport {
                $script:recoveryFailureStage = $FailureStage
                $script:recoveryProvenance = $Provenance
                'release-recovery.json'
            }

            { Invoke-CgrNewDestinationFullHistory -Plan $plan -SourceRepository $source -DestinationRepository $destination } |
                Should -Throw '*simulated second-release failure*'

            $script:recoveryFailureStage | Should -Be 'RestoreGitHubReleases'
            $script:recoveryProvenance.PlannedReleaseSelection | Should -Be $releaseSelection
            $script:recoveryProvenance.PlannedSourceState | Should -Be $plan.SourceState
            Should -Invoke Write-CgrMigrationRecoveryReport -Times 1 -Exactly -ParameterFilter {
                $FailureStage -eq 'RestoreGitHubReleases' -and
                $Provenance.PlannedReleaseSelection -eq $releaseSelection
            }
        }
    }
}
