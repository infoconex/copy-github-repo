BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force
}

InModuleScope CopyGitHubRepo {
    Describe 'Public same-name replacement execution' {
        BeforeEach {
            $script:prerequisites = [pscustomobject] @{
                Git = [pscustomobject] @{ Found = $true }
                GitHubCli = [pscustomobject] @{ Found = $true }
                Authentication = [pscustomobject] @{ Authenticated = $true; Message = 'Authenticated.' }
            }
            $script:sourceRepository = [pscustomobject] @{
                PSTypeName = 'CopyGitHubRepo.Repository'
                Id = 101L
                NodeId = 'R_source'
                Name = 'source'
                FullName = 'infoconex/source'
                Owner = 'infoconex'
                Visibility = 'private'
                IsPrivate = $true
                IsArchived = $false
                IsFork = $false
                DefaultBranch = 'main'
                Description = 'Source repository.'
                HtmlUrl = 'https://github.com/infoconex/source'
                CloneUrl = 'https://github.com/infoconex/source.git'
                SshUrl = 'git@github.com:infoconex/source.git'
                HostName = 'github.com'
                CanAdmin = $true
                CanPush = $true
            }
            Mock Get-CgrPrerequisiteStatus { $script:prerequisites }
            Mock Get-CgrRepository { $script:sourceRepository }
            Mock Test-CgrGitHubRepositoryExistence { $false }
            Mock Get-CgrRepositoryProtectionConfiguration {
                [pscustomobject] @{ Rulesets = @(); BranchProtection = $null; Unsupported = @() }
            }
            Mock Get-CgrApprovedSourceState {
                if ($ContentMode -eq 'FullHistory') {
                    [pscustomobject] @{
                        PSTypeName = 'CopyGitHubRepo.ApprovedSourceState'
                        ContentMode = 'FullHistory'
                        Repository = 'infoconex/source'
                        RepositoryId = 101L
                        RepositoryNodeId = 'R_source'
                        DefaultBranch = 'main'
                        Refs = @('refs/heads/main source-commit')
                        ReachableCommitCount = 1
                        BranchTrees = @('refs/heads/main source-tree')
                        GitLfsObjectsAvailable = $true
                    }
                }
                else {
                    [pscustomobject] @{
                        PSTypeName = 'CopyGitHubRepo.ApprovedSourceState'
                        ContentMode = 'Snapshot'
                        Repository = 'infoconex/source'
                        RepositoryId = 101L
                        RepositoryNodeId = 'R_source'
                        DefaultBranch = 'main'
                        CommitSha = 'source-commit'
                        TreeSha = 'source-tree'
                        GitLfsObjectsAvailable = $false
                        GitLfsPointerFiles = @()
                    }
                }
            }
            Mock Assert-CgrApprovedSourceState { $SourceState }
        }

        It 'does not mutate when WhatIf is used and does not require exact confirmation' {
            Mock Invoke-CgrApprovedMigrationPlan { throw 'Approved execution must not run under WhatIf.' }
            Mock Assert-CgrSameNameReplacementConfirmation { throw 'Exact confirmation must not be required under WhatIf.' }

            $plan = Copy-GitHubRepository `
                -SourceRepository infoconex/source `
                -DestinationRepository infoconex/source `
                -ArchiveRepositoryName source-archive `
                -WhatIf

            $plan.Mode | Should -Be 'SameNameReplacement'
            $plan.SourceState.CommitSha | Should -Be 'source-commit'
            Should -Invoke Invoke-CgrApprovedMigrationPlan -Times 0 -Exactly
            Should -Invoke Assert-CgrSameNameReplacementConfirmation -Times 0 -Exactly
        }

        It 'requires exact confirmation for non-interactive same-name mutation even with Force' {
            Mock Invoke-CgrSameNameSnapshotReplacement { throw 'Same-name replacement must not execute without exact confirmation.' }

            {
                Copy-GitHubRepository `
                    -SourceRepository infoconex/source `
                    -DestinationRepository infoconex/source `
                    -ArchiveRepositoryName source-archive `
                    -NonInteractive `
                    -Force
            } | Should -Throw -ErrorId 'SameNameReplacementConfirmationRequired,Assert-CgrSameNameReplacementConfirmation'

            Should -Invoke Invoke-CgrSameNameSnapshotReplacement -Times 0 -Exactly
        }

        It 'does not allow Confirm false to bypass exact same-name replacement confirmation' {
            Mock Invoke-CgrSameNameSnapshotReplacement { throw 'Same-name replacement must not execute without exact confirmation.' }

            {
                Copy-GitHubRepository `
                    -SourceRepository infoconex/source `
                    -DestinationRepository infoconex/source `
                    -ArchiveRepositoryName source-archive `
                    -Confirm:$false
            } | Should -Throw -ErrorId 'SameNameReplacementConfirmationRequired,Assert-CgrSameNameReplacementConfirmation'

            Should -Invoke Invoke-CgrSameNameSnapshotReplacement -Times 0 -Exactly
        }

        It 'dispatches a confirmed non-interactive Snapshot replacement into the approved Snapshot engine' {
            Mock Invoke-CgrSameNameSnapshotReplacement {
                [pscustomobject] @{
                    PSTypeName = 'CopyGitHubRepo.MigrationExecutionResult'
                    Status = 'SameNameSnapshotVerifiedSettingsSkipped'
                    SourceRepository = 'infoconex/source'
                    ArchiveRepository = 'infoconex/source-archive'
                    DestinationRepository = 'infoconex/source'
                    IsVerified = $true
                }
            } -ParameterFilter {
                $Plan.Mode -eq 'SameNameReplacement' -and
                $Plan.ContentMode -eq 'Snapshot' -and
                $Plan.ArchiveRepository -eq 'infoconex/source-archive' -and
                $Plan.SourceState.CommitSha -eq 'source-commit' -and
                $SourceRepository.FullName -eq 'infoconex/source'
            }

            $result = Copy-GitHubRepository `
                -SourceRepository infoconex/source `
                -DestinationRepository infoconex/source `
                -ArchiveRepositoryName source-archive `
                -SameNameConfirmation 'SOURCE=infoconex/source;ARCHIVE=infoconex/source-archive;REPLACEMENT=infoconex/source' `
                -SkipSettings `
                -NonInteractive `
                -Force

            $result.Status | Should -Be 'SameNameSnapshotVerifiedSettingsSkipped'
            Should -Invoke Assert-CgrApprovedSourceState -Times 1 -Exactly
            Should -Invoke Invoke-CgrSameNameSnapshotReplacement -Times 1 -Exactly
        }

        It 'dispatches a confirmed non-interactive FullHistory replacement into the approved FullHistory engine' {
            Mock Invoke-CgrSameNameSnapshotReplacement { throw 'Snapshot engine must not run for FullHistory.' }
            Mock Invoke-CgrSameNameFullHistoryReplacement {
                [pscustomobject] @{
                    PSTypeName = 'CopyGitHubRepo.MigrationExecutionResult'
                    Status = 'SameNameFullHistoryVerifiedSettingsSkipped'
                    SourceRepository = 'infoconex/source'
                    ArchiveRepository = 'infoconex/source-archive'
                    DestinationRepository = 'infoconex/source'
                    IsVerified = $true
                }
            } -ParameterFilter {
                $Plan.Mode -eq 'SameNameReplacement' -and
                $Plan.ContentMode -eq 'FullHistory' -and
                $Plan.ArchiveRepository -eq 'infoconex/source-archive' -and
                @($Plan.SourceState.Refs).Count -eq 1 -and
                $SourceRepository.FullName -eq 'infoconex/source'
            }

            $result = Copy-GitHubRepository `
                -SourceRepository infoconex/source `
                -DestinationRepository infoconex/source `
                -ArchiveRepositoryName source-archive `
                -ContentMode FullHistory `
                -SameNameConfirmation 'SOURCE=infoconex/source;ARCHIVE=infoconex/source-archive;REPLACEMENT=infoconex/source' `
                -SkipSettings `
                -NonInteractive `
                -Force

            $result.Status | Should -Be 'SameNameFullHistoryVerifiedSettingsSkipped'
            Should -Invoke Invoke-CgrSameNameFullHistoryReplacement -Times 1 -Exactly
            Should -Invoke Invoke-CgrSameNameSnapshotReplacement -Times 0 -Exactly
        }
    }
}
