BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1') -Force
}

Describe 'FullHistory planned protection restoration' {
    It 'does not rediscover protection for an explicit non-captured new-destination plan' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                SourceState = [pscustomobject] @{ Refs = @(); ReachableCommitCount = 1 }
                IncludeReleases = $false
                ReleaseSelection = $null
                SkipSettings = $false
                Protection = [pscustomobject] @{ Status = 'SkippedSourceIdentityUnavailable'; Configuration = $null }
            }
            $source = [pscustomobject] @{ FullName = 'acme/source'; HostName = 'github.com' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination'; HtmlUrl = 'https://github.com/acme/destination' }

            Mock Copy-CgrRepositoryFullHistory {
                [pscustomobject] @{ IsSuccessful = $true; DefaultBranch = 'main'; CopiedSourceEvidence = $plan.SourceState }
            }
            Mock Get-CgrRepository { $destination }
            Mock Invoke-CgrApprovedFullHistoryVerification { [pscustomobject] @{ IsSuccessful = $true } }
            Mock Set-CgrGitHubRepositorySetting {
                [pscustomobject] @{ Repository = $destination.FullName; Restored = @(); Skipped = @(); Unsupported = @(); IsSuccessful = $true }
            }
            Mock Set-CgrRepositoryProtectionConfiguration { throw 'Protection must not be rediscovered after planning.' }

            $result = Invoke-CgrNewDestinationFullHistory -Plan $plan -SourceRepository $source -DestinationRepository $destination

            $result.Protection.Status | Should -Be 'Unsupported'
            $result.Protection.Skipped | Should -Contain 'ProtectionPlanning:SkippedSourceIdentityUnavailable'
            $result.Protection.IsSuccessful | Should -BeTrue
            $result.Protection.IsComplete | Should -BeFalse
            $result.ProtectionRestored | Should -BeFalse
            Should -Invoke Set-CgrRepositoryProtectionConfiguration -Times 0 -Exactly
        }
    }

    It 'does not use legacy protection discovery when new-destination protection evidence is explicitly null' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                SourceState = [pscustomobject] @{ Refs = @(); ReachableCommitCount = 1 }
                IncludeReleases = $false
                ReleaseSelection = $null
                SkipSettings = $false
                Protection = $null
            }
            $source = [pscustomobject] @{ FullName = 'acme/source'; HostName = 'github.com' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination'; HtmlUrl = 'https://github.com/acme/destination' }

            Mock Copy-CgrRepositoryFullHistory {
                [pscustomobject] @{ IsSuccessful = $true; DefaultBranch = 'main'; CopiedSourceEvidence = $plan.SourceState }
            }
            Mock Get-CgrRepository { $destination }
            Mock Invoke-CgrApprovedFullHistoryVerification { [pscustomobject] @{ IsSuccessful = $true } }
            Mock Set-CgrGitHubRepositorySetting {
                [pscustomobject] @{ Repository = $destination.FullName; Restored = @(); Skipped = @(); Unsupported = @(); IsSuccessful = $true }
            }
            Mock Set-CgrRepositoryProtectionConfiguration { throw 'Explicitly null protection evidence must not trigger live source discovery.' }

            $result = Invoke-CgrNewDestinationFullHistory -Plan $plan -SourceRepository $source -DestinationRepository $destination

            $result.Protection.Status | Should -Be 'Unsupported'
            $result.Protection.Skipped | Should -Contain 'ProtectionPlanning:Invalid'
            $result.Protection.IsSuccessful | Should -BeTrue
            $result.Protection.IsComplete | Should -BeFalse
            $result.ProtectionRestored | Should -BeFalse
            Should -Invoke Set-CgrRepositoryProtectionConfiguration -Times 0 -Exactly
        }
    }

    It 'preserves legacy protection discovery only when the new-destination Protection property is absent' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                SourceState = [pscustomobject] @{ Refs = @(); ReachableCommitCount = 1 }
                IncludeReleases = $false
                ReleaseSelection = $null
                SkipSettings = $false
            }
            $source = [pscustomobject] @{ FullName = 'acme/source'; HostName = 'github.com' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination'; HtmlUrl = 'https://github.com/acme/destination' }

            Mock Copy-CgrRepositoryFullHistory {
                [pscustomobject] @{ IsSuccessful = $true; DefaultBranch = 'main'; CopiedSourceEvidence = $plan.SourceState }
            }
            Mock Get-CgrRepository { $destination }
            Mock Invoke-CgrApprovedFullHistoryVerification { [pscustomobject] @{ IsSuccessful = $true } }
            Mock Set-CgrGitHubRepositorySetting {
                [pscustomobject] @{ Repository = $destination.FullName; Restored = @(); Skipped = @(); Unsupported = @(); IsSuccessful = $true }
            }
            Mock Set-CgrRepositoryProtectionConfiguration {
                [pscustomobject] @{ Repository = $destination.FullName; Status = 'NotApplicable'; Restored = @(); Skipped = @(); IsSuccessful = $true; IsComplete = $true }
            }

            $result = Invoke-CgrNewDestinationFullHistory -Plan $plan -SourceRepository $source -DestinationRepository $destination

            $result.Protection.Status | Should -Be 'NotApplicable'
            $result.Protection.IsComplete | Should -BeTrue
            $result.ProtectionRestored | Should -BeTrue
            Should -Invoke Set-CgrRepositoryProtectionConfiguration -Times 1 -Exactly
        }
    }

    It 'uses the exact captured protection configuration for a new-destination plan' {
        InModuleScope CopyGitHubRepo {
            $plannedConfiguration = [pscustomobject] @{ Rulesets = @([pscustomobject] @{ Name = 'planned-ruleset' }); BranchProtection = $null; Unsupported = @() }
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                SourceState = [pscustomobject] @{ Refs = @(); ReachableCommitCount = 1 }
                IncludeReleases = $false
                ReleaseSelection = $null
                SkipSettings = $false
                Protection = [pscustomobject] @{ Status = 'Captured'; Configuration = $plannedConfiguration }
            }
            $source = [pscustomobject] @{ FullName = 'acme/source'; HostName = 'github.com' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination'; HtmlUrl = 'https://github.com/acme/destination' }

            Mock Copy-CgrRepositoryFullHistory {
                [pscustomobject] @{ IsSuccessful = $true; DefaultBranch = 'main'; CopiedSourceEvidence = $plan.SourceState }
            }
            Mock Get-CgrRepository { $destination }
            Mock Invoke-CgrApprovedFullHistoryVerification { [pscustomobject] @{ IsSuccessful = $true } }
            Mock Set-CgrGitHubRepositorySetting {
                [pscustomobject] @{ Repository = $destination.FullName; Restored = @(); Skipped = @(); Unsupported = @(); IsSuccessful = $true }
            }
            Mock Set-CgrRepositoryProtectionConfiguration {
                [pscustomobject] @{ Repository = $destination.FullName; Status = 'Restored'; Restored = @('Ruleset:planned-ruleset'); Skipped = @(); IsSuccessful = $true; IsComplete = $true }
            }

            $result = Invoke-CgrNewDestinationFullHistory -Plan $plan -SourceRepository $source -DestinationRepository $destination

            $result.Protection.Status | Should -Be 'Restored'
            $result.ProtectionRestored | Should -BeTrue
            Should -Invoke Set-CgrRepositoryProtectionConfiguration -Times 1 -Exactly -ParameterFilter {
                $SourceConfiguration -eq $plannedConfiguration
            }
        }
    }

    It 'does not rediscover protection for an explicit non-captured same-name plan' {
        InModuleScope CopyGitHubRepo {
            $sourceState = [pscustomobject] @{ Refs = @('refs/heads/main 1111111111111111111111111111111111111111'); ReachableCommitCount = 1 }
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'
                ArchiveRepository = 'acme/source-archive'
                DestinationRepository = 'acme/source'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                SourceState = $sourceState
                IncludeReleases = $false
                ReleaseSelection = $null
                SkipSettings = $false
                Protection = [pscustomobject] @{ Status = 'SkippedSourceIdentityUnavailable'; Configuration = $null }
            }
            $source = [pscustomobject] @{ FullName = 'acme/source'; HostName = 'github.com'; Id = 10; NodeId = 'SRC' }
            $script:archiveFixture = [pscustomobject] @{ FullName = 'acme/source-archive'; HostName = 'github.com'; Id = 10; NodeId = 'SRC' }
            $script:destinationFixture = [pscustomobject] @{ FullName = 'acme/source'; HostName = 'github.com'; HtmlUrl = 'https://github.com/acme/source'; Id = 20; NodeId = 'DST' }

            Mock Assert-CgrApprovedSourceState {}
            Mock Rename-CgrGitHubRepository { $script:archiveFixture }
            Mock New-CgrGitHubRepository { $script:destinationFixture }
            Mock Assert-CgrReplacementRepositoryIdentity {
                [pscustomobject] @{ SourceRepositoryId = 10; ArchiveRepositoryId = 10; ReplacementRepositoryId = 20 }
            }
            Mock Copy-CgrRepositoryFullHistory {
                [pscustomobject] @{ IsSuccessful = $true; DefaultBranch = 'main'; CopiedSourceEvidence = $sourceState }
            }
            Mock Get-CgrRepository { $script:destinationFixture }
            Mock Invoke-CgrApprovedFullHistoryVerification { [pscustomobject] @{ IsSuccessful = $true } }
            Mock Set-CgrGitHubRepositorySetting {
                [pscustomobject] @{ Repository = $script:destinationFixture.FullName; Restored = @(); Skipped = @(); Unsupported = @(); IsSuccessful = $true }
            }
            Mock Set-CgrRepositoryProtectionConfiguration { throw 'Protection must not be rediscovered after planning.' }

            $result = Invoke-CgrSameNameFullHistoryReplacement -Plan $plan -SourceRepository $source

            $result.Protection.Status | Should -Be 'Unsupported'
            $result.Protection.Skipped | Should -Contain 'ProtectionPlanning:SkippedSourceIdentityUnavailable'
            $result.Protection.IsSuccessful | Should -BeTrue
            $result.Protection.IsComplete | Should -BeFalse
            $result.ProtectionRestored | Should -BeFalse
            Should -Invoke Set-CgrRepositoryProtectionConfiguration -Times 0 -Exactly
        }
    }

    It 'does not use legacy protection discovery when same-name protection evidence is explicitly null' {
        InModuleScope CopyGitHubRepo {
            $sourceState = [pscustomobject] @{ Refs = @('refs/heads/main 1111111111111111111111111111111111111111'); ReachableCommitCount = 1 }
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'
                ArchiveRepository = 'acme/source-archive'
                DestinationRepository = 'acme/source'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                SourceState = $sourceState
                IncludeReleases = $false
                ReleaseSelection = $null
                SkipSettings = $false
                Protection = $null
            }
            $source = [pscustomobject] @{ FullName = 'acme/source'; HostName = 'github.com'; Id = 10; NodeId = 'SRC' }
            $script:archiveFixture = [pscustomobject] @{ FullName = 'acme/source-archive'; HostName = 'github.com'; Id = 10; NodeId = 'SRC' }
            $script:destinationFixture = [pscustomobject] @{ FullName = 'acme/source'; HostName = 'github.com'; HtmlUrl = 'https://github.com/acme/source'; Id = 20; NodeId = 'DST' }

            Mock Assert-CgrApprovedSourceState {}
            Mock Rename-CgrGitHubRepository { $script:archiveFixture }
            Mock New-CgrGitHubRepository { $script:destinationFixture }
            Mock Assert-CgrReplacementRepositoryIdentity {
                [pscustomobject] @{ SourceRepositoryId = 10; ArchiveRepositoryId = 10; ReplacementRepositoryId = 20 }
            }
            Mock Copy-CgrRepositoryFullHistory {
                [pscustomobject] @{ IsSuccessful = $true; DefaultBranch = 'main'; CopiedSourceEvidence = $sourceState }
            }
            Mock Get-CgrRepository { $script:destinationFixture }
            Mock Invoke-CgrApprovedFullHistoryVerification { [pscustomobject] @{ IsSuccessful = $true } }
            Mock Set-CgrGitHubRepositorySetting {
                [pscustomobject] @{ Repository = $script:destinationFixture.FullName; Restored = @(); Skipped = @(); Unsupported = @(); IsSuccessful = $true }
            }
            Mock Set-CgrRepositoryProtectionConfiguration { throw 'Explicitly null protection evidence must not trigger live source discovery.' }

            $result = Invoke-CgrSameNameFullHistoryReplacement -Plan $plan -SourceRepository $source

            $result.Protection.Status | Should -Be 'Unsupported'
            $result.Protection.Skipped | Should -Contain 'ProtectionPlanning:Invalid'
            $result.Protection.IsSuccessful | Should -BeTrue
            $result.Protection.IsComplete | Should -BeFalse
            $result.ProtectionRestored | Should -BeFalse
            Should -Invoke Set-CgrRepositoryProtectionConfiguration -Times 0 -Exactly
        }
    }

    It 'preserves legacy protection discovery only when the same-name Protection property is absent' {
        InModuleScope CopyGitHubRepo {
            $sourceState = [pscustomobject] @{ Refs = @('refs/heads/main 1111111111111111111111111111111111111111'); ReachableCommitCount = 1 }
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'
                ArchiveRepository = 'acme/source-archive'
                DestinationRepository = 'acme/source'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                SourceState = $sourceState
                IncludeReleases = $false
                ReleaseSelection = $null
                SkipSettings = $false
            }
            $source = [pscustomobject] @{ FullName = 'acme/source'; HostName = 'github.com'; Id = 10; NodeId = 'SRC' }
            $script:archiveFixture = [pscustomobject] @{ FullName = 'acme/source-archive'; HostName = 'github.com'; Id = 10; NodeId = 'SRC' }
            $script:destinationFixture = [pscustomobject] @{ FullName = 'acme/source'; HostName = 'github.com'; HtmlUrl = 'https://github.com/acme/source'; Id = 20; NodeId = 'DST' }

            Mock Assert-CgrApprovedSourceState {}
            Mock Rename-CgrGitHubRepository { $script:archiveFixture }
            Mock New-CgrGitHubRepository { $script:destinationFixture }
            Mock Assert-CgrReplacementRepositoryIdentity {
                [pscustomobject] @{ SourceRepositoryId = 10; ArchiveRepositoryId = 10; ReplacementRepositoryId = 20 }
            }
            Mock Copy-CgrRepositoryFullHistory {
                [pscustomobject] @{ IsSuccessful = $true; DefaultBranch = 'main'; CopiedSourceEvidence = $sourceState }
            }
            Mock Get-CgrRepository { $script:destinationFixture }
            Mock Invoke-CgrApprovedFullHistoryVerification { [pscustomobject] @{ IsSuccessful = $true } }
            Mock Set-CgrGitHubRepositorySetting {
                [pscustomobject] @{ Repository = $script:destinationFixture.FullName; Restored = @(); Skipped = @(); Unsupported = @(); IsSuccessful = $true }
            }
            Mock Set-CgrRepositoryProtectionConfiguration {
                [pscustomobject] @{ Repository = $script:destinationFixture.FullName; Status = 'NotApplicable'; Restored = @(); Skipped = @(); IsSuccessful = $true; IsComplete = $true }
            }

            $result = Invoke-CgrSameNameFullHistoryReplacement -Plan $plan -SourceRepository $source

            $result.Protection.Status | Should -Be 'NotApplicable'
            $result.Protection.IsComplete | Should -BeTrue
            $result.ProtectionRestored | Should -BeTrue
            Should -Invoke Set-CgrRepositoryProtectionConfiguration -Times 1 -Exactly
        }
    }

    It 'uses the exact captured protection configuration for a same-name plan' {
        InModuleScope CopyGitHubRepo {
            $plannedConfiguration = [pscustomobject] @{ Rulesets = @([pscustomobject] @{ Name = 'planned-ruleset' }); BranchProtection = $null; Unsupported = @() }
            $sourceState = [pscustomobject] @{ Refs = @('refs/heads/main 1111111111111111111111111111111111111111'); ReachableCommitCount = 1 }
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'
                ArchiveRepository = 'acme/source-archive'
                DestinationRepository = 'acme/source'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                SourceState = $sourceState
                IncludeReleases = $false
                ReleaseSelection = $null
                SkipSettings = $false
                Protection = [pscustomobject] @{ Status = 'Captured'; Configuration = $plannedConfiguration }
            }
            $source = [pscustomobject] @{ FullName = 'acme/source'; HostName = 'github.com'; Id = 10; NodeId = 'SRC' }
            $script:archiveFixture = [pscustomobject] @{ FullName = 'acme/source-archive'; HostName = 'github.com'; Id = 10; NodeId = 'SRC' }
            $script:destinationFixture = [pscustomobject] @{ FullName = 'acme/source'; HostName = 'github.com'; HtmlUrl = 'https://github.com/acme/source'; Id = 20; NodeId = 'DST' }

            Mock Assert-CgrApprovedSourceState {}
            Mock Rename-CgrGitHubRepository { $script:archiveFixture }
            Mock New-CgrGitHubRepository { $script:destinationFixture }
            Mock Assert-CgrReplacementRepositoryIdentity {
                [pscustomobject] @{ SourceRepositoryId = 10; ArchiveRepositoryId = 10; ReplacementRepositoryId = 20 }
            }
            Mock Copy-CgrRepositoryFullHistory {
                [pscustomobject] @{ IsSuccessful = $true; DefaultBranch = 'main'; CopiedSourceEvidence = $sourceState }
            }
            Mock Get-CgrRepository { $script:destinationFixture }
            Mock Invoke-CgrApprovedFullHistoryVerification { [pscustomobject] @{ IsSuccessful = $true } }
            Mock Set-CgrGitHubRepositorySetting {
                [pscustomobject] @{ Repository = $script:destinationFixture.FullName; Restored = @(); Skipped = @(); Unsupported = @(); IsSuccessful = $true }
            }
            Mock Set-CgrRepositoryProtectionConfiguration {
                [pscustomobject] @{ Repository = $script:destinationFixture.FullName; Status = 'Restored'; Restored = @('Ruleset:planned-ruleset'); Skipped = @(); IsSuccessful = $true; IsComplete = $true }
            }

            $result = Invoke-CgrSameNameFullHistoryReplacement -Plan $plan -SourceRepository $source

            $result.Protection.Status | Should -Be 'Restored'
            $result.ProtectionRestored | Should -BeTrue
            Should -Invoke Set-CgrRepositoryProtectionConfiguration -Times 1 -Exactly -ParameterFilter {
                $SourceConfiguration -eq $plannedConfiguration
            }
        }
    }
}
