BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force

    $script:sourceState = [pscustomobject] @{
        ContentMode = 'FullHistory'
        Repository = 'infoconex/source'
        RepositoryId = 101L
        RepositoryNodeId = 'R_source'
        DefaultBranch = 'main'
        Refs = @(
            'refs/heads/feature 2222222222222222222222222222222222222222'
            'refs/heads/main 1111111111111111111111111111111111111111'
            'refs/tags/v1.0.0 3333333333333333333333333333333333333333'
        )
        ReachableCommitCount = 3
        BranchTrees = @('refs/heads/feature feature-tree', 'refs/heads/main main-tree')
        GitLfsObjectsAvailable = $true
    }
    $script:plan = [pscustomobject] @{
        SourceRepository = 'infoconex/source'
        ArchiveRepository = 'infoconex/source-archive'
        DestinationRepository = 'infoconex/source'
        SourceVisibility = 'private'
        DestinationVisibility = 'private'
        SourceDefaultBranch = 'main'
        ContentMode = 'FullHistory'
        SkipSettings = $true
        SourceState = $script:sourceState
    }
    $script:sourceRepository = [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.Repository'; Id = 101L; NodeId = 'R_source'; Name = 'source'; FullName = 'infoconex/source'; Owner = 'infoconex'
        Visibility = 'private'; DefaultBranch = 'main'; Description = 'Source repository.'; HtmlUrl = 'https://github.com/infoconex/source'
        CloneUrl = 'https://github.com/infoconex/source.git'; HostName = 'github.com'
    }
    $script:archiveRepository = [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.Repository'; Id = 101L; NodeId = 'R_source'; Name = 'source-archive'; FullName = 'infoconex/source-archive'; Owner = 'infoconex'
        Visibility = 'private'; DefaultBranch = 'main'; Description = 'Source repository.'; HtmlUrl = 'https://github.com/infoconex/source-archive'
        CloneUrl = 'https://github.com/infoconex/source-archive.git'; HostName = 'github.com'
    }
    $script:replacementRepository = [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.Repository'; Id = 202L; NodeId = 'R_replacement'; Name = 'source'; FullName = 'infoconex/source'; Owner = 'infoconex'
        Visibility = 'private'; DefaultBranch = 'main'; Description = $null; HtmlUrl = 'https://github.com/infoconex/source'
        CloneUrl = 'https://github.com/infoconex/source.git'; HostName = 'github.com'
    }
}

Describe 'Same-name FullHistory replacement' {
    It 'stops before replacement creation when the archived repository no longer matches approved FullHistory state' {
        InModuleScope CopyGitHubRepo -Parameters @{
            PlanFixture = $script:plan
            SourceFixture = $script:sourceRepository
            ArchiveFixture = $script:archiveRepository
        } {
            $script:assertCallCount = 0
            Mock Assert-CgrApprovedSourceState {
                $script:assertCallCount++
                if ($script:assertCallCount -eq 2) {
                    $exception = [System.InvalidOperationException]::new('Archived source no longer matches approved FullHistory state.')
                    throw [System.Management.Automation.ErrorRecord]::new($exception, 'SourceStateChangedSincePlanning', [System.Management.Automation.ErrorCategory]::InvalidResult, 'infoconex/source')
                }
                [pscustomobject] @{ DefaultBranch = 'main' }
            }
            Mock Rename-CgrGitHubRepository { $ArchiveFixture }
            Mock New-CgrGitHubRepository { throw 'Replacement creation must not occur after archive state mismatch.' }
            Mock Write-CgrSameNameRecoveryReport { 'recovery.json' }

            { Invoke-CgrSameNameFullHistoryReplacement -Plan $PlanFixture -SourceRepository $SourceFixture } |
                Should -Throw -ErrorId 'SourceStateChangedSincePlanning'

            Should -Invoke Assert-CgrApprovedSourceState -Times 2 -Exactly
            Should -Invoke Rename-CgrGitHubRepository -Times 1 -Exactly
            Should -Invoke New-CgrGitHubRepository -Times 0 -Exactly
            Should -Invoke Write-CgrSameNameRecoveryReport -Times 1 -Exactly -ParameterFilter {
                $FailureStage -eq 'VerifyArchivedSourceFullHistory' -and
                $SourceRepositoryId -eq 101 -and
                $SourceFullHistoryRefCount -eq 3 -and
                $SourceReachableCommitCount -eq 3
            }
        }
    }

    It 'copies approved FullHistory from the verified archive after replacement creation' {
        InModuleScope CopyGitHubRepo -Parameters @{
            PlanFixture = $script:plan
            SourceFixture = $script:sourceRepository
            ArchiveFixture = $script:archiveRepository
            ReplacementFixture = $script:replacementRepository
        } {
            Mock Assert-CgrApprovedSourceState { [pscustomobject] @{ DefaultBranch = 'main' } }
            Mock Rename-CgrGitHubRepository { $ArchiveFixture }
            Mock New-CgrGitHubRepository { $ReplacementFixture }
            Mock Copy-CgrRepositoryFullHistory {
                [pscustomobject] @{
                    PSTypeName = 'CopyGitHubRepo.FullHistoryCopyResult'
                    SourceRepository = 'infoconex/source-archive'
                    DestinationRepository = 'infoconex/source'
                    DefaultBranch = 'main'
                    IsSuccessful = $true
                    CopiedSourceEvidence = [pscustomobject] @{ Refs = @($ApprovedSourceState.Refs); ReachableCommitCount = $ApprovedSourceState.ReachableCommitCount; BranchTrees = @($ApprovedSourceState.BranchTrees) }
                }
            } -ParameterFilter {
                $SourceRepository.FullName -eq 'infoconex/source-archive' -and
                $DestinationRepository.FullName -eq 'infoconex/source' -and
                $null -ne $ApprovedSourceState
            }
            Mock Get-CgrRepository { $ReplacementFixture } -ParameterFilter { $Repository -eq 'infoconex/source' }
            Mock Invoke-CgrApprovedFullHistoryVerification {
                [pscustomobject] @{
                    PSTypeName = 'CopyGitHubRepo.MigrationVerificationResult'
                    ContentMode = 'FullHistory'
                    SourceRepository = 'infoconex/source-archive'
                    DestinationRepository = 'infoconex/source'
                    IsSuccessful = $true
                    Checks = @()
                }
            }
            Mock Set-CgrGitHubRepositorySetting { throw 'Settings are skipped in this test.' }

            $result = Invoke-CgrSameNameFullHistoryReplacement -Plan $PlanFixture -SourceRepository $SourceFixture

            $result.Status | Should -Be 'SameNameFullHistoryVerifiedSettingsSkipped'
            $result.SourceRepositoryId | Should -Be 101
            $result.ArchiveRepository | Should -Be 'infoconex/source-archive'
            $result.ArchiveRepositoryId | Should -Be 101
            $result.DestinationRepository | Should -Be 'infoconex/source'
            $result.DestinationRepositoryId | Should -Be 202
            $result.SourceFullHistoryRefCount | Should -Be 3
            $result.SourceReachableCommitCount | Should -Be 3
            $result.IsVerified | Should -BeTrue
            Should -Invoke Assert-CgrApprovedSourceState -Times 2 -Exactly
            Should -Invoke Copy-CgrRepositoryFullHistory -Times 1 -Exactly
            Should -Invoke Invoke-CgrApprovedFullHistoryVerification -Times 1 -Exactly
            Should -Invoke Set-CgrGitHubRepositorySetting -Times 0 -Exactly
        }
    }
}
