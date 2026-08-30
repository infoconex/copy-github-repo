BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1') -Force
}

Describe 'Snapshot planned protection compatibility boundary' {
    It 'does not use legacy protection discovery when new-destination protection evidence is explicitly null' {
        InModuleScope CopyGitHubRepo {
            $sourceState = [pscustomobject] @{ DefaultBranch = 'main'; CommitSha = 'source-commit'; TreeSha = 'source-tree' }
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'
                SourceDefaultBranch = 'main'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                CommitMessage = 'Snapshot commit'
                SourceState = $sourceState
                SkipSettings = $false
                Protection = $null
            }
            $source = [pscustomobject] @{ FullName = 'acme/source'; HostName = 'github.com' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination'; HtmlUrl = 'https://github.com/acme/destination' }

            Mock Copy-CgrRepositorySnapshot {
                [pscustomobject] @{ Verified = $true; BranchName = 'main'; CommitSha = 'destination-commit'; SourceCommitSha = 'source-commit'; TreeSha = 'source-tree' }
            }
            Mock Get-CgrRepository { $destination }
            Mock Invoke-CgrRepositorySnapshotVerification {
                [pscustomobject] @{ IsSuccessful = $true; SourceTree = 'source-tree'; DestinationTree = 'source-tree' }
            }
            Mock Set-CgrGitHubRepositorySetting {
                [pscustomobject] @{ Repository = $destination.FullName; Restored = @(); Skipped = @(); Unsupported = @(); IsSuccessful = $true }
            }
            Mock Set-CgrRepositoryProtectionConfiguration { throw 'Explicitly null protection evidence must not trigger live source discovery.' }

            $result = Invoke-CgrNewDestinationSnapshot -Plan $plan -SourceRepository $source -DestinationRepository $destination

            $result.Protection.Status | Should -Be 'Unsupported'
            $result.Protection.Skipped | Should -Contain 'ProtectionPlanning:Invalid'
            $result.Protection.IsComplete | Should -BeFalse
            $result.ProtectionRestored | Should -BeFalse
            Should -Invoke Set-CgrRepositoryProtectionConfiguration -Times 0 -Exactly
        }
    }

    It 'preserves legacy protection discovery only when the new-destination Protection property is absent' {
        InModuleScope CopyGitHubRepo {
            $sourceState = [pscustomobject] @{ DefaultBranch = 'main'; CommitSha = 'source-commit'; TreeSha = 'source-tree' }
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'
                SourceDefaultBranch = 'main'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                CommitMessage = 'Snapshot commit'
                SourceState = $sourceState
                SkipSettings = $false
            }
            $source = [pscustomobject] @{ FullName = 'acme/source'; HostName = 'github.com' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination'; HtmlUrl = 'https://github.com/acme/destination' }

            Mock Copy-CgrRepositorySnapshot {
                [pscustomobject] @{ Verified = $true; BranchName = 'main'; CommitSha = 'destination-commit'; SourceCommitSha = 'source-commit'; TreeSha = 'source-tree' }
            }
            Mock Get-CgrRepository { $destination }
            Mock Invoke-CgrRepositorySnapshotVerification {
                [pscustomobject] @{ IsSuccessful = $true; SourceTree = 'source-tree'; DestinationTree = 'source-tree' }
            }
            Mock Set-CgrGitHubRepositorySetting {
                [pscustomobject] @{ Repository = $destination.FullName; Restored = @(); Skipped = @(); Unsupported = @(); IsSuccessful = $true }
            }
            Mock Set-CgrRepositoryProtectionConfiguration {
                [pscustomobject] @{ Repository = $destination.FullName; Status = 'NotApplicable'; Restored = @(); Skipped = @(); IsSuccessful = $true; IsComplete = $true }
            }

            $result = Invoke-CgrNewDestinationSnapshot -Plan $plan -SourceRepository $source -DestinationRepository $destination

            $result.Protection.Status | Should -Be 'NotApplicable'
            $result.Protection.IsComplete | Should -BeTrue
            $result.ProtectionRestored | Should -BeTrue
            Should -Invoke Set-CgrRepositoryProtectionConfiguration -Times 1 -Exactly
        }
    }

    It 'does not use legacy protection discovery when same-name protection evidence is explicitly null' {
        InModuleScope CopyGitHubRepo {
            $sourceState = [pscustomobject] @{ DefaultBranch = 'main'; CommitSha = 'source-commit'; TreeSha = 'source-tree' }
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'
                ArchiveRepository = 'acme/source-archive'
                DestinationRepository = 'acme/source'
                SourceDefaultBranch = 'main'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                CommitMessage = 'Snapshot commit'
                SourceState = $sourceState
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
            Mock Copy-CgrRepositorySnapshot {
                [pscustomobject] @{ Verified = $true; BranchName = 'main'; CommitSha = 'destination-commit'; SourceCommitSha = 'source-commit'; TreeSha = 'source-tree' }
            }
            Mock Get-CgrRepository { $script:destinationFixture }
            Mock Invoke-CgrRepositorySnapshotVerification {
                [pscustomobject] @{ IsSuccessful = $true; SourceTree = 'source-tree'; DestinationTree = 'source-tree' }
            }
            Mock Set-CgrGitHubRepositorySetting {
                [pscustomobject] @{ Repository = $script:destinationFixture.FullName; Restored = @(); Skipped = @(); Unsupported = @(); IsSuccessful = $true }
            }
            Mock Set-CgrRepositoryProtectionConfiguration { throw 'Explicitly null protection evidence must not trigger live source discovery.' }

            $result = Invoke-CgrSameNameSnapshotReplacement -Plan $plan -SourceRepository $source

            $result.Protection.Status | Should -Be 'Unsupported'
            $result.Protection.Skipped | Should -Contain 'ProtectionPlanning:Invalid'
            $result.Protection.IsComplete | Should -BeFalse
            $result.ProtectionRestored | Should -BeFalse
            Should -Invoke Set-CgrRepositoryProtectionConfiguration -Times 0 -Exactly
        }
    }

    It 'preserves legacy protection discovery only when the same-name Protection property is absent' {
        InModuleScope CopyGitHubRepo {
            $sourceState = [pscustomobject] @{ DefaultBranch = 'main'; CommitSha = 'source-commit'; TreeSha = 'source-tree' }
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'
                ArchiveRepository = 'acme/source-archive'
                DestinationRepository = 'acme/source'
                SourceDefaultBranch = 'main'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                CommitMessage = 'Snapshot commit'
                SourceState = $sourceState
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
            Mock Copy-CgrRepositorySnapshot {
                [pscustomobject] @{ Verified = $true; BranchName = 'main'; CommitSha = 'destination-commit'; SourceCommitSha = 'source-commit'; TreeSha = 'source-tree' }
            }
            Mock Get-CgrRepository { $script:destinationFixture }
            Mock Invoke-CgrRepositorySnapshotVerification {
                [pscustomobject] @{ IsSuccessful = $true; SourceTree = 'source-tree'; DestinationTree = 'source-tree' }
            }
            Mock Set-CgrGitHubRepositorySetting {
                [pscustomobject] @{ Repository = $script:destinationFixture.FullName; Restored = @(); Skipped = @(); Unsupported = @(); IsSuccessful = $true }
            }
            Mock Set-CgrRepositoryProtectionConfiguration {
                [pscustomobject] @{ Repository = $script:destinationFixture.FullName; Status = 'NotApplicable'; Restored = @(); Skipped = @(); IsSuccessful = $true; IsComplete = $true }
            }

            $result = Invoke-CgrSameNameSnapshotReplacement -Plan $plan -SourceRepository $source

            $result.Protection.Status | Should -Be 'NotApplicable'
            $result.Protection.IsComplete | Should -BeTrue
            $result.ProtectionRestored | Should -BeTrue
            Should -Invoke Set-CgrRepositoryProtectionConfiguration -Times 1 -Exactly
        }
    }
}
