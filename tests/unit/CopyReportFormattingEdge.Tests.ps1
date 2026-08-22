BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force
}

InModuleScope CopyGitHubRepo {
    Describe 'Repository copy report formatting edge cases' {
        It 'renders an archive plan that predates approved source-state evidence without inventing evidence' {
            $plan = [pscustomobject] @{
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/source'
                ArchiveRepository = 'infoconex/source-archive'
                Mode = 'SameNameReplacement'
                ContentMode = 'Snapshot'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                RestorePages = $false
                EnableActionsAfterMigration = $false
                SkipSettings = $true
                PlanOnly = $true
                Steps = @()
            }

            $markdown = Format-CgrMigrationPlan -Plan $plan -Format Markdown

            $markdown | Should -Match '\| Archive \| infoconex/source-archive \|'
            $markdown | Should -Not -Match '## Approved Source State'
        }

        It 'uses direct original-repository evidence and supports a minimal execution result' {
            $result = [pscustomobject] @{
                Status = 'ReplacementCompleted'
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/source'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                DestinationHtmlUrl = 'https://github.com/infoconex/source'
                DestinationBranch = 'main'
                SnapshotCommitSha = 'root'
                IsVerified = $true
                SettingsRestored = $false
                OriginalRepository = 'infoconex/source'
                OriginalRepositoryId = 101L
                OriginalRepositoryNodeId = 'R_original'
                ArchiveRepository = 'infoconex/source-archive'
                ArchiveRepositoryId = 101L
                ArchiveRepositoryNodeId = 'R_original'
                ArchivedOriginalIdentityPreserved = $true
                ReplacementDestinationRepository = 'infoconex/source'
                ReplacementDestinationRepositoryId = 102L
                ReplacementDestinationRepositoryNodeId = 'R_replacement'
                ReplacementHasDistinctIdentity = $true
                CompletedSteps = @()
                Verification = $null
                Settings = $null
                Protection = $null
            }

            $markdown = Format-CgrMigrationExecutionResult -Result $result -Format Markdown

            $markdown | Should -Match '\| Original repository \| infoconex/source \|'
            $markdown | Should -Match '\| Original repository ID \| 101 \|'
            $markdown | Should -Not -Match '## Approved Source State'
            $markdown | Should -Not -Match '## Publication Provenance'
        }
    }
}
