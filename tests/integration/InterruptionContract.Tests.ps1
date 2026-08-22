BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force
}

Describe 'Interruption and signal-handling contract' {
    It 'does not emit post-mutation recovery evidence when cancellation occurs before mutation' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{
                Id = 101L; NodeId = 'R_source'; FullName = 'infoconex/source'; Owner = 'infoconex'; Visibility = 'private'; DefaultBranch = 'main'
            }
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                ContentMode = 'Snapshot'
                SourceDefaultBranch = 'main'
                CommitMessage = 'Initial repository commit'
                SkipSettings = $false
                SourceState = [pscustomobject] @{
                    ContentMode = 'Snapshot'; Repository = 'infoconex/source'; RepositoryId = 101L; RepositoryNodeId = 'R_source'
                    DefaultBranch = 'main'; CommitSha = 'source-commit'; TreeSha = 'source-tree'
                }
            }

            Mock Assert-CgrApprovedSourceState { [pscustomobject] @{ CommitSha = 'source-commit'; TreeSha = 'source-tree' } }
            Mock Assert-CgrLocalResourcePreflight { throw [System.OperationCanceledException]::new('Simulated pre-mutation interruption.') }
            Mock New-CgrGitHubRepository { throw 'Destination creation must not run.' }
            Mock Write-CgrMigrationRecoveryReport { throw 'Recovery reporting must not run before mutation.' }

            { Invoke-CgrApprovedMigrationPlan -Plan $plan -SourceRepository $source } |
                Should -Throw -ExceptionType ([System.OperationCanceledException])

            Should -Invoke New-CgrGitHubRepository -Times 0 -Exactly
            Should -Invoke Write-CgrMigrationRecoveryReport -Times 0 -Exactly
        }
    }

    It 'attempts normal recovery reporting when cancellation is catchable after destination creation' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{
                Id = 101L; NodeId = 'R_source'; FullName = 'infoconex/source'; Owner = 'infoconex'; Visibility = 'private'; DefaultBranch = 'main'
            }
            $destination = [pscustomobject] @{
                Id = 202L; NodeId = 'R_destination'; FullName = 'infoconex/destination'; Owner = 'infoconex'; Visibility = 'private'; DefaultBranch = 'main'
                HtmlUrl = 'https://github.com/infoconex/destination'
            }
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                ContentMode = 'Snapshot'
                SourceDefaultBranch = 'main'
                CommitMessage = 'Initial repository commit'
                SkipSettings = $false
                SourceState = [pscustomobject] @{
                    ContentMode = 'Snapshot'; Repository = 'infoconex/source'; RepositoryId = 101L; RepositoryNodeId = 'R_source'
                    DefaultBranch = 'main'; CommitSha = 'source-commit'; TreeSha = 'source-tree'
                }
            }

            Mock Assert-CgrApprovedSourceState { [pscustomobject] @{ CommitSha = 'source-commit'; TreeSha = 'source-tree' } }
            Mock Assert-CgrLocalResourcePreflight { [pscustomobject] @{ IsSufficient = $true } }
            Mock New-CgrGitHubRepository { $destination }
            Mock Copy-CgrRepositorySnapshot { throw [System.OperationCanceledException]::new('Simulated post-create interruption.') }
            Mock Write-CgrMigrationRecoveryReport { 'C:\recovery\interrupted.json' } -ParameterFilter {
                $FailureStage -eq 'CopySnapshot' -and
                $DestinationRepository.FullName -eq 'infoconex/destination' -and
                @($CompletedSteps).Count -eq 1 -and
                @($CompletedSteps)[0].Name -eq 'CreateDestinationRepository'
            }

            { Invoke-CgrApprovedMigrationPlan -Plan $plan -SourceRepository $source } |
                Should -Throw -ExceptionType ([System.OperationCanceledException])

            Should -Invoke New-CgrGitHubRepository -Times 1 -Exactly
            Should -Invoke Write-CgrMigrationRecoveryReport -Times 1 -Exactly
        }
    }

    It 'attempts same-name recovery reporting when cancellation is catchable after archive mutation' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{
                Id = 101L; NodeId = 'R_source'; FullName = 'infoconex/source'; Owner = 'infoconex'; Visibility = 'private'; DefaultBranch = 'main'
            }
            $plan = [pscustomobject] @{
                Mode = 'SameNameReplacement'
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/source'
                ArchiveRepository = 'infoconex/source-archive'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                ContentMode = 'Snapshot'
                SourceDefaultBranch = 'main'
                CommitMessage = 'Initial repository commit'
                SkipSettings = $false
                SourceState = [pscustomobject] @{
                    ContentMode = 'Snapshot'; Repository = 'infoconex/source'; RepositoryId = 101L; RepositoryNodeId = 'R_source'
                    DefaultBranch = 'main'; CommitSha = 'source-commit'; TreeSha = 'source-tree'
                }
            }

            Mock Assert-CgrApprovedSourceState { [pscustomobject] @{ CommitSha = 'source-commit'; TreeSha = 'source-tree' } }
            Mock Rename-CgrGitHubRepository {
                [pscustomobject] @{
                    Id = 101L; NodeId = 'R_source'; FullName = 'infoconex/source-archive'; Owner = 'infoconex'; Visibility = 'private'; DefaultBranch = 'main'
                }
            }
            Mock New-CgrGitHubRepository { throw [System.OperationCanceledException]::new('Simulated interruption after archive rename.') }
            Mock Write-CgrSameNameRecoveryReport { 'C:\recovery\same-name-interrupted.json' } -ParameterFilter {
                $FailureStage -eq 'CreateReplacementRepository' -and
                $ArchiveRepository.FullName -eq 'infoconex/source-archive' -and
                @($CompletedSteps).Count -eq 2 -and
                @($CompletedSteps)[0].Name -eq 'PreserveSourceAsArchive' -and
                @($CompletedSteps)[1].Name -eq 'VerifyArchivedSource'
            }

            { Invoke-CgrSameNameSnapshotReplacement -Plan $plan -SourceRepository $source } |
                Should -Throw -ExceptionType ([System.OperationCanceledException])

            Should -Invoke Rename-CgrGitHubRepository -Times 1 -Exactly
            Should -Invoke New-CgrGitHubRepository -Times 1 -Exactly
            Should -Invoke Write-CgrSameNameRecoveryReport -Times 1 -Exactly
        }
    }
}
