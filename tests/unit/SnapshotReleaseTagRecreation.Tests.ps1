BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Snapshot release tag recreation' {
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
            $script:checkpointTrees = @{ c1 = 'tree-c1'; c2 = 'tree-c2' }
            $script:generatedCommitShas = [System.Collections.Generic.Queue[string]]::new()
            $script:remoteTip = $null
            $script:tagRefs = @{
                v1 = [pscustomobject] @{ object = [pscustomobject] @{ type = 'commit'; sha = 'c1' } }
                v2 = [pscustomobject] @{ object = [pscustomobject] @{ type = 'tag'; sha = 'tag-object-v2' } }
                'v2-alt' = [pscustomobject] @{ object = [pscustomobject] @{ type = 'commit'; sha = 'c2' } }
            }

            Mock Send-CgrActivityEvent {}
            Mock Get-CgrGitCommitIdentity { [pscustomobject] @{ Name = 'CopyGitHubRepo'; Email = 'copy@example.test' } }
            Mock Copy-CgrGitLfsObject { [pscustomobject] @{ IsSuccessful = $true } }
            Mock Invoke-CgrActivityStage { & $Action }
            Mock Invoke-CgrGitHubApiReadRequest {
                $path = [string] $ArgumentList[-1]
                if ($path -notmatch '/git/ref/tags/(.+)$') {
                    throw "Unexpected GitHub API read: $($ArgumentList -join ' ')"
                }
                $tagName = [uri]::UnescapeDataString($Matches[1])
                if (-not $script:tagRefs.ContainsKey($tagName)) {
                    return [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = 'not found' }
                }
                return [pscustomobject] @{ ExitCode = 0; Output = @($script:tagRefs[$tagName] | ConvertTo-Json -Compress -Depth 10); ErrorText = '' }
            }
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
                if ($joined -match 'rev-parse (c[12])\^\{tree\}$') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @($script:checkpointTrees[$Matches[1]]); ErrorText = '' }
                }
                if ($joined -match 'commit-tree ') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @($script:generatedCommitShas.Dequeue()); ErrorText = '' }
                }
                throw "Unexpected native command: $joined"
            }
        }
    }

    It 'recreates one selected lightweight release tag against its generated checkpoint commit' {
        InModuleScope CopyGitHubRepo {
            $script:generatedCommitShas.Enqueue('destination-c1')
            $script:remoteTip = 'destination-c1'
            $plan = [pscustomobject] @{
                SourceHead = [pscustomobject] @{ CommitSha = 'head'; TreeSha = 'tree-head' }
                ReleaseEvidence = @([pscustomobject] @{ TagName = 'v1'; TagObjectType = 'commit'; TagObjectSha = 'c1'; PeeledCommitSha = 'c1' })
                Checkpoints = @([pscustomobject] @{ Order = 1; SourceCommitSha = 'c1'; SourceTreeSha = 'tree-c1'; TagNames = @('v1') })
                FinalHeadCheckpointRequired = $false
            }

            $result = Copy-CgrRepositorySnapshot -SourceRepository $script:sourceRepository -DestinationRepository $script:destinationRepository -BranchName main -CommitMessage unused -ApprovedSourceState $script:sourceState -ReleaseCheckpointPlan $plan

            $result.ReleaseTags.Count | Should -Be 1
            $result.ReleaseTags[0].TagName | Should -Be 'v1'
            $result.ReleaseTags[0].DestinationCommitSha | Should -Be 'destination-c1'
            $result.ReleaseTags[0].DestinationTagType | Should -Be 'lightweight'
            Should -Invoke Invoke-CgrGitCommand -Times 1 -Exactly -ParameterFilter {
                ($ArgumentList -join ' ') -match 'push --atomic https://github.com/acme/destination.git destination-c1:refs/heads/main destination-c1:refs/tags/v1$'
            }
        }
    }

    It 'maps sequential selected tags to the generated commits from reviewed checkpoint order rather than selection order' {
        InModuleScope CopyGitHubRepo {
            $script:generatedCommitShas.Enqueue('destination-c1')
            $script:generatedCommitShas.Enqueue('destination-c2')
            $script:remoteTip = 'destination-c2'
            $plan = [pscustomobject] @{
                SourceHead = [pscustomobject] @{ CommitSha = 'head'; TreeSha = 'tree-head' }
                ReleaseEvidence = @(
                    [pscustomobject] @{ SelectionOrder = 1; TagName = 'v2'; TagObjectType = 'tag'; TagObjectSha = 'tag-object-v2'; PeeledCommitSha = 'c2' },
                    [pscustomobject] @{ SelectionOrder = 2; TagName = 'v1'; TagObjectType = 'commit'; TagObjectSha = 'c1'; PeeledCommitSha = 'c1' }
                )
                Checkpoints = @(
                    [pscustomobject] @{ Order = 1; SourceCommitSha = 'c1'; SourceTreeSha = 'tree-c1'; TagNames = @('v1') },
                    [pscustomobject] @{ Order = 2; SourceCommitSha = 'c2'; SourceTreeSha = 'tree-c2'; TagNames = @('v2') }
                )
                FinalHeadCheckpointRequired = $false
            }

            $result = Copy-CgrRepositorySnapshot -SourceRepository $script:sourceRepository -DestinationRepository $script:destinationRepository -BranchName main -CommitMessage unused -ApprovedSourceState $script:sourceState -ReleaseCheckpointPlan $plan

            ($result.ReleaseTags | Where-Object TagName -EQ 'v1').DestinationCommitSha | Should -Be 'destination-c1'
            ($result.ReleaseTags | Where-Object TagName -EQ 'v2').DestinationCommitSha | Should -Be 'destination-c2'
            ($result.ReleaseTags | Where-Object TagName -EQ 'v2').SourceTagObjectType | Should -Be 'tag'
            ($result.ReleaseTags | Where-Object TagName -EQ 'v2').DestinationTagType | Should -Be 'lightweight'
            Should -Invoke Invoke-CgrGitCommand -Times 1 -Exactly -ParameterFilter {
                $joined = $ArgumentList -join ' '
                $joined -match 'destination-c2:refs/heads/main' -and
                $joined -match 'destination-c2:refs/tags/v2' -and
                $joined -match 'destination-c1:refs/tags/v1'
            }
        }
    }

    It 'recreates multiple selected tags on one shared checkpoint without another checkpoint commit' {
        InModuleScope CopyGitHubRepo {
            $script:generatedCommitShas.Enqueue('destination-shared')
            $script:remoteTip = 'destination-shared'
            $plan = [pscustomobject] @{
                SourceHead = [pscustomobject] @{ CommitSha = 'head'; TreeSha = 'tree-head' }
                ReleaseEvidence = @(
                    [pscustomobject] @{ TagName = 'v2'; TagObjectType = 'tag'; TagObjectSha = 'tag-object-v2'; PeeledCommitSha = 'c2' },
                    [pscustomobject] @{ TagName = 'v2-alt'; TagObjectType = 'commit'; TagObjectSha = 'c2'; PeeledCommitSha = 'c2' }
                )
                Checkpoints = @([pscustomobject] @{ Order = 1; SourceCommitSha = 'c2'; SourceTreeSha = 'tree-c2'; TagNames = @('v2', 'v2-alt') })
                FinalHeadCheckpointRequired = $false
            }

            $result = Copy-CgrRepositorySnapshot -SourceRepository $script:sourceRepository -DestinationRepository $script:destinationRepository -BranchName main -CommitMessage unused -ApprovedSourceState $script:sourceState -ReleaseCheckpointPlan $plan

            $result.GeneratedCommits.Count | Should -Be 1
            $result.ReleaseTags.Count | Should -Be 2
            @($result.ReleaseTags.DestinationCommitSha | Select-Object -Unique) | Should -Be @('destination-shared')
            Should -Invoke Invoke-CgrNativeCommand -Times 1 -Exactly -ParameterFilter { ($ArgumentList -join ' ') -match 'commit-tree tree-c2' }
        }
    }

    It 'does not recreate an unselected source tag' {
        InModuleScope CopyGitHubRepo {
            $script:tagRefs['v-unselected'] = [pscustomobject] @{ object = [pscustomobject] @{ type = 'commit'; sha = 'other' } }
            $script:generatedCommitShas.Enqueue('destination-c1')
            $script:remoteTip = 'destination-c1'
            $plan = [pscustomobject] @{
                SourceHead = [pscustomobject] @{ CommitSha = 'head'; TreeSha = 'tree-head' }
                ReleaseEvidence = @([pscustomobject] @{ TagName = 'v1'; TagObjectType = 'commit'; TagObjectSha = 'c1'; PeeledCommitSha = 'c1' })
                Checkpoints = @([pscustomobject] @{ Order = 1; SourceCommitSha = 'c1'; SourceTreeSha = 'tree-c1'; TagNames = @('v1') })
                FinalHeadCheckpointRequired = $false
            }

            Copy-CgrRepositorySnapshot -SourceRepository $script:sourceRepository -DestinationRepository $script:destinationRepository -BranchName main -CommitMessage unused -ApprovedSourceState $script:sourceState -ReleaseCheckpointPlan $plan | Out-Null

            Should -Invoke Invoke-CgrGitCommand -Times 0 -ParameterFilter { ($ArgumentList -join ' ') -match 'refs/tags/v-unselected' }
            Should -Invoke Invoke-CgrGitHubApiReadRequest -Times 0 -ParameterFilter { ($ArgumentList -join ' ') -match 'v-unselected' }
        }
    }

    It 'fails closed on reviewed tag-target drift before any destination push' {
        InModuleScope CopyGitHubRepo {
            $script:tagRefs.v1.object.sha = 'moved-commit'
            $plan = [pscustomobject] @{
                SourceHead = [pscustomobject] @{ CommitSha = 'head'; TreeSha = 'tree-head' }
                ReleaseEvidence = @([pscustomobject] @{ TagName = 'v1'; TagObjectType = 'commit'; TagObjectSha = 'c1'; PeeledCommitSha = 'c1' })
                Checkpoints = @([pscustomobject] @{ Order = 1; SourceCommitSha = 'c1'; SourceTreeSha = 'tree-c1'; TagNames = @('v1') })
                FinalHeadCheckpointRequired = $false
            }

            { Copy-CgrRepositorySnapshot -SourceRepository $script:sourceRepository -DestinationRepository $script:destinationRepository -BranchName main -CommitMessage unused -ApprovedSourceState $script:sourceState -ReleaseCheckpointPlan $plan } |
                Should -Throw -ErrorId 'SnapshotReleaseTagStateChangedSincePlanning,Copy-CgrRepositorySnapshot'
            Should -Invoke Invoke-CgrGitCommand -Times 0 -ParameterFilter { ($ArgumentList -join ' ') -match ' push ' }
            Should -Invoke Invoke-CgrNativeCommand -Times 0 -ParameterFilter { ($ArgumentList -join ' ') -match 'commit-tree ' }
        }
    }
}
