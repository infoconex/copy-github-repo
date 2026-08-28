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
}
