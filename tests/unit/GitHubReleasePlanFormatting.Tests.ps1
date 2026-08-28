BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'GitHub Release plan formatting' {
    It 'renders approved FullHistory release selection and commit evidence' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'
                DestinationRepository = 'acme/destination'
                ArchiveRepository = $null
                Mode = 'NewDestination'
                ContentMode = 'FullHistory'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                IncludeReleases = $true
                RestorePages = $false
                EnableActionsAfterMigration = $false
                SkipSettings = $false
                PlanOnly = $true
                SourceState = [pscustomobject] @{
                    Repository = 'acme/source'
                    RepositoryId = 1
                    RepositoryNodeId = 'R_1'
                    DefaultBranch = 'main'
                    CapturedAtUtc = '2026-08-28T00:00:00Z'
                    Refs = @('refs/heads/main abc123', 'refs/tags/v2.0.0 abc123')
                    ReachableCommitCount = 10
                    BranchTrees = @('refs/heads/main def456')
                    GitLfsObjectsAvailable = $true
                }
                ReleaseSelection = [pscustomobject] @{
                    AvailableReleaseCount = 4
                    SelectedReleaseCount = 1
                    SelectedAssetCount = 2
                    IncludePatterns = @('v2.*')
                    ExcludePatterns = @()
                    IncludePrerelease = $false
                    IncludeDraftReleases = $false
                    ReleaseCount = 1
                    Releases = @([pscustomobject] @{
                            TagName = 'v2.0.0'
                            TargetCommitSha = 'abc123'
                            Draft = $false
                            Prerelease = $false
                            Assets = @([pscustomobject] @{ Name = 'one.zip' }, [pscustomobject] @{ Name = 'one.sha256' })
                        })
                }
                Steps = @([pscustomobject] @{ Order = 1; Name = 'RestoreGitHubReleases'; MutatesGitHub = $true; Description = 'Restore one release.' })
            }

            $markdown = Format-CgrMigrationPlan -Plan $plan -Format Markdown

            $markdown | Should -Match '## Approved GitHub Releases'
            $markdown | Should -Match 'Available source releases \| 4'
            $markdown | Should -Match 'Selected releases \| 1'
            $markdown | Should -Match 'Selected assets \| 2'
            $markdown | Should -Match 'v2\.\*'
            $markdown | Should -Match 'v2\.0\.0'
            $markdown | Should -Match 'abc123'
        }
    }
}
