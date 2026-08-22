BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $root 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Repository copy repeated invocation safety' {
    It 'does not silently reuse a destination created by an earlier new-destination attempt' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{
                FullName = 'infoconex/source'
                Owner = 'infoconex'
                Visibility = 'private'
                DefaultBranch = 'main'
            }
            $script:retryDestinationExists = $false

            Mock Test-CgrGitHubRepositoryExistence { $script:retryDestinationExists }
            Mock Get-CgrApprovedSourceState {
                [pscustomobject] @{
                    ContentMode = 'Snapshot'
                    Repository = 'infoconex/source'
                    DefaultBranch = 'main'
                    CommitSha = 'source-commit'
                    TreeSha = 'source-tree'
                }
            }

            $firstPlan = New-CgrMigrationPlan `
                -SourceRepository $source `
                -DestinationRepository 'infoconex/destination' `
                -ContentMode Snapshot `
                -DestinationVisibility private `
                -CommitMessage 'Initial repository commit' `
                -PlanOnly

            $firstPlan.Mode | Should -Be 'NewDestination'
            $script:retryDestinationExists = $true

            {
                New-CgrMigrationPlan `
                    -SourceRepository $source `
                    -DestinationRepository 'infoconex/destination' `
                    -ContentMode Snapshot `
                    -DestinationVisibility private `
                    -CommitMessage 'Initial repository commit' `
                    -PlanOnly
            } | Should -Throw -ErrorId 'DestinationRepositoryAlreadyExists,New-CgrMigrationPlan'

            Should -Invoke Get-CgrApprovedSourceState -Times 1 -Exactly
        }
    }

    It 'does not silently reuse an archive from an earlier existing-destination replacement attempt' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{
                FullName = 'infoconex/source'
                Owner = 'infoconex'
                Visibility = 'private'
                DefaultBranch = 'main'
            }
            $script:retryExistingArchiveExists = $false

            Mock Test-CgrGitHubRepositoryExistence {
                param($Repository)
                if ($Repository -eq 'infoconex/destination') { return $true }
                if ($Repository -eq 'infoconex/destination-archive') { return $script:retryExistingArchiveExists }
                return $false
            }
            Mock Get-CgrApprovedSourceState {
                [pscustomobject] @{
                    ContentMode = 'Snapshot'
                    Repository = 'infoconex/source'
                    DefaultBranch = 'main'
                    CommitSha = 'source-commit'
                    TreeSha = 'source-tree'
                }
            }

            $firstPlan = New-CgrMigrationPlan `
                -SourceRepository $source `
                -DestinationRepository 'infoconex/destination' `
                -ContentMode Snapshot `
                -DestinationVisibility private `
                -ExistingDestinationArchiveName 'destination-archive' `
                -CommitMessage 'Initial repository commit' `
                -PlanOnly

            $firstPlan.Mode | Should -Be 'ExistingDestinationReplacement'
            $script:retryExistingArchiveExists = $true

            {
                New-CgrMigrationPlan `
                    -SourceRepository $source `
                    -DestinationRepository 'infoconex/destination' `
                    -ContentMode Snapshot `
                    -DestinationVisibility private `
                    -ExistingDestinationArchiveName 'destination-archive' `
                    -CommitMessage 'Initial repository commit' `
                    -PlanOnly
            } | Should -Throw -ErrorId 'ExistingDestinationArchiveAlreadyExists,New-CgrMigrationPlan'

            Should -Invoke Get-CgrApprovedSourceState -Times 1 -Exactly
        }
    }

    It 'does not silently reuse the preserved source archive from an earlier same-name attempt' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{
                FullName = 'infoconex/source'
                Owner = 'infoconex'
                Visibility = 'private'
                DefaultBranch = 'main'
            }
            $script:retrySourceArchiveExists = $false

            Mock Test-CgrGitHubRepositoryExistence { $script:retrySourceArchiveExists }
            Mock Get-CgrApprovedSourceState {
                [pscustomobject] @{
                    ContentMode = 'Snapshot'
                    Repository = 'infoconex/source'
                    DefaultBranch = 'main'
                    CommitSha = 'source-commit'
                    TreeSha = 'source-tree'
                }
            }

            $firstPlan = New-CgrMigrationPlan `
                -SourceRepository $source `
                -DestinationRepository 'infoconex/source' `
                -ContentMode Snapshot `
                -DestinationVisibility private `
                -ArchiveRepositoryName 'source-archive' `
                -CommitMessage 'Initial repository commit' `
                -PlanOnly

            $firstPlan.Mode | Should -Be 'SameNameReplacement'
            $script:retrySourceArchiveExists = $true

            {
                New-CgrMigrationPlan `
                    -SourceRepository $source `
                    -DestinationRepository 'infoconex/source' `
                    -ContentMode Snapshot `
                    -DestinationVisibility private `
                    -ArchiveRepositoryName 'source-archive' `
                    -CommitMessage 'Initial repository commit' `
                    -PlanOnly
            } | Should -Throw -ErrorId 'ArchiveRepositoryAlreadyExists,New-CgrMigrationPlan'

            Should -Invoke Get-CgrApprovedSourceState -Times 1 -Exactly
        }
    }
}
