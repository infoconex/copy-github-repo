BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Snapshot publication provenance' {
    It 'records source and destination evidence for a new-destination Snapshot' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                SourceVisibility = 'public'
                DestinationVisibility = 'public'
                SourceDefaultBranch = 'main'
                CommitMessage = 'Initial repository commit'
                SkipSettings = $false
            }
            $source = [pscustomobject] @{ FullName = 'infoconex/source'; Id = 101L; NodeId = 'R_source' }
            $destination = [pscustomobject] @{ FullName = 'infoconex/destination'; Id = 202L; NodeId = 'R_destination'; HtmlUrl = 'https://github.com/infoconex/destination' }

            Mock Copy-CgrRepositorySnapshot {
                [pscustomobject] @{ SourceCommitSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; BranchName = 'main'; CommitSha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'; TreeSha = 'cccccccccccccccccccccccccccccccccccccccc'; Verified = $true }
            }
            Mock Get-CgrRepository { $destination }
            Mock Invoke-CgrRepositorySnapshotVerification { [pscustomobject] @{ IsSuccessful = $true; Checks = @() } }
            Mock Set-CgrGitHubRepositorySetting { [pscustomobject] @{ Restored = @(); Skipped = @(); Unsupported = @(); IsSuccessful = $true } }
            Mock Set-CgrRepositoryProtectionConfiguration { [pscustomobject] @{ Restored = @(); Skipped = @(); IsSuccessful = $true; IsComplete = $true } }

            $result = Invoke-CgrNewDestinationSnapshot -Plan $plan -SourceRepository $source -DestinationRepository $destination

            $result.Provenance.ContentMode | Should -Be 'Snapshot'
            $result.Provenance.SourceRepositoryId | Should -Be 101
            $result.Provenance.SourceRepositoryNodeId | Should -Be 'R_source'
            $result.Provenance.SourceCommitSha | Should -Be 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
            $result.Provenance.SourceTreeSha | Should -Be 'cccccccccccccccccccccccccccccccccccccccc'
            $result.Provenance.DestinationRepositoryId | Should -Be 202
            $result.Provenance.DestinationRepositoryNodeId | Should -Be 'R_destination'
            $result.Provenance.DestinationRootCommitSha | Should -Be 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
            $result.Provenance.DestinationTreeSha | Should -Be 'cccccccccccccccccccccccccccccccccccccccc'
            $result.Provenance.VerificationSuccessful | Should -BeTrue
            [DateTimeOffset]::Parse($result.Provenance.RecordedAtUtc).Offset | Should -Be ([TimeSpan]::Zero)
            $result.ProtectionRestored | Should -BeTrue
        }
    }

    It 'renders provenance in Markdown and JSON reports' {
        InModuleScope CopyGitHubRepo {
            $result = [pscustomobject] @{
                Status = 'CompletedWithSupportedSettings'; SourceRepository = 'infoconex/source'; DestinationRepository = 'infoconex/destination'
                SourceVisibility = 'public'; DestinationVisibility = 'public'; DestinationHtmlUrl = 'https://github.com/infoconex/destination'
                DestinationBranch = 'main'; SnapshotCommitSha = 'dest-commit'; IsVerified = $true; SettingsRestored = $true; ProtectionRestored = $true
                CompletedSteps = @(); Verification = $null; Settings = $null; Protection = $null
                Provenance = [pscustomobject] @{
                    RecordedAtUtc = '2026-08-15T04:00:00.0000000+00:00'; ContentMode = 'Snapshot'; SourceRepository = 'infoconex/source'
                    SourceRepositoryId = 101; SourceRepositoryNodeId = 'R_source'; SourceDefaultBranch = 'main'; SourceCommitSha = 'source-commit'; SourceTreeSha = 'tree-sha'
                    ArchiveRepository = $null; DestinationRepository = 'infoconex/destination'; DestinationRepositoryId = 202; DestinationRepositoryNodeId = 'R_destination'
                    DestinationRootCommitSha = 'dest-commit'; DestinationTreeSha = 'tree-sha'; VerificationSuccessful = $true
                }
            }

            $markdown = Format-CgrMigrationExecutionResult -Result $result -Format Markdown
            $markdown | Should -Match '## Publication Provenance'
            $markdown | Should -Match 'source-commit'
            $markdown | Should -Match 'dest-commit'

            $json = Format-CgrMigrationExecutionResult -Result $result -Format Json | ConvertFrom-Json
            $json.Provenance.SourceCommitSha | Should -Be 'source-commit'
            $json.Provenance.DestinationRootCommitSha | Should -Be 'dest-commit'
        }
    }

    It 'keeps Snapshot provenance outside the Git tree' {
        InModuleScope CopyGitHubRepo {
            $source = Get-Command Copy-CgrRepositorySnapshot
            $source.Definition | Should -Not -Match 'provenance\.json'
            $source.Definition | Should -Not -Match 'git notes'
            $source.Definition | Should -Not -Match 'git tag'
        }
    }
}
