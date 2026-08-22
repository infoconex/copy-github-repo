BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force
}

InModuleScope CopyGitHubRepo {
    Describe 'Repository copy report formatting' {
        BeforeEach {
            $script:snapshotState = [pscustomobject] @{
                ContentMode = 'Snapshot'
                Repository = 'infoconex/source'
                RepositoryId = 101L
                RepositoryNodeId = 'R_source'
                DefaultBranch = 'main'
                CapturedAtUtc = '2026-08-15T15:00:00Z'
                CommitSha = 'source-commit'
                TreeSha = 'source-tree'
                GitLfsPointerFiles = @('large.bin')
                GitLfsObjectsAvailable = $true
            }
            $script:fullHistoryState = [pscustomobject] @{
                ContentMode = 'FullHistory'
                Repository = 'infoconex/source'
                RepositoryId = 101L
                RepositoryNodeId = 'R_source'
                DefaultBranch = 'main'
                CapturedAtUtc = '2026-08-15T15:00:00Z'
                Refs = @('refs/heads/main source-commit', 'refs/tags/v1 tag-commit')
                ReachableCommitCount = 14
                BranchTrees = @('refs/heads/main source-tree')
                GitLfsObjectsAvailable = $true
            }
        }

        It 'renders Snapshot approved state in the human-readable plan without raw object output' {
            $plan = [pscustomobject] @{
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                ArchiveRepository = $null
                Mode = 'NewDestination'
                ContentMode = 'Snapshot'
                SourceVisibility = 'public'
                DestinationVisibility = 'public'
                RestorePages = $false
                EnableActionsAfterMigration = $false
                SkipSettings = $false
                PlanOnly = $true
                SourceState = $script:snapshotState
                Steps = @([pscustomobject] @{ Order = 1; Name = 'CopySnapshot'; MutatesGitHub = $true; Description = 'Publish the approved Snapshot state.' })
            }

            $markdown = Format-CgrMigrationPlan -Plan $plan -Format Markdown

            $markdown | Should -Match '^# GitHub Repository Copy Plan'
            $markdown | Should -Match '## Approved Source State'
            $markdown | Should -Match '\| Approved commit SHA \| source-commit \|'
            $markdown | Should -Match '\| Approved tree SHA \| source-tree \|'
            $markdown | Should -Match '\| Git LFS pointer files \| 1 \|'
            $markdown | Should -Not -Match '@\{'
        }

        It 'renders FullHistory approved state in the human-readable plan' {
            $plan = [pscustomobject] @{
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                ArchiveRepository = $null
                Mode = 'NewDestination'
                ContentMode = 'FullHistory'
                SourceVisibility = 'public'
                DestinationVisibility = 'public'
                RestorePages = $false
                EnableActionsAfterMigration = $false
                SkipSettings = $false
                PlanOnly = $true
                SourceState = $script:fullHistoryState
                Steps = @([pscustomobject] @{ Order = 1; Name = 'CopyFullHistory'; MutatesGitHub = $true; Description = 'Copy the approved history.' })
            }

            $markdown = Format-CgrMigrationPlan -Plan $plan -Format Markdown

            $markdown | Should -Match '\| Approved branch/tag refs \| 2 \|'
            $markdown | Should -Match '\| Reachable commit count \| 14 \|'
            $markdown | Should -Match '\| Branch-tip trees \| 1 \|'
            $markdown | Should -Match 'Reachable Git LFS objects available'
        }

        It 'renders Snapshot planned state in the repository copy execution report' {
            $result = [pscustomobject] @{
                Status = 'CompletedWithSupportedSettings'
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                SourceVisibility = 'public'
                DestinationVisibility = 'public'
                DestinationHtmlUrl = 'https://github.com/infoconex/destination'
                DestinationBranch = 'main'
                SnapshotCommitSha = 'destination-root'
                IsVerified = $true
                SettingsRestored = $true
                ProtectionRestored = $true
                PlannedSourceState = $script:snapshotState
                CompletedSteps = @()
                Verification = $null
                Settings = $null
                Protection = $null
            }

            $markdown = Format-CgrMigrationExecutionResult -Result $result -Format Markdown

            $markdown | Should -Match '^# GitHub Repository Copy Report'
            $markdown | Should -Match '## Approved Source State'
            $markdown | Should -Match '\| Approved commit SHA \| source-commit \|'
            $markdown | Should -Match '\| Approved tree SHA \| source-tree \|'
            $markdown | Should -Not -Match '# GitHub Repository Migration Report'
        }

        It 'renders FullHistory planned state from the reviewed plan fallback in the execution report' {
            $result = [pscustomobject] @{
                Status = 'FullHistoryVerifiedSettingsSkipped'
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                SourceVisibility = 'public'
                DestinationVisibility = 'public'
                DestinationHtmlUrl = 'https://github.com/infoconex/destination'
                DestinationBranch = 'main'
                SnapshotCommitSha = $null
                IsVerified = $true
                SettingsRestored = $false
                Plan = [pscustomobject] @{ SourceState = $script:fullHistoryState }
                CompletedSteps = @()
                Verification = $null
                Settings = $null
                Protection = $null
            }

            $markdown = Format-CgrMigrationExecutionResult -Result $result -Format Markdown

            $markdown | Should -Match '\| Content mode \| FullHistory \|'
            $markdown | Should -Match '\| Approved branch/tag refs \| 2 \|'
            $markdown | Should -Match '\| Reachable commit count \| 14 \|'
            $markdown | Should -Match '\| Branch-tip trees \| 1 \|'
        }

        It 'renders replacement identity, provenance, verification, settings, and protection evidence' {
            $result = [pscustomobject] @{
                Status = 'CompletedWithSupportedSettings'
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                SourceVisibility = 'public'
                DestinationVisibility = 'public'
                DestinationHtmlUrl = 'https://github.com/infoconex/destination'
                DestinationBranch = 'main'
                SnapshotCommitSha = 'destination-root'
                IsVerified = $true
                SettingsRestored = $true
                ProtectionRestored = $true
                PlannedSourceState = $script:snapshotState
                OriginalDestinationRepository = 'infoconex/destination'
                OriginalDestinationRepositoryId = 201L
                OriginalDestinationRepositoryNodeId = 'R_original'
                ArchiveRepository = 'infoconex/destination-archive'
                ArchiveRepositoryId = 201L
                ArchiveRepositoryNodeId = 'R_original'
                ArchivedOriginalIdentityPreserved = $true
                ReplacementDestinationRepository = 'infoconex/destination'
                ReplacementDestinationRepositoryId = 202L
                ReplacementDestinationRepositoryNodeId = 'R_replacement'
                ReplacementHasDistinctIdentity = $true
                Provenance = [pscustomobject] @{
                    RecordedAtUtc = '2026-08-15T15:05:00Z'
                    ContentMode = 'Snapshot'
                    SourceRepository = 'infoconex/source'
                    SourceRepositoryId = 101L
                    SourceRepositoryNodeId = 'R_source'
                    SourceDefaultBranch = 'main'
                    SourceCommitSha = 'source-commit'
                    SourceTreeSha = 'source-tree'
                    ArchiveRepository = 'infoconex/destination-archive'
                    ArchiveRepositoryId = 201L
                    ArchiveRepositoryNodeId = 'R_original'
                    DestinationRepository = 'infoconex/destination'
                    DestinationRepositoryId = 202L
                    DestinationRepositoryNodeId = 'R_replacement'
                    DestinationRootCommitSha = 'destination-root'
                    DestinationTreeSha = 'source-tree'
                    VerificationSuccessful = $true
                }
                CompletedSteps = @([pscustomobject] @{ Order = 1; Name = 'CopySnapshot'; MutatedGitHub = $true; Verified = $true })
                Verification = [pscustomobject] @{
                    Checks = @([pscustomobject] @{ Name = 'TreeMatches'; Passed = $true; Expected = 'source|tree'; Actual = 'source|tree' })
                }
                Settings = [pscustomobject] @{
                    Restored = @([pscustomobject] @{ Name = 'Description'; Status = 'Restored'; Value = 'Copy | description' })
                    Skipped = @('Homepage')
                    Unsupported = @('CustomProperty')
                }
                Protection = [pscustomobject] @{
                    Restored = @([pscustomobject] @{ Kind = 'Ruleset'; Name = 'Protect main' })
                    Skipped = @(
                        'Inherited organization ruleset',
                        [pscustomobject] @{ Kind = 'BranchProtection'; Name = 'main'; Reason = 'Contains identity-bound restrictions.' }
                    )
                }
            }

            $markdown = Format-CgrMigrationExecutionResult -Result $result -Format Markdown

            $markdown | Should -Match '## Replacement Identity Evidence'
            $markdown | Should -Match '\| Replacement repository ID \| 202 \|'
            $markdown | Should -Match '## Publication Provenance'
            $markdown | Should -Match '\| Destination root commit SHA \| destination-root \|'
            $markdown | Should -Match '## Completed Steps'
            $markdown | Should -Match '## Verification Checks'
            $markdown | Should -Match 'source\\\|tree'
            $markdown | Should -Match '## Settings'
            $markdown | Should -Match 'Copy \\\| description'
            $markdown | Should -Match '## Repository Protection'
            $markdown | Should -Match 'Inherited organization ruleset'
            $markdown | Should -Match 'Contains identity-bound restrictions'
        }

        It 'serializes plan and execution objects to JSON without changing their structured evidence' {
            $plan = [pscustomobject] @{
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                ContentMode = 'Snapshot'
                SourceState = $script:snapshotState
            }
            $result = [pscustomobject] @{
                Status = 'Completed'
                PlannedSourceState = $script:snapshotState
            }

            $planJson = Format-CgrMigrationPlan -Plan $plan -Format Json | ConvertFrom-Json
            $resultJson = Format-CgrMigrationExecutionResult -Result $result -Format Json | ConvertFrom-Json

            $planJson.SourceState.CommitSha | Should -Be 'source-commit'
            $resultJson.PlannedSourceState.TreeSha | Should -Be 'source-tree'
        }
    }
}
