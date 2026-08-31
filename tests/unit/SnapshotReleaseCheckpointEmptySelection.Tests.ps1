BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Snapshot release checkpoint empty selection construction' {
    It 'falls back to the ordinary unrelated current-state root when the reviewed selection has no checkpoints' {
        InModuleScope CopyGitHubRepo {
            $sourceRepository = [pscustomobject] @{
                FullName = 'acme/source'
                HostName = 'github.com'
                CloneUrl = 'https://github.com/acme/source.git'
            }
            $destinationRepository = [pscustomobject] @{
                FullName = 'acme/destination'
                HostName = 'github.com'
                CloneUrl = 'https://github.com/acme/destination.git'
            }
            $sourceState = [pscustomobject] @{
                DefaultBranch = 'main'
                CommitSha = 'head'
                TreeSha = 'tree-head'
            }
            $checkpointPlan = [pscustomobject] @{
                SourceHead = [pscustomobject] @{ CommitSha = 'head'; TreeSha = 'tree-head' }
                ReleaseEvidence = @()
                Checkpoints = @()
                FinalHeadCheckpointRequired = $false
            }

            Mock Send-CgrActivityEvent {}
            Mock Get-CgrGitCommitIdentity { [pscustomobject] @{ Name = 'CopyGitHubRepo'; Email = 'copy@example.test' } }
            Mock Copy-CgrGitLfsObject { [pscustomobject] @{ IsSuccessful = $true } }
            Mock Invoke-CgrActivityStage { & $Action }
            Mock Invoke-CgrGitCommand {
                $joined = $ArgumentList -join ' '
                if ($joined -match '^clone ' -or $joined -match ' push ') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
                }
                if ($joined -match '^ls-remote ') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @("destination-root`trefs/heads/main"); ErrorText = '' }
                }
                throw "Unexpected Git command: $joined"
            }
            Mock Invoke-CgrNativeCommand {
                $joined = $ArgumentList -join ' '
                if ($joined -match 'rev-parse HEAD\^\{tree\}$') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('tree-head'); ErrorText = '' }
                }
                if ($joined -match 'rev-parse HEAD$') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('head'); ErrorText = '' }
                }
                if ($joined -match 'commit-tree tree-head' -and $joined -notmatch ' -p ') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('destination-root'); ErrorText = '' }
                }
                throw "Unexpected native command: $joined"
            }

            $result = Copy-CgrRepositorySnapshot `
                -SourceRepository $sourceRepository `
                -DestinationRepository $destinationRepository `
                -BranchName main `
                -CommitMessage 'Initial repository commit' `
                -ApprovedSourceState $sourceState `
                -ReleaseCheckpointPlan $checkpointPlan

            $result.RootCommitSha | Should -Be 'destination-root'
            $result.CommitSha | Should -Be 'destination-root'
            $result.GeneratedCommits.Count | Should -Be 1
            $result.GeneratedCommits[0].Kind | Should -Be 'SnapshotRoot'
            $result.GeneratedCommits[0].TreeSha | Should -Be 'tree-head'
            $result.GeneratedCommits[0].Message | Should -Be 'Initial repository commit'
            $result.ReleaseCheckpointPlan.SourceHead.CommitSha | Should -Be 'head'
            @($result.ReleaseCheckpointPlan.Checkpoints).Count | Should -Be 0
            @($result.ReleaseCheckpointPlan.ReleaseEvidence).Count | Should -Be 0
            Should -Invoke Invoke-CgrGitCommand -Times 0 -ParameterFilter { ($ArgumentList -join ' ') -match ' fetch ' }
        }
    }
}
