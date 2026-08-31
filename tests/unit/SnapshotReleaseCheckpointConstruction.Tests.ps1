BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Snapshot release checkpoint construction' {
    BeforeEach {
        InModuleScope CopyGitHubRepo {
            $script:sourceRepository = [pscustomobject] @{
                FullName = 'acme/source'
                HostName = 'github.com'
                CloneUrl = 'https://github.com/acme/source.git'
            }
            $script:destinationRepository = [pscustomobject] @{
                FullName = 'acme/destination'
                HostName = 'github.com'
                CloneUrl = 'https://github.com/acme/destination.git'
            }
            $script:sourceState = [pscustomobject] @{
                DefaultBranch = 'main'
                CommitSha = 'head'
                TreeSha = 'tree-head'
            }
            $script:checkpointTrees = @{
                c1 = 'tree-c1'
                c2 = 'tree-c2'
                c3 = 'tree-c3'
            }
            $script:generatedCommitShas = [System.Collections.Generic.Queue[string]]::new()
            $script:remoteTip = $null

            Mock Send-CgrActivityEvent {}
            Mock Get-CgrGitCommitIdentity { [pscustomobject] @{ Name = 'CopyGitHubRepo'; Email = 'copy@example.test' } }
            Mock Copy-CgrGitLfsObject { [pscustomobject] @{ IsSuccessful = $true } }
            Mock Invoke-CgrActivityStage { & $Action }
            Mock Invoke-CgrGitCommand {
                $joined = $ArgumentList -join ' '
                if ($joined -match '^clone ' -or $joined -match ' fetch ' -or $joined -match ' push ') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
                }
                if ($joined -match '^ls-remote ') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @("$script:remoteTip`trefs/heads/main"); ErrorText = '' }
                }
                throw "Unexpected Git command: $joined"
            }
            Mock Invoke-CgrNativeCommand {
                $joined = $ArgumentList -join ' '
                if ($joined -match 'rev-parse HEAD\^\{tree\}$') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @($script:sourceState.TreeSha); ErrorText = '' }
                }
                if ($joined -match 'rev-parse HEAD$') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('head'); ErrorText = '' }
                }
                if ($joined -match 'rev-parse (c[123])\^\{tree\}$') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @($script:checkpointTrees[$Matches[1]]); ErrorText = '' }
                }
                if ($joined -match 'commit-tree ') {
                    if ($script:generatedCommitShas.Count -eq 0) {
                        throw "No generated commit SHA queued for: $joined"
                    }
                    return [pscustomobject] @{ ExitCode = 0; Output = @($script:generatedCommitShas.Dequeue()); ErrorText = '' }
                }
                throw "Unexpected native command: $joined"
            }
        }
    }

    It 'creates one selected release as an unrelated root with the reviewed tree' {
        InModuleScope CopyGitHubRepo {
            $script:generatedCommitShas.Enqueue('destination-root')
            $script:remoteTip = 'destination-root'
            $checkpointPlan = [pscustomobject] @{
                SourceHead = [pscustomobject] @{ CommitSha = 'head'; TreeSha = 'tree-head' }
                Checkpoints = @([pscustomobject] @{ Order = 1; SourceCommitSha = 'c1'; SourceTreeSha = 'tree-c1'; TagNames = @('v1.0.0') })
                FinalHeadCheckpointRequired = $false
            }

            $result = Copy-CgrRepositorySnapshot -SourceRepository $script:sourceRepository -DestinationRepository $script:destinationRepository -BranchName main -CommitMessage 'Initial repository commit' -ApprovedSourceState $script:sourceState -ReleaseCheckpointPlan $checkpointPlan

            $result.RootCommitSha | Should -Be 'destination-root'
            $result.CommitSha | Should -Be 'destination-root'
            $result.GeneratedCommits.Count | Should -Be 1
            $result.GeneratedCommits[0].TreeSha | Should -Be 'tree-c1'
            $result.GeneratedCommits[0].Message | Should -Be 'Snapshot release checkpoint 1: v1.0.0'
            Should -Invoke Invoke-CgrGitCommand -Times 1 -Exactly -ParameterFilter { ($ArgumentList -join ' ') -match ' fetch --depth 1 origin c1$' }
            Should -Invoke Invoke-CgrNativeCommand -Times 1 -Exactly -ParameterFilter {
                $joined = $ArgumentList -join ' '
                $joined -match 'commit-tree tree-c1' -and $joined -notmatch ' -p '
            }
        }
    }

    It 'constructs multiple reviewed checkpoints in plan order and appends reviewed HEAD only when required' {
        InModuleScope CopyGitHubRepo {
            $script:generatedCommitShas.Enqueue('destination-c1')
            $script:generatedCommitShas.Enqueue('destination-c2')
            $script:generatedCommitShas.Enqueue('destination-head')
            $script:remoteTip = 'destination-head'
            $checkpointPlan = [pscustomobject] @{
                SourceHead = [pscustomobject] @{ CommitSha = 'head'; TreeSha = 'tree-head' }
                ReleaseEvidence = @(
                    [pscustomobject] @{ SelectionOrder = 1; TagName = 'v2'; PeeledCommitSha = 'c2' },
                    [pscustomobject] @{ SelectionOrder = 2; TagName = 'v1'; PeeledCommitSha = 'c1' }
                )
                Checkpoints = @(
                    [pscustomobject] @{ Order = 1; SourceCommitSha = 'c1'; SourceTreeSha = 'tree-c1'; TagNames = @('v1') },
                    [pscustomobject] @{ Order = 2; SourceCommitSha = 'c2'; SourceTreeSha = 'tree-c2'; TagNames = @('v2') }
                )
                FinalHeadCheckpointRequired = $true
            }

            $result = Copy-CgrRepositorySnapshot -SourceRepository $script:sourceRepository -DestinationRepository $script:destinationRepository -BranchName main -CommitMessage 'ignored-for-checkpoints' -ApprovedSourceState $script:sourceState -ReleaseCheckpointPlan $checkpointPlan

            @($result.GeneratedCommits.Kind) | Should -Be @('ReleaseCheckpoint', 'ReleaseCheckpoint', 'CurrentHead')
            @($result.GeneratedCommits.TreeSha) | Should -Be @('tree-c1', 'tree-c2', 'tree-head')
            @($result.GeneratedCommits.CommitSha) | Should -Be @('destination-c1', 'destination-c2', 'destination-head')
            $result.FinalHeadCommitCreated | Should -BeTrue
            Should -Invoke Invoke-CgrGitCommand -Times 1 -Exactly -ParameterFilter { ($ArgumentList -join ' ') -match ' fetch --depth 1 origin c1$' }
            Should -Invoke Invoke-CgrGitCommand -Times 1 -Exactly -ParameterFilter { ($ArgumentList -join ' ') -match ' fetch --depth 1 origin c2$' }
            Should -Invoke Invoke-CgrNativeCommand -Times 1 -Exactly -ParameterFilter {
                $joined = $ArgumentList -join ' '
                $joined -match 'commit-tree tree-c1' -and $joined -notmatch ' -p '
            }
            Should -Invoke Invoke-CgrNativeCommand -Times 1 -Exactly -ParameterFilter { ($ArgumentList -join ' ') -match 'commit-tree tree-c2 -p destination-c1 -m Snapshot release checkpoint 2: v2$' }
            Should -Invoke Invoke-CgrNativeCommand -Times 1 -Exactly -ParameterFilter { ($ArgumentList -join ' ') -match 'commit-tree tree-head -p destination-c2 -m Snapshot current state$' }
        }
    }

    It 'coalesces duplicate selected releases already sharing one reviewed checkpoint boundary' {
        InModuleScope CopyGitHubRepo {
            $script:generatedCommitShas.Enqueue('destination-shared')
            $script:remoteTip = 'destination-shared'
            $checkpointPlan = [pscustomobject] @{
                SourceHead = [pscustomobject] @{ CommitSha = 'head'; TreeSha = 'tree-head' }
                Checkpoints = @([pscustomobject] @{ Order = 1; SourceCommitSha = 'c2'; SourceTreeSha = 'tree-c2'; TagNames = @('v2-a', 'v2-b') })
                FinalHeadCheckpointRequired = $false
            }

            $result = Copy-CgrRepositorySnapshot -SourceRepository $script:sourceRepository -DestinationRepository $script:destinationRepository -BranchName main -CommitMessage 'unused' -ApprovedSourceState $script:sourceState -ReleaseCheckpointPlan $checkpointPlan

            $result.GeneratedCommits.Count | Should -Be 1
            @($result.GeneratedCommits[0].TagNames) | Should -Be @('v2-a', 'v2-b')
            $result.GeneratedCommits[0].Message | Should -Be 'Snapshot release checkpoint 1: v2-a, v2-b'
            Should -Invoke Invoke-CgrNativeCommand -Times 1 -Exactly -ParameterFilter { ($ArgumentList -join ' ') -match 'commit-tree tree-c2' }
        }
    }

    It 'does not create an equivalent current HEAD commit when reviewed evidence says it is unnecessary' {
        InModuleScope CopyGitHubRepo {
            $script:sourceState.TreeSha = 'tree-c3'
            $script:generatedCommitShas.Enqueue('destination-c3')
            $script:remoteTip = 'destination-c3'
            $checkpointPlan = [pscustomobject] @{
                SourceHead = [pscustomobject] @{ CommitSha = 'head'; TreeSha = 'tree-c3' }
                Checkpoints = @([pscustomobject] @{ Order = 1; SourceCommitSha = 'c3'; SourceTreeSha = 'tree-c3'; TagNames = @('v3') })
                FinalHeadCheckpointRequired = $false
            }

            $result = Copy-CgrRepositorySnapshot -SourceRepository $script:sourceRepository -DestinationRepository $script:destinationRepository -BranchName main -CommitMessage 'unused' -ApprovedSourceState $script:sourceState -ReleaseCheckpointPlan $checkpointPlan

            $result.GeneratedCommits.Count | Should -Be 1
            $result.FinalHeadCommitCreated | Should -BeFalse
            Should -Invoke Invoke-CgrNativeCommand -Times 0 -ParameterFilter { ($ArgumentList -join ' ') -match 'commit-tree tree-c3 -p ' }
        }
    }

    It 'fails closed before push when a reviewed checkpoint commit does not reproduce its planned tree' {
        InModuleScope CopyGitHubRepo {
            $script:checkpointTrees.c1 = 'drifted-tree'
            $checkpointPlan = [pscustomobject] @{
                SourceHead = [pscustomobject] @{ CommitSha = 'head'; TreeSha = 'tree-head' }
                Checkpoints = @([pscustomobject] @{ Order = 1; SourceCommitSha = 'c1'; SourceTreeSha = 'tree-c1'; TagNames = @('v1') })
                FinalHeadCheckpointRequired = $false
            }

            { Copy-CgrRepositorySnapshot -SourceRepository $script:sourceRepository -DestinationRepository $script:destinationRepository -BranchName main -CommitMessage 'unused' -ApprovedSourceState $script:sourceState -ReleaseCheckpointPlan $checkpointPlan } |
                Should -Throw -ErrorId 'SnapshotReleaseCheckpointTreeMismatch,Copy-CgrRepositorySnapshot'
            Should -Invoke Invoke-CgrGitCommand -Times 0 -ParameterFilter { ($ArgumentList -join ' ') -match ' push ' }
        }
    }

    It 'preserves ordinary plain Snapshot as one unrelated current-state root commit' {
        InModuleScope CopyGitHubRepo {
            $script:generatedCommitShas.Enqueue('plain-root')
            $script:remoteTip = 'plain-root'

            $result = Copy-CgrRepositorySnapshot -SourceRepository $script:sourceRepository -DestinationRepository $script:destinationRepository -BranchName main -CommitMessage 'Initial repository commit' -ApprovedSourceState $script:sourceState

            $result.RootCommitSha | Should -Be 'plain-root'
            $result.CommitSha | Should -Be 'plain-root'
            $result.GeneratedCommits.Count | Should -Be 1
            $result.GeneratedCommits[0].Kind | Should -Be 'SnapshotRoot'
            $result.GeneratedCommits[0].TreeSha | Should -Be 'tree-head'
            $result.GeneratedCommits[0].Message | Should -Be 'Initial repository commit'
            Should -Invoke Invoke-CgrGitCommand -Times 0 -ParameterFilter { ($ArgumentList -join ' ') -match ' fetch ' }
            Should -Invoke Invoke-CgrNativeCommand -Times 1 -Exactly -ParameterFilter {
                $joined = $ArgumentList -join ' '
                $joined -match 'commit-tree tree-head' -and $joined -notmatch ' -p '
            }
        }
    }
}
