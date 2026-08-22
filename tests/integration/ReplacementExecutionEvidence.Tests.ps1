BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $root 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Existing-destination replacement execution evidence' {
    It 'preserves archive-before-replacement timeline and immutable identity evidence' {
        InModuleScope CopyGitHubRepo {
            $sourceState = [pscustomobject] @{ ContentMode = 'Snapshot'; Repository = 'infoconex/source'; RepositoryId = 10L; DefaultBranch = 'main'; CommitSha = 'source-commit'; TreeSha = 'source-tree' }
            $plan = [pscustomobject] @{
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                ArchiveRepository = 'infoconex/destination-archive'
                DestinationVisibility = 'private'
                ContentMode = 'Snapshot'
                SourceState = $sourceState
            }
            $source = [pscustomobject] @{ FullName = 'infoconex/source'; Id = 10L }
            $existing = [pscustomobject] @{ FullName = 'infoconex/destination'; Id = 20L; NodeId = 'R_original' }
            $script:archiveFixture = [pscustomobject] @{ FullName = 'infoconex/destination-archive'; Id = 20L; NodeId = 'R_original' }
            $script:replacementFixture = [pscustomobject] @{ FullName = 'infoconex/destination'; Id = 30L; NodeId = 'R_replacement' }

            Mock Assert-CgrApprovedSourceState { [pscustomobject] @{ DefaultBranch = 'main'; CommitSha = 'source-commit'; TreeSha = 'source-tree' } }
            Mock Rename-CgrGitHubRepository { $script:archiveFixture }
            Mock New-CgrGitHubRepository { $script:replacementFixture }
            Mock Invoke-CgrNewDestinationSnapshot {
                [pscustomobject] @{
                    PSTypeName = 'CopyGitHubRepo.MigrationExecutionResult'
                    Status = 'SnapshotVerifiedSettingsSkipped'
                    DestinationRepository = 'infoconex/destination'
                    IsVerified = $true
                    CompletedSteps = @(
                        [pscustomobject] @{ Order = 1; Name = 'CreateDestinationRepository'; MutatedGitHub = $true; Verified = $true }
                        [pscustomobject] @{ Order = 2; Name = 'CopySnapshot'; MutatedGitHub = $true; Verified = $true }
                        [pscustomobject] @{ Order = 3; Name = 'VerifySnapshot'; MutatedGitHub = $false; Verified = $true }
                        [pscustomobject] @{ Order = 4; Name = 'RestoreSupportedSettings'; MutatedGitHub = $false; Verified = $true }
                        [pscustomobject] @{ Order = 5; Name = 'RestoreRepositoryProtection'; MutatedGitHub = $false; Verified = $true }
                    )
                }
            }

            $result = Invoke-CgrExistingDestinationReplacement -Plan $plan -SourceRepository $source -ExistingDestinationRepository $existing

            @($result.CompletedSteps).Name | Should -Be @(
                'PreserveDestinationAsArchive'
                'VerifyArchivedDestinationIdentity'
                'CreateReplacementRepository'
                'VerifyReplacementRepositoryIdentity'
                'CopySnapshot'
                'VerifySnapshot'
                'RestoreSupportedSettings'
                'RestoreRepositoryProtection'
            )
            $result.OriginalDestinationRepositoryId | Should -Be 20
            $result.ArchiveRepositoryId | Should -Be 20
            $result.ArchivedOriginalIdentityPreserved | Should -BeTrue
            $result.ReplacementDestinationRepositoryId | Should -Be 30
            $result.ReplacementHasDistinctIdentity | Should -BeTrue
            $result.ReplacedDestinationRepositoryId | Should -Be 20
            Should -Invoke Assert-CgrApprovedSourceState -Times 1 -Exactly
        }
    }

    It 'stops before replacement creation when the archive does not retain original identity' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                ArchiveRepository = 'infoconex/archive'
                DestinationVisibility = 'private'
                ContentMode = 'Snapshot'
                SourceState = [pscustomobject] @{ ContentMode = 'Snapshot'; Repository = 'infoconex/source'; DefaultBranch = 'main'; CommitSha = 'source-commit'; TreeSha = 'source-tree' }
            }
            $source = [pscustomobject] @{ FullName = 'infoconex/source' }
            $existing = [pscustomobject] @{ FullName = 'infoconex/destination'; Id = 20L; NodeId = 'R_original' }
            Mock Assert-CgrApprovedSourceState { [pscustomobject] @{ DefaultBranch = 'main'; CommitSha = 'source-commit'; TreeSha = 'source-tree' } }
            Mock Rename-CgrGitHubRepository { [pscustomobject] @{ FullName = 'infoconex/archive'; Id = 21L; NodeId = 'R_other' } }
            Mock New-CgrGitHubRepository { throw 'must not create replacement' }
            Mock Write-CgrExistingDestinationRecoveryReport { 'recovery.json' }

            { Invoke-CgrExistingDestinationReplacement -Plan $plan -SourceRepository $source -ExistingDestinationRepository $existing } |
                Should -Throw -ErrorId 'ArchivedDestinationIdentityMismatch'
            Should -Invoke New-CgrGitHubRepository -Times 0 -Exactly
        }
    }
}

Describe 'Replacement evidence presentation' {
    It 'renders original archive and replacement immutable identities in Markdown' {
        InModuleScope CopyGitHubRepo {
            $result = [pscustomobject] @{
                Status = 'Completed'
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                DestinationHtmlUrl = 'https://github.com/infoconex/destination'
                DestinationBranch = 'main'
                SnapshotCommitSha = 'abc'
                IsVerified = $true
                SettingsRestored = $true
                ProtectionRestored = $true
                OriginalDestinationRepository = 'infoconex/destination'
                OriginalDestinationRepositoryId = 20L
                OriginalDestinationRepositoryNodeId = 'R_original'
                ArchiveRepository = 'infoconex/destination-archive'
                ArchiveRepositoryId = 20L
                ArchiveRepositoryNodeId = 'R_original'
                ArchivedOriginalIdentityPreserved = $true
                ReplacementDestinationRepository = 'infoconex/destination'
                ReplacementDestinationRepositoryId = 30L
                ReplacementDestinationRepositoryNodeId = 'R_replacement'
                ReplacementHasDistinctIdentity = $true
                CompletedSteps = @()
                Verification = $null
                Settings = $null
                Protection = $null
            }

            $markdown = Format-CgrMigrationExecutionResult -Result $result -Format Markdown
            $markdown | Should -Match 'Replacement Identity Evidence'
            $markdown | Should -Match 'Original repository ID \| 20'
            $markdown | Should -Match 'Archive repository ID \| 20'
            $markdown | Should -Match 'Replacement repository ID \| 30'
            $markdown | Should -Match 'Replacement has distinct identity \| True'
        }
    }
}
