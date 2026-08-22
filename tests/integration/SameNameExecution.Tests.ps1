BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force
}

Describe 'Same-name replacement execution safety' {
    BeforeEach {
        $script:sourceState = [pscustomobject] @{
            ContentMode = 'Snapshot'; Repository = 'infoconex/source'; RepositoryId = 101L; RepositoryNodeId = 'R_source'
            DefaultBranch = 'main'; CommitSha = 'source-commit'; TreeSha = 'matching-tree'; GitLfsObjectsAvailable = $false; GitLfsPointerFiles = @()
        }
        $script:plan = [pscustomobject] @{
            SourceRepository = 'infoconex/source'; ArchiveRepository = 'infoconex/source-archive'; DestinationRepository = 'infoconex/source'
            SourceVisibility = 'private'; DestinationVisibility = 'private'; ContentMode = 'Snapshot'; SourceDefaultBranch = 'main'
            CommitMessage = 'Initial release'; SkipSettings = $true; SourceState = $script:sourceState
        }
        $script:sourceRepository = [pscustomobject] @{
            Id = 101L; NodeId = 'R_source'; FullName = 'infoconex/source'; Owner = 'infoconex'; Visibility = 'private'; DefaultBranch = 'main'
            Description = 'Source repository.'; CloneUrl = 'https://github.com/infoconex/source.git'; HostName = 'github.com'
        }
        $script:archiveRepository = [pscustomobject] @{
            Id = 101L; NodeId = 'R_source'; FullName = 'infoconex/source-archive'; Owner = 'infoconex'; Visibility = 'private'; DefaultBranch = 'main'
            Description = 'Source repository.'; HtmlUrl = 'https://github.com/infoconex/source-archive'; CloneUrl = 'https://github.com/infoconex/source-archive.git'; HostName = 'github.com'
        }
        $script:destinationRepository = [pscustomobject] @{
            Id = 202L; NodeId = 'R_destination'; FullName = 'infoconex/source'; Owner = 'infoconex'; Visibility = 'private'; DefaultBranch = 'main'
            HtmlUrl = 'https://github.com/infoconex/source'; CloneUrl = 'https://github.com/infoconex/source.git'; HostName = 'github.com'
        }
    }

    It 'requires the exact source archive and replacement confirmation' {
        InModuleScope CopyGitHubRepo -Parameters @{ PlanFixture = $script:plan } {
            { Assert-CgrSameNameReplacementConfirmation -Plan $PlanFixture -Confirmation 'yes' } |
                Should -Throw -ErrorId 'SameNameReplacementConfirmationRequired,Assert-CgrSameNameReplacementConfirmation'
            $expected = 'SOURCE=infoconex/source;ARCHIVE=infoconex/source-archive;REPLACEMENT=infoconex/source'
            Assert-CgrSameNameReplacementConfirmation -Plan $PlanFixture -Confirmation $expected | Should -Be $expected
        }
    }

    It 'stops before replacement creation when the archived Snapshot state no longer matches the approved plan' {
        InModuleScope CopyGitHubRepo -Parameters @{
            PlanFixture = $script:plan
            SourceRepositoryFixture = $script:sourceRepository
            ArchiveRepositoryFixture = $script:archiveRepository
        } {
            $script:assertCallCount = 0
            Mock Assert-CgrApprovedSourceState {
                $script:assertCallCount++
                if ($script:assertCallCount -eq 2) {
                    $exception = [System.InvalidOperationException]::new('Archived source changed.')
                    throw [System.Management.Automation.ErrorRecord]::new($exception, 'SourceStateChangedSincePlanning', [System.Management.Automation.ErrorCategory]::InvalidResult, 'infoconex/source')
                }
                [pscustomobject] @{ DefaultBranch = 'main'; CommitSha = 'source-commit'; TreeSha = 'matching-tree' }
            }
            Mock Rename-CgrGitHubRepository { $ArchiveRepositoryFixture }
            Mock New-CgrGitHubRepository { throw 'Replacement creation must not occur after archive verification failure.' }
            Mock Write-CgrSameNameRecoveryReport { 'C:\recovery\same-name.json' }

            { Invoke-CgrSameNameSnapshotReplacement -Plan $PlanFixture -SourceRepository $SourceRepositoryFixture } |
                Should -Throw -ErrorId 'SourceStateChangedSincePlanning'

            Should -Invoke Assert-CgrApprovedSourceState -Times 2 -Exactly
            Should -Invoke Rename-CgrGitHubRepository -Times 1 -Exactly
            Should -Invoke New-CgrGitHubRepository -Times 0 -Exactly
            Should -Invoke Write-CgrSameNameRecoveryReport -Times 1 -Exactly -ParameterFilter {
                $FailureStage -eq 'VerifyArchivedSource' -and $ArchiveRepository.FullName -eq 'infoconex/source-archive'
            }
        }
    }

    It 'copies the approved Snapshot from the verified archive only after replacement creation and records identity evidence' {
        InModuleScope CopyGitHubRepo -Parameters @{
            PlanFixture = $script:plan
            SourceRepositoryFixture = $script:sourceRepository
            ArchiveRepositoryFixture = $script:archiveRepository
            DestinationRepositoryFixture = $script:destinationRepository
        } {
            Mock Assert-CgrApprovedSourceState { [pscustomobject] @{ DefaultBranch = 'main'; CommitSha = 'source-commit'; TreeSha = 'matching-tree' } }
            Mock Rename-CgrGitHubRepository { $ArchiveRepositoryFixture }
            Mock New-CgrGitHubRepository { $DestinationRepositoryFixture }
            Mock Copy-CgrRepositorySnapshot {
                [pscustomobject] @{ BranchName = 'main'; SourceCommitSha = 'source-commit'; TreeSha = 'matching-tree'; CommitSha = '0123456789abcdef0123456789abcdef01234567'; Verified = $true }
            } -ParameterFilter {
                $SourceRepository.FullName -eq 'infoconex/source-archive' -and
                $DestinationRepository.FullName -eq 'infoconex/source' -and
                $null -ne $ApprovedSourceState
            }
            Mock Get-CgrRepository { $DestinationRepositoryFixture }
            Mock Invoke-CgrRepositorySnapshotVerification { [pscustomobject] @{ IsSuccessful = $true; DestinationTree = 'matching-tree' } } -ParameterFilter {
                $SourceRepository.FullName -eq 'infoconex/source-archive' -and
                $DestinationRepository.FullName -eq 'infoconex/source' -and
                $null -ne $ApprovedSourceState
            }
            Mock Write-CgrMigrationExecutionReport { $null }

            $result = Invoke-CgrSameNameSnapshotReplacement -Plan $PlanFixture -SourceRepository $SourceRepositoryFixture

            $result.Status | Should -Be 'SameNameSnapshotVerifiedSettingsSkipped'
            $result.SourceRepositoryId | Should -Be 101
            $result.ArchiveRepository | Should -Be 'infoconex/source-archive'
            $result.ArchiveRepositoryId | Should -Be 101
            $result.DestinationRepository | Should -Be 'infoconex/source'
            $result.DestinationRepositoryId | Should -Be 202
            $result.OriginalRepositoryId | Should -Be 101
            $result.ArchivedOriginalIdentityPreserved | Should -BeTrue
            $result.ReplacementDestinationRepositoryId | Should -Be 202
            $result.ReplacementHasDistinctIdentity | Should -BeTrue
            $result.SourceTreeSha | Should -Be 'matching-tree'
            $result.ApprovedSourceState | Should -Be $PlanFixture.SourceState
            $result.ActualCopiedSourceState.TreeSha | Should -Be 'matching-tree'
            $result.IsVerified | Should -BeTrue
            @($result.CompletedSteps).Count | Should -Be 8
            @($result.CompletedSteps)[0].Name | Should -Be 'PreserveSourceAsArchive'
            @($result.CompletedSteps)[1].Name | Should -Be 'VerifyArchivedSource'
            @($result.CompletedSteps)[2].Name | Should -Be 'CreateReplacementRepository'
            @($result.CompletedSteps)[3].Name | Should -Be 'VerifyReplacementRepositoryIdentity'
            Should -Invoke Assert-CgrApprovedSourceState -Times 2 -Exactly
            Should -Invoke Copy-CgrRepositorySnapshot -Times 1 -Exactly
            Should -Invoke Invoke-CgrRepositorySnapshotVerification -Times 1 -Exactly
        }
    }

    It 'stops before content copy when the replacement repository reuses source identity' {
        $collidingDestination = $script:destinationRepository.PSObject.Copy()
        $collidingDestination.Id = 101L
        InModuleScope CopyGitHubRepo -Parameters @{
            PlanFixture = $script:plan
            SourceRepositoryFixture = $script:sourceRepository
            ArchiveRepositoryFixture = $script:archiveRepository
            DestinationRepositoryFixture = $collidingDestination
        } {
            Mock Assert-CgrApprovedSourceState { [pscustomobject] @{ DefaultBranch = 'main'; CommitSha = 'source-commit'; TreeSha = 'matching-tree' } }
            Mock Rename-CgrGitHubRepository { $ArchiveRepositoryFixture }
            Mock New-CgrGitHubRepository { $DestinationRepositoryFixture }
            Mock Copy-CgrRepositorySnapshot { throw 'Content copy must not run after replacement identity collision.' }
            Mock Write-CgrSameNameRecoveryReport { 'C:\recovery\same-name.json' }

            { Invoke-CgrSameNameSnapshotReplacement -Plan $PlanFixture -SourceRepository $SourceRepositoryFixture } |
                Should -Throw -ErrorId 'ReplacementRepositoryIdentityCollision,Assert-CgrReplacementRepositoryIdentity'
            Should -Invoke Copy-CgrRepositorySnapshot -Times 0 -Exactly
            Should -Invoke Write-CgrSameNameRecoveryReport -Times 1 -Exactly -ParameterFilter {
                $FailureStage -eq 'VerifyReplacementRepositoryIdentity' -and $SourceRepositoryId -eq 101
            }
        }
    }
}
