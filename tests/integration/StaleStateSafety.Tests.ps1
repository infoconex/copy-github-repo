BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Stale source and replacement state safety' {
    BeforeEach {
        InModuleScope CopyGitHubRepo {
            Mock Get-CgrRepositoryDefaultBranchTree {
                [pscustomobject] @{
                    BranchName = 'main'
                    CommitSha = 'approved-commit'
                    TreeSha = 'approved-tree'
                    GitLfsObjectsAvailable = $true
                    GitLfsPointerFiles = @()
                }
            }
        }
    }

    It 'rejects source commit drift after plan approval' {
        InModuleScope CopyGitHubRepo {
            Mock Get-CgrRepositoryDefaultBranchTree {
                [pscustomobject] @{
                    BranchName = 'main'
                    CommitSha = 'changed-commit'
                    TreeSha = 'changed-tree'
                    GitLfsObjectsAvailable = $true
                    GitLfsPointerFiles = @()
                }
            }
            $repository = [pscustomobject] @{ FullName = 'acme/source'; Id = 10L; NodeId = 'R_source' }
            $state = [pscustomobject] @{
                Repository = 'acme/source'; RepositoryId = 10L; RepositoryNodeId = 'R_source'; ContentMode = 'Snapshot'
                DefaultBranch = 'main'; CommitSha = 'approved-commit'; TreeSha = 'approved-tree'
                GitLfsObjectsAvailable = $true; GitLfsPointerFiles = @()
            }

            { Assert-CgrApprovedSourceState -Repository $repository -SourceState $state } |
                Should -Throw -ErrorId 'SourceStateChangedSincePlanning,Assert-CgrApprovedSourceState'
        }
    }

    It 'rejects source repository identity drift even when the name is unchanged' {
        InModuleScope CopyGitHubRepo {
            $repository = [pscustomobject] @{ FullName = 'acme/source'; Id = 99L; NodeId = 'R_other' }
            $state = [pscustomobject] @{
                Repository = 'acme/source'; RepositoryId = 10L; RepositoryNodeId = 'R_source'; ContentMode = 'Snapshot'
                DefaultBranch = 'main'; CommitSha = 'approved-commit'; TreeSha = 'approved-tree'
                GitLfsObjectsAvailable = $true; GitLfsPointerFiles = @()
            }

            { Assert-CgrApprovedSourceState -Repository $repository -SourceState $state } |
                Should -Throw -ErrorId 'SourceStateChangedSincePlanning,Assert-CgrApprovedSourceState'
        }
    }

    It 'rejects a repository rename when name changes are not allowed' {
        InModuleScope CopyGitHubRepo {
            $repository = [pscustomobject] @{ FullName = 'acme/renamed'; Id = 10L; NodeId = 'R_source' }
            $state = [pscustomobject] @{
                Repository = 'acme/source'; RepositoryId = 10L; RepositoryNodeId = 'R_source'; ContentMode = 'Snapshot'
                DefaultBranch = 'main'; CommitSha = 'approved-commit'; TreeSha = 'approved-tree'
                GitLfsObjectsAvailable = $true; GitLfsPointerFiles = @()
            }

            { Assert-CgrApprovedSourceState -Repository $repository -SourceState $state } |
                Should -Throw -ErrorId 'SourceStateChangedSincePlanning,Assert-CgrApprovedSourceState'
        }
    }

    It 'permits the expected same repository rename when immutable identity and content still match' {
        InModuleScope CopyGitHubRepo {
            $repository = [pscustomobject] @{ FullName = 'acme/source-archive'; Id = 10L; NodeId = 'R_source' }
            $state = [pscustomobject] @{
                Repository = 'acme/source'; RepositoryId = 10L; RepositoryNodeId = 'R_source'; ContentMode = 'Snapshot'
                DefaultBranch = 'main'; CommitSha = 'approved-commit'; TreeSha = 'approved-tree'
                GitLfsObjectsAvailable = $true; GitLfsPointerFiles = @()
            }

            { Assert-CgrApprovedSourceState -Repository $repository -SourceState $state -AllowRepositoryNameChange } |
                Should -Not -Throw
        }
    }

    It 'rejects replacement identity collisions with the preserved source repository' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'acme/source'; Id = 10L }
            $archive = [pscustomobject] @{ FullName = 'acme/source-archive'; Id = 10L }
            $replacement = [pscustomobject] @{ FullName = 'acme/source'; Id = 10L }

            { Assert-CgrReplacementRepositoryIdentity -SourceRepository $source -ArchiveRepository $archive -ReplacementRepository $replacement } |
                Should -Throw -ErrorId 'ReplacementRepositoryIdentityCollision,Assert-CgrReplacementRepositoryIdentity'
        }
    }

    It 'rejects an archive that resolves to a different repository identity' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'acme/source'; Id = 10L }
            $archive = [pscustomobject] @{ FullName = 'acme/source-archive'; Id = 11L }
            $replacement = [pscustomobject] @{ FullName = 'acme/source'; Id = 12L }

            { Assert-CgrReplacementRepositoryIdentity -SourceRepository $source -ArchiveRepository $archive -ReplacementRepository $replacement } |
                Should -Throw -ErrorId 'PreservedRepositoryIdentityMismatch,Assert-CgrReplacementRepositoryIdentity'
        }
    }
}
