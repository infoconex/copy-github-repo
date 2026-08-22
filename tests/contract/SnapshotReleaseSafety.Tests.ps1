BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $root 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Snapshot tag and GitHub Release safety' {
    It 'captures bounded tag and release evidence without changing FullHistory semantics' {
        InModuleScope CopyGitHubRepo {
            $repository = [pscustomobject] @{ FullName = 'infoconex/source' }

            Mock Get-CgrGitHubApi {
                if ($Path -like '*/tags?*') {
                    return @(
                        [pscustomobject] @{ name = 'v0.1.0' },
                        [pscustomobject] @{ name = 'demo' }
                    )
                }

                return @(
                    [pscustomobject] @{ tag_name = 'v0.1.0'; name = 'Version 0.1.0'; draft = $false; prerelease = $false }
                )
            }

            $records = Get-CgrSnapshotHistory -Repository $repository
            $records.TagCount | Should -Be 2
            $records.TagNames | Should -Contain 'v0.1.0'
            $records.VersionLikeTagNames | Should -Contain 'v0.1.0'
            $records.ReleaseCount | Should -Be 1
            $records.Releases[0].TagName | Should -Be 'v0.1.0'
            $records.TagsAreCopied | Should -BeFalse
            $records.ReleasesAreCopied | Should -BeFalse
        }
    }

    It 'stores historical records in the approved Snapshot source state' {
        InModuleScope CopyGitHubRepo {
            $repository = [pscustomobject] @{
                FullName = 'infoconex/source'
                Id = 10L
                NodeId = 'R_source'
            }

            Mock Get-CgrRepositoryDefaultBranchTree {
                [pscustomobject] @{
                    BranchName = 'main'
                    CommitSha = 'commit-sha'
                    TreeSha = 'tree-sha'
                    GitLfsObjectsAvailable = $true
                    GitLfsPointerFiles = @()
                }
            }
            Mock Get-CgrSnapshotHistory {
                [pscustomobject] @{
                    TagCount = 1
                    TagNames = @('v0.1.0')
                    VersionLikeTagNames = @('v0.1.0')
                    ReleaseCount = 1
                    Releases = @()
                    TagsAreCopied = $false
                    ReleasesAreCopied = $false
                }
            }

            $state = Get-CgrApprovedSourceState -Repository $repository -ContentMode Snapshot
            $state.HistoricalRecords.TagCount | Should -Be 1
            $state.HistoricalRecords.ReleaseCount | Should -Be 1
            $state.HistoricalRecords.TagsAreCopied | Should -BeFalse
        }
    }

    It 'renders same-name Snapshot archive and release-order guidance' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/source'
                ArchiveRepository = 'infoconex/source-archive'
                Mode = 'SameNameReplacement'
                ContentMode = 'Snapshot'
                SourceVisibility = 'public'
                DestinationVisibility = 'public'
                RestorePages = $false
                EnableActionsAfterMigration = $false
                SkipSettings = $false
                PlanOnly = $true
                SourceState = [pscustomobject] @{
                    Repository = 'infoconex/source'
                    RepositoryId = 10L
                    RepositoryNodeId = 'R_source'
                    DefaultBranch = 'main'
                    CommitSha = 'commit-sha'
                    TreeSha = 'tree-sha'
                    GitLfsPointerFiles = @()
                    GitLfsObjectsAvailable = $true
                    HistoricalRecords = [pscustomobject] @{
                        TagCount = 1
                        TagCountMayBeTruncated = $false
                        TagNames = @('v0.1.0')
                        VersionLikeTagNames = @('v0.1.0')
                        ReleaseCount = 1
                        ReleaseCountMayBeTruncated = $false
                        Releases = @()
                    }
                }
                Steps = @()
            }

            $markdown = Format-CgrMigrationPlan -Plan $plan -Format Markdown
            $markdown | Should -Match 'Git tags \| 1 \| Not copied; retained by the archived original repository'
            $markdown | Should -Match 'GitHub Releases \| 1 \| Not copied; retained by the archived original repository'
            $markdown | Should -Match 'create the new release tag and GitHub Release on the clean replacement only after Snapshot publication and verification'
        }
    }

    It 'keeps the interactive plan review warning in the wizard contract' {
        $root = Split-Path -Parent $PSScriptRoot
        $wizardPath = Join-Path $root 'src/CopyGitHubRepo/Private/Wizard/Invoke-CgrRepositoryCopyWizard.ps1'
        $wizard = Get-Content -LiteralPath $wizardPath -Raw
        $wizard | Should -Match 'Existing tags and GitHub Releases remain with the archived original repository'
        $wizard | Should -Match 'Create the new release tag and GitHub Release only after the clean replacement has completed and been verified'
    }
}
