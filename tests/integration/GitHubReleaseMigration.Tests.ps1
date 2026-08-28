BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'GitHub Release migration planning' {
    It 'captures the exact approved release inventory and adds a restore step' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{
                FullName = 'acme/source'
                Owner = 'acme'
                Visibility = 'private'
                DefaultBranch = 'main'
                Id = 101
            }

            Mock ConvertTo-CgrRepositoryName { param($Repository) [string] $Repository }
            Mock Test-CgrGitHubRepositoryExistence { $false }
            Mock Get-CgrRepositoryProtectionConfiguration {
                [pscustomobject] @{ Rulesets = @(); BranchProtection = $null; Unsupported = @() }
            }
            Mock Get-CgrApprovedSourceState {
                [pscustomobject] @{
                    Repository = 'acme/source'
                    DefaultBranch = 'main'
                    Refs = @([pscustomobject] @{ Name = 'refs/tags/v2.0.0'; Sha = 'abc123' })
                    ReachableCommitCount = 1
                    BranchTrees = @()
                    GitLfsObjectsAvailable = $true
                }
            }
            Mock Get-CgrGitHubReleaseSelection {
                [pscustomobject] @{
                    PSTypeName = 'CopyGitHubRepo.ReleaseSelection'
                    Repository = 'acme/source'
                    AvailableReleaseCount = 4
                    SelectedReleaseCount = 1
                    SelectedAssetCount = 2
                    IncludePatterns = @('v2.*')
                    ExcludePatterns = @()
                    IncludePrerelease = $false
                    IncludeDraftReleases = $false
                    ReleaseCount = 1
                    Releases = @([pscustomobject] @{
                            ReleaseId = 20
                            TagName = 'v2.0.0'
                            Name = 'Version 2.0.0'
                            Body = 'approved notes'
                            Draft = $false
                            Prerelease = $false
                            TargetCommitSha = 'abc123'
                            Assets = @(
                                [pscustomobject] @{ Name = 'module.zip'; Size = 10; Digest = 'sha256:a' },
                                [pscustomobject] @{ Name = 'module.sha256'; Size = 20; Digest = 'sha256:b' }
                            )
                        })
                }
            }

            $plan = New-CgrMigrationPlan `
                -SourceRepository $source `
                -DestinationRepository 'acme/destination' `
                -ContentMode FullHistory `
                -DestinationVisibility private `
                -CommitMessage 'unused' `
                -IncludeReleases `
                -ReleaseTag 'v2.*' `
                -ReleaseCount 1 `
                -PlanOnly

            $plan.IncludeReleases | Should -BeTrue
            $plan.ReleaseSelection.SelectedReleaseCount | Should -Be 1
            $plan.ReleaseSelection.SelectedAssetCount | Should -Be 2
            $plan.ReleaseSelection.Releases[0].TagName | Should -Be 'v2.0.0'
            $plan.ReleaseSelection.Releases[0].TargetCommitSha | Should -Be 'abc123'
            @($plan.Steps | Where-Object Name -eq 'RestoreGitHubReleases').Count | Should -Be 1
            @($plan.Steps | Where-Object Name -eq 'RestoreGitHubReleases')[0].Description | Should -Match '1 approved GitHub Release\(s\).*2 release asset\(s\)'

            Should -Invoke Get-CgrGitHubReleaseSelection -Times 1 -Exactly -ParameterFilter {
                $Repository.FullName -eq 'acme/source' -and
                $ReleaseTag.Count -eq 1 -and
                $ReleaseTag[0] -eq 'v2.*' -and
                $ReleaseCount -eq 1
            }
        }
    }
}

Describe 'GitHub Release migration orchestration' {
    It 'restores approved releases after FullHistory content verification' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'acme/source'; Visibility = 'private'; DefaultBranch = 'main' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination'; HtmlUrl = 'https://github.com/acme/destination'; DefaultBranch = 'main' }
            $selection = [pscustomobject] @{
                SelectedReleaseCount = 1
                SelectedAssetCount = 1
                Releases = @([pscustomobject] @{ TagName = 'v1.0.0'; TargetCommitSha = 'abc123'; Assets = @([pscustomobject] @{ Name = 'module.zip' }) })
            }
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                DestinationRepository = 'acme/destination'
                ContentMode = 'FullHistory'
                SkipSettings = $true
                IncludeReleases = $true
                ReleaseSelection = $selection
                Protection = $null
                SourceState = [pscustomobject] @{ Refs = @(); ReachableCommitCount = 1 }
            }
            $script:stageOrder = [System.Collections.Generic.List[string]]::new()

            Mock Copy-CgrRepositoryFullHistory {
                [pscustomobject] @{ IsSuccessful = $true; DefaultBranch = 'main'; CopiedSourceEvidence = [pscustomobject] @{ Repository = 'acme/source' } }
            }
            Mock Get-CgrRepository { $destination }
            Mock Invoke-CgrApprovedFullHistoryVerification {
                $script:stageOrder.Add('VerifyFullHistory')
                [pscustomobject] @{ IsSuccessful = $true }
            }
            Mock Copy-CgrApprovedGitHubRelease {
                $script:stageOrder.Add('RestoreGitHubReleases')
                [pscustomobject] @{
                    PSTypeName = 'CopyGitHubRepo.ReleaseMigrationResult'
                    ApprovedReleaseCount = 1
                    DestinationReleaseCount = 1
                    AssetCount = 1
                    Releases = @([pscustomobject] @{ TagName = 'v1.0.0'; IsVerified = $true })
                    IsSuccessful = $true
                }
            }
            Mock Invoke-CgrActivityStage {
                param($Name, $Message, $Action)
                & $Action
            }
            Mock Set-CgrGitHubRepositorySetting { throw 'Settings must remain skipped.' }
            Mock Set-CgrRepositoryProtectionConfiguration { throw 'Protection must remain skipped.' }

            $result = Invoke-CgrNewDestinationFullHistory -Plan $plan -SourceRepository $source -DestinationRepository $destination

            $result.IsVerified | Should -BeTrue
            $result.Releases.IsSuccessful | Should -BeTrue
            $result.Releases.DestinationReleaseCount | Should -Be 1
            $result.ReleaseRestored | Should -BeTrue
            @($result.CompletedSteps | Where-Object Name -eq 'RestoreGitHubReleases').Count | Should -Be 1
            ($script:stageOrder -join ',') | Should -Be 'VerifyFullHistory,RestoreGitHubReleases'

            Should -Invoke Copy-CgrApprovedGitHubRelease -Times 1 -Exactly -ParameterFilter {
                $SourceRepository.FullName -eq 'acme/source' -and
                $DestinationRepository.FullName -eq 'acme/destination' -and
                $ApprovedSelection.SelectedReleaseCount -eq 1
            }
        }
    }

    It 'does not restore releases when FullHistory verification fails' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'acme/source'; Visibility = 'private'; DefaultBranch = 'main' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination'; HtmlUrl = 'https://github.com/acme/destination'; DefaultBranch = 'main' }
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                DestinationRepository = 'acme/destination'
                ContentMode = 'FullHistory'
                SkipSettings = $true
                IncludeReleases = $true
                ReleaseSelection = [pscustomobject] @{ Releases = @([pscustomobject] @{ TagName = 'v1.0.0' }) }
                Protection = $null
                SourceState = [pscustomobject] @{ Refs = @(); ReachableCommitCount = 1 }
            }

            Mock Copy-CgrRepositoryFullHistory {
                [pscustomobject] @{ IsSuccessful = $true; DefaultBranch = 'main'; CopiedSourceEvidence = [pscustomobject] @{ Repository = 'acme/source' } }
            }
            Mock Get-CgrRepository { $destination }
            Mock Invoke-CgrApprovedFullHistoryVerification { [pscustomobject] @{ IsSuccessful = $false } }
            Mock Copy-CgrApprovedGitHubRelease { throw 'Release mutation must not run after failed content verification.' }
            Mock Invoke-CgrActivityStage {
                param($Name, $Message, $Action)
                & $Action
            }

            $result = Invoke-CgrNewDestinationFullHistory -Plan $plan -SourceRepository $source -DestinationRepository $destination

            $result.IsVerified | Should -BeFalse
            $result.Releases.IsSuccessful | Should -BeFalse
            $result.Releases.Skipped | Should -Contain 'FullHistoryVerificationFailed'
            Should -Invoke Copy-CgrApprovedGitHubRelease -Times 0 -Exactly
        }
    }
}
