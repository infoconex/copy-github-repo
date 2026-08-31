BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Snapshot release checkpoint planning evidence' {
    BeforeEach {
        InModuleScope CopyGitHubRepo {
            $script:repository = [pscustomobject] @{ FullName = 'acme/widget'; DefaultBranch = 'main' }
            $script:sourceState = [pscustomobject] @{ DefaultBranch = 'main'; CommitSha = 'head'; TreeSha = 'tree-head' }
            $script:releaseSelection = [pscustomobject] @{
                AvailableReleaseCount = 3
                SelectedReleaseCount = 3
                SelectedAssetCount = 0
                IncludePatterns = @()
                ExcludePatterns = @()
                IncludePrerelease = $false
                IncludeDraftReleases = $false
                ReleaseCount = $null
                Releases = @(
                    [pscustomobject] @{ ReleaseId = 30; TagName = 'v3'; TargetCommitSha = 'c3' },
                    [pscustomobject] @{ ReleaseId = 10; TagName = 'v1'; TargetCommitSha = 'c1' },
                    [pscustomobject] @{ ReleaseId = 20; TagName = 'v2'; TargetCommitSha = 'c2' }
                )
            }

            Mock Invoke-CgrGitHubApiReadRequest {
                $joined = $ArgumentList -join ' '
                if ($joined -match '/git/ref/tags/(v\d+)') {
                    $tag = $Matches[1]
                    $type = if ($tag -eq 'v2') { 'tag' } else { 'commit' }
                    return [pscustomobject] @{ ExitCode = 0; Output = @(([pscustomobject] @{ object = [pscustomobject] @{ type = $type; sha = "ref-$tag" } } | ConvertTo-Json -Compress)); ErrorText = '' }
                }
                if ($joined -match '/commits/(c\d+)') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @("tree-$($Matches[1])"); ErrorText = '' }
                }
                if ($joined -match '/compare/([^ ]+)\.\.\.([^ ]+)') {
                    $left = $Matches[1]
                    $right = $Matches[2]
                    $rank = @{ c1 = 1; c2 = 2; c3 = 3; head = 4 }
                    $status = if ($rank[$left] -lt $rank[$right]) { 'ahead' } elseif ($rank[$left] -gt $rank[$right]) { 'behind' } else { 'identical' }
                    return [pscustomobject] @{ ExitCode = 0; Output = @($status); ErrorText = '' }
                }
                throw "Unexpected read request: $joined"
            }
        }
    }

    It 'keeps release selection order separate from checkpoint Git-ancestry order' {
        InModuleScope CopyGitHubRepo {
            $result = New-CgrSnapshotReleaseCheckpointPlan -Repository $script:repository -ReleaseSelection $script:releaseSelection -SourceState $script:sourceState
            @($result.ReleaseEvidence.TagName) | Should -Be @('v3', 'v1', 'v2')
            @($result.ReleaseEvidence.SelectionOrder) | Should -Be @(1, 2, 3)
            @($result.Checkpoints.SourceCommitSha) | Should -Be @('c1', 'c2', 'c3')
            @($result.Checkpoints.TagNames[0]) | Should -Be @('v1')
            $result.FinalHeadCheckpointRequired | Should -BeTrue
            $result.PlannedSnapshotCommitCount | Should -Be 4
            $result.SourceHead.CommitSha | Should -Be 'head'
            $result.SourceHead.TreeSha | Should -Be 'tree-head'
        }
    }

    It 'captures annotated and lightweight tag-reference evidence while using peeled commit targets' {
        InModuleScope CopyGitHubRepo {
            $result = New-CgrSnapshotReleaseCheckpointPlan -Repository $script:repository -ReleaseSelection $script:releaseSelection -SourceState $script:sourceState
            ($result.ReleaseEvidence | Where-Object TagName -EQ 'v2').TagObjectType | Should -Be 'tag'
            ($result.ReleaseEvidence | Where-Object TagName -EQ 'v2').TagObjectSha | Should -Be 'ref-v2'
            ($result.ReleaseEvidence | Where-Object TagName -EQ 'v2').PeeledCommitSha | Should -Be 'c2'
            ($result.ReleaseEvidence | Where-Object TagName -EQ 'v1').TagObjectType | Should -Be 'commit'
        }
    }

    It 'coalesces multiple selected releases with the same peeled target into one checkpoint boundary' {
        InModuleScope CopyGitHubRepo {
            $selection = [pscustomobject] @{ Releases = @(
                    [pscustomobject] @{ ReleaseId = 21; TagName = 'v2-a'; TargetCommitSha = 'c2' },
                    [pscustomobject] @{ ReleaseId = 22; TagName = 'v2-b'; TargetCommitSha = 'c2' }
                ) }
            Mock Invoke-CgrGitHubApiReadRequest {
                $joined = $ArgumentList -join ' '
                if ($joined -match '/git/ref/tags/(v2-[ab])') { return [pscustomobject] @{ ExitCode = 0; Output = @('{"object":{"type":"commit","sha":"ref-c2"}}'); ErrorText = '' } }
                if ($joined -match '/commits/c2') { return [pscustomobject] @{ ExitCode = 0; Output = @('tree-c2'); ErrorText = '' } }
                if ($joined -match '/compare/c2\.\.\.head') { return [pscustomobject] @{ ExitCode = 0; Output = @('ahead'); ErrorText = '' } }
                throw "Unexpected read request: $joined"
            }
            $result = New-CgrSnapshotReleaseCheckpointPlan -Repository $script:repository -ReleaseSelection $selection -SourceState $script:sourceState
            $result.CheckpointCount | Should -Be 1
            @($result.Checkpoints[0].TagNames) | Should -Be @('v2-a', 'v2-b')
            @($result.Checkpoints[0].ReleaseIds) | Should -Be @(21, 22)
            Should -Invoke Invoke-CgrGitHubApiReadRequest -Times 1 -ParameterFilter { ($ArgumentList -join ' ') -match '/commits/c2' }
        }
    }

    It 'uses tree state rather than commit identity to decide whether a final HEAD checkpoint is needed' {
        InModuleScope CopyGitHubRepo {
            $sourceState = [pscustomobject] @{ DefaultBranch = 'main'; CommitSha = 'different-head-commit'; TreeSha = 'tree-c3' }
            $result = New-CgrSnapshotReleaseCheckpointPlan -Repository $script:repository -ReleaseSelection $script:releaseSelection -SourceState $sourceState
            $result.FinalHeadCheckpointRequired | Should -BeFalse
            $result.PlannedSnapshotCommitCount | Should -Be 3
            Should -Invoke Invoke-CgrGitHubApiReadRequest -Times 0 -ParameterFilter { ($ArgumentList -join ' ') -match '/compare/c3\.\.\.different-head-commit' }
        }
    }

    It 'fails closed with an actionable error when selected release targets diverge' {
        InModuleScope CopyGitHubRepo {
            $selection = [pscustomobject] @{ Releases = @(
                    [pscustomobject] @{ ReleaseId = 1; TagName = 'left'; TargetCommitSha = 'left-sha' },
                    [pscustomobject] @{ ReleaseId = 2; TagName = 'right'; TargetCommitSha = 'right-sha' }
                ) }
            Mock Invoke-CgrGitHubApiReadRequest {
                $joined = $ArgumentList -join ' '
                if ($joined -match '/git/ref/tags/(left|right)') { return [pscustomobject] @{ ExitCode = 0; Output = @('{"object":{"type":"commit","sha":"ref-sha"}}'); ErrorText = '' } }
                if ($joined -match '/commits/(left-sha|right-sha)') { return [pscustomobject] @{ ExitCode = 0; Output = @("tree-$($Matches[1])"); ErrorText = '' } }
                if ($joined -match '/compare/left-sha\.\.\.right-sha') { return [pscustomobject] @{ ExitCode = 0; Output = @('diverged'); ErrorText = '' } }
                throw "Unexpected read request: $joined"
            }
            { New-CgrSnapshotReleaseCheckpointPlan -Repository $script:repository -ReleaseSelection $selection -SourceState $script:sourceState } |
                Should -Throw -ErrorId 'SnapshotReleaseCheckpointTopologyIncompatible,New-CgrSnapshotReleaseCheckpointPlan'
        }
    }

    It 'fails closed when current HEAD differs in state but is not descended from the final selected release' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrGitHubApiReadRequest {
                $joined = $ArgumentList -join ' '
                if ($joined -match '/git/ref/tags/(v\d+)') { return [pscustomobject] @{ ExitCode = 0; Output = @('{"object":{"type":"commit","sha":"ref"}}'); ErrorText = '' } }
                if ($joined -match '/commits/(c\d+)') { return [pscustomobject] @{ ExitCode = 0; Output = @("tree-$($Matches[1])"); ErrorText = '' } }
                if ($joined -match '/compare/(c[123])\.\.\.(c[123])') {
                    $left = $Matches[1]; $right = $Matches[2]; $rank = @{ c1 = 1; c2 = 2; c3 = 3 }
                    return [pscustomobject] @{ ExitCode = 0; Output = @(if ($rank[$left] -lt $rank[$right]) { 'ahead' } else { 'behind' }); ErrorText = '' }
                }
                if ($joined -match '/compare/c3\.\.\.head') { return [pscustomobject] @{ ExitCode = 0; Output = @('diverged'); ErrorText = '' } }
                throw "Unexpected read request: $joined"
            }
            { New-CgrSnapshotReleaseCheckpointPlan -Repository $script:repository -ReleaseSelection $script:releaseSelection -SourceState $script:sourceState } |
                Should -Throw -ErrorId 'SnapshotReleaseCheckpointHeadTopologyIncompatible,New-CgrSnapshotReleaseCheckpointPlan'
        }
    }

    It 'plans the ordinary one-commit Snapshot state when release filters select nothing' {
        InModuleScope CopyGitHubRepo {
            $selection = [pscustomobject] @{ Releases = @() }
            $result = New-CgrSnapshotReleaseCheckpointPlan -Repository $script:repository -ReleaseSelection $selection -SourceState $script:sourceState
            $result.CheckpointCount | Should -Be 0
            $result.FinalHeadCheckpointRequired | Should -BeTrue
            $result.PlannedSnapshotCommitCount | Should -Be 1
            Should -Invoke Invoke-CgrGitHubApiReadRequest -Times 0
        }
    }
}

Describe 'Snapshot IncludeReleases planning integration' {
    It 'resolves the release inventory once and passes that exact reviewed selection to checkpoint planning' {
        InModuleScope CopyGitHubRepo {
            $sourceRepository = [pscustomobject] @{ FullName = 'acme/source'; Owner = 'acme'; DefaultBranch = 'main'; Visibility = 'private'; Id = $null }
            $sourceState = [pscustomobject] @{ ContentMode = 'Snapshot'; Repository = 'acme/source'; DefaultBranch = 'main'; CommitSha = 'head'; TreeSha = 'tree-head'; GitLfsPointerFiles = @(); GitLfsObjectsAvailable = $true; HistoricalRecords = $null }
            $selection = [pscustomobject] @{ SelectedReleaseCount = 1; SelectedAssetCount = 0; Releases = @([pscustomobject] @{ ReleaseId = 1; TagName = 'v1'; TargetCommitSha = 'c1' }) }
            $checkpointPlan = [pscustomobject] @{ CheckpointCount = 1; FinalHeadCheckpointRequired = $true }

            Mock Test-CgrGitHubRepositoryExistence { $false }
            Mock Get-CgrApprovedSourceState { $sourceState }
            Mock Get-CgrGitHubReleaseSelection { $selection }
            Mock New-CgrSnapshotReleaseCheckpointPlan { $checkpointPlan }

            $plan = New-CgrMigrationPlan -SourceRepository $sourceRepository -DestinationRepository acme/destination -ContentMode Snapshot -IncludeReleases -ReleaseTag 'v1.*' -DestinationVisibility private -CommitMessage 'Initial repository commit' -SkipSettings -PlanOnly

            $plan.ReleaseSelection.SelectedReleaseCount | Should -Be 1
            $plan.ReleaseCheckpointPlan.CheckpointCount | Should -Be 1
            Should -Invoke Get-CgrGitHubReleaseSelection -Times 1 -Exactly -ParameterFilter { $Repository -eq $sourceRepository -and $ReleaseTag -eq 'v1.*' }
            Should -Invoke New-CgrSnapshotReleaseCheckpointPlan -Times 1 -Exactly -ParameterFilter { $Repository -eq $sourceRepository -and $ReleaseSelection -eq $selection -and $SourceState -eq $sourceState }
        }
    }
}

Describe 'Snapshot release checkpoint plan rendering' {
    It 'shows release selection order separately from Git-ancestry checkpoint construction order' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'; DestinationRepository = 'acme/destination'; ArchiveRepository = $null; Mode = 'NewDestination'; ContentMode = 'Snapshot'; SourceVisibility = 'private'; DestinationVisibility = 'private'; IncludeReleases = $true; RestorePages = $false; EnableActionsAfterMigration = $false; SkipSettings = $true; PlanOnly = $true
                SourceState = [pscustomobject] @{ Repository = 'acme/source'; RepositoryId = 1; RepositoryNodeId = 'R1'; DefaultBranch = 'main'; CommitSha = 'head'; TreeSha = 'tree-head'; GitLfsPointerFiles = @(); GitLfsObjectsAvailable = $true; HistoricalRecords = $null }
                ReleaseSelection = [pscustomobject] @{ AvailableReleaseCount = 2; SelectedReleaseCount = 2; IncludePatterns = @(); ExcludePatterns = @(); IncludePrerelease = $false; IncludeDraftReleases = $false; ReleaseCount = $null }
                ReleaseCheckpointPlan = [pscustomobject] @{
                    CheckpointCount = 2; PlannedSnapshotCommitCount = 3; FinalHeadCheckpointRequired = $true; SourceHead = [pscustomobject] @{ CommitSha = 'head'; TreeSha = 'tree-head' }
                    ReleaseEvidence = @(
                        [pscustomobject] @{ SelectionOrder = 1; TagName = 'v2'; TagObjectType = 'commit'; TagObjectSha = 'ref-v2'; PeeledCommitSha = 'c2'; TreeSha = 'tree-c2' },
                        [pscustomobject] @{ SelectionOrder = 2; TagName = 'v1'; TagObjectType = 'tag'; TagObjectSha = 'ref-v1'; PeeledCommitSha = 'c1'; TreeSha = 'tree-c1' }
                    )
                    Checkpoints = @(
                        [pscustomobject] @{ Order = 1; SourceCommitSha = 'c1'; SourceTreeSha = 'tree-c1'; TagNames = @('v1') },
                        [pscustomobject] @{ Order = 2; SourceCommitSha = 'c2'; SourceTreeSha = 'tree-c2'; TagNames = @('v2') }
                    )
                }
                Steps = @()
            }
            $markdown = Format-CgrMigrationPlan -Plan $plan -Format Markdown
            $markdown | Should -Match 'Release filtering determines the approved release inventory; checkpoint order below is independently derived from peeled source commit ancestry'
            $markdown | Should -Match '\| 1 \| v2 \| commit \| ref-v2 \| c2 \| tree-c2 \|'
            $markdown | Should -Match '\| 1 \| c1 \| tree-c1 \| v1 \|'
        }
    }
}

Describe 'Snapshot IncludeReleases PlanOnly public boundary' {
    It 'allows PlanOnly planning, forwards release filters exactly once, and performs no execution mutation' {
        InModuleScope CopyGitHubRepo {
            Mock Assert-CgrSupportedHostName {}
            Mock Get-CgrPrerequisiteStatus { [pscustomobject] @{ Git = [pscustomobject] @{ Found = $true }; GitHubCli = [pscustomobject] @{ Found = $true }; Authentication = [pscustomobject] @{ Authenticated = $true; Message = 'ok' } } }
            Mock Get-CgrRepository { [pscustomobject] @{ FullName = 'acme/source'; DefaultBranch = 'main'; Visibility = 'private' } }
            Mock New-CgrMigrationPlan { [pscustomobject] @{ PSTypeName = 'CopyGitHubRepo.MigrationPlan'; ContentMode = 'Snapshot'; IncludeReleases = $true; PlanOnly = $true; WillMutateGitHub = $false; ReleaseSelection = [pscustomobject] @{ SelectedReleaseCount = 1 }; ReleaseCheckpointPlan = [pscustomobject] @{ CheckpointCount = 1 } } }
            Mock Invoke-CgrApprovedMigrationPlan { throw 'execution must not run for PlanOnly' }

            $plan = Copy-GitHubRepository -SourceRepository acme/source -DestinationRepository acme/destination -ContentMode Snapshot -IncludeReleases -ReleaseTag 'v1.*' -ReleaseCount 1 -PlanOnly
            $plan.ReleaseCheckpointPlan.CheckpointCount | Should -Be 1
            $plan.WillMutateGitHub | Should -BeFalse
            Should -Invoke New-CgrMigrationPlan -Times 1 -Exactly -ParameterFilter { $ContentMode -eq 'Snapshot' -and $IncludeReleases -and $PlanOnly -and $ReleaseTag -eq 'v1.*' -and $ReleaseCount -eq 1 }
            Should -Invoke Invoke-CgrApprovedMigrationPlan -Times 0
        }
    }

    It 'continues to reject Snapshot IncludeReleases mutation before planning or mutation' {
        InModuleScope CopyGitHubRepo {
            Mock Assert-CgrSupportedHostName {}
            Mock Get-CgrPrerequisiteStatus { throw 'must fail before prerequisites' }
            Mock New-CgrMigrationPlan { throw 'must fail before planning' }
            { Copy-GitHubRepository -SourceRepository acme/source -DestinationRepository acme/destination -ContentMode Snapshot -IncludeReleases } |
                Should -Throw -ErrorId 'SnapshotReleaseMigrationNotImplemented,Copy-GitHubRepository'
            Should -Invoke Get-CgrPrerequisiteStatus -Times 0
            Should -Invoke New-CgrMigrationPlan -Times 0
        }
    }
}
