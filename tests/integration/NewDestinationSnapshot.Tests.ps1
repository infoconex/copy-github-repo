BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force
}

Describe 'New-destination Snapshot orchestration' {
    It 'returns verified provenance for the deterministic new-destination happy path' {
        InModuleScope CopyGitHubRepo {
            $sourceState = [pscustomobject] @{
                RepositoryId = 101
                RepositoryNodeId = 'SRC_node'
                CommitSha = 'source-commit'
                TreeSha = 'source-tree'
            }
            $plan = [pscustomobject] @{
                PSTypeName = 'CopyGitHubRepo.MigrationPlan'
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                SourceVisibility = 'public'
                DestinationVisibility = 'public'
                SourceDefaultBranch = 'main'
                CommitMessage = 'Initial release'
                SkipSettings = $true
                SourceState = $sourceState
                Protection = $null
            }
            $source = [pscustomobject] @{
                FullName = 'infoconex/source'
                Id = 101
                NodeId = 'SRC_node'
            }
            $destination = [pscustomobject] @{
                FullName = 'infoconex/destination'
                HtmlUrl = 'https://github.com/infoconex/destination'
                Id = 202
                NodeId = 'DEST_node'
            }
            $reloadedDestination = [pscustomobject] @{
                FullName = 'infoconex/destination'
                HtmlUrl = 'https://github.com/infoconex/destination'
                Id = 202
                NodeId = 'DEST_node'
            }

            Mock Copy-CgrRepositorySnapshot {
                [pscustomobject] @{
                    Verified = $true
                    BranchName = 'main'
                    CommitSha = 'destination-root'
                    SourceCommitSha = 'source-commit'
                    TreeSha = 'source-tree'
                }
            }
            Mock Get-CgrRepository { $reloadedDestination }
            Mock Invoke-CgrRepositorySnapshotVerification {
                [pscustomobject] @{
                    IsSuccessful = $true
                    SourceTree = 'source-tree'
                    DestinationTree = 'source-tree'
                }
            }

            $result = Invoke-CgrNewDestinationSnapshot `
                -Plan $plan `
                -SourceRepository $source `
                -DestinationRepository $destination `
                -HostName 'github.com'

            $result.Status | Should -Be 'SnapshotVerifiedSettingsSkipped'
            $result.IsVerified | Should -BeTrue
            $result.SnapshotCommitSha | Should -Be 'destination-root'
            $result.SourceTreeSha | Should -Be 'source-tree'
            $result.Provenance.SourceCommitSha | Should -Be 'source-commit'
            $result.Provenance.SourceTreeSha | Should -Be 'source-tree'
            $result.Provenance.DestinationRootCommitSha | Should -Be 'destination-root'
            $result.Provenance.DestinationTreeSha | Should -Be 'source-tree'
            $result.Provenance.VerificationSuccessful | Should -BeTrue
            @($result.CompletedSteps).Name | Should -Be @(
                'CreateDestinationRepository',
                'CopySnapshot',
                'VerifySnapshot',
                'RestoreSupportedSettings',
                'RestoreRepositoryProtection'
            )

            Should -Invoke Copy-CgrRepositorySnapshot -Times 1 -Exactly -ParameterFilter {
                $ApprovedSourceState -eq $sourceState -and
                $BranchName -eq 'main' -and
                $CommitMessage -eq 'Initial release'
            }
            Should -Invoke Get-CgrRepository -Times 1 -Exactly -ParameterFilter {
                $Repository -eq 'infoconex/destination' -and $HostName -eq 'github.com'
            }
            Should -Invoke Invoke-CgrRepositorySnapshotVerification -Times 1 -Exactly -ParameterFilter {
                $ApprovedSourceState -eq $sourceState -and
                $DestinationRepository -eq $reloadedDestination
            }
        }
    }

    It 'records CopySnapshot as the recovery stage when snapshot copy fails' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                PSTypeName = 'CopyGitHubRepo.MigrationPlan'
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                SourceVisibility = 'public'
                DestinationVisibility = 'public'
                SourceDefaultBranch = 'main'
                CommitMessage = 'Initial release'
                SkipSettings = $false
            }
            $source = [pscustomobject] @{
                FullName = 'infoconex/source'
            }
            $destination = [pscustomobject] @{
                FullName = 'infoconex/destination'
                HtmlUrl = 'https://github.com/infoconex/destination'
            }

            Mock Copy-CgrRepositorySnapshot { throw 'snapshot copy failed' }
            Mock Write-CgrMigrationRecoveryReport { 'recovery.json' } -ParameterFilter {
                $Plan -eq $plan -and
                $DestinationRepository -eq $destination -and
                $FailureStage -eq 'CopySnapshot' -and
                @($CompletedSteps).Count -eq 1 -and
                @($CompletedSteps)[0].Name -eq 'CreateDestinationRepository'
            }

            {
                Invoke-CgrNewDestinationSnapshot `
                    -Plan $plan `
                    -SourceRepository $source `
                    -DestinationRepository $destination `
                    -HostName 'github.com'
            } | Should -Throw -ExpectedMessage 'snapshot copy failed'

            Should -Invoke Copy-CgrRepositorySnapshot -Times 1 -Exactly
            Should -Invoke Write-CgrMigrationRecoveryReport -Times 1 -Exactly
        }
    }
}
