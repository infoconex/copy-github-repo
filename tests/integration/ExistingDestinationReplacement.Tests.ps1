BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $root 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Existing destination archive and replace planning' {
    It 'plans archive before replacement creation when an existing destination is explicitly preserved' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{
                FullName = 'infoconex/source'
                Owner = 'infoconex'
                Visibility = 'public'
                DefaultBranch = 'main'
            }
            Mock Test-CgrGitHubRepositoryExistence { param($Repository) $Repository -eq 'infoconex/destination' }
            Mock Get-CgrApprovedSourceState {
                [pscustomobject] @{ ContentMode = 'Snapshot'; Repository = 'infoconex/source'; DefaultBranch = 'main'; CommitSha = 'source-commit'; TreeSha = 'source-tree' }
            }

            $plan = New-CgrMigrationPlan `
                -SourceRepository $source `
                -DestinationRepository 'infoconex/destination' `
                -ContentMode Snapshot `
                -DestinationVisibility public `
                -ExistingDestinationArchiveName 'destination-archive-20260813-213700' `
                -CommitMessage 'Initial repository commit' `
                -PlanOnly

            $plan.Mode | Should -Be 'ExistingDestinationReplacement'
            $plan.DestinationExistedBeforeMigration | Should -BeTrue
            $plan.ArchiveRepository | Should -Be 'infoconex/destination-archive-20260813-213700'
            $plan.SourceState.CommitSha | Should -Be 'source-commit'
            @($plan.Steps)[0].Name | Should -Be 'PreserveDestinationAsArchive'
            @($plan.Steps)[1].Name | Should -Be 'CreateReplacementRepository'
        }
    }

    It 'rejects an archive-name collision before source-state capture or mutation' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{
                FullName = 'infoconex/source'
                Owner = 'infoconex'
                Visibility = 'public'
                DefaultBranch = 'main'
            }
            Mock Test-CgrGitHubRepositoryExistence { $true }
            Mock Get-CgrApprovedSourceState { throw 'source-state capture must not run after archive collision' }

            {
                New-CgrMigrationPlan `
                    -SourceRepository $source `
                    -DestinationRepository 'infoconex/destination' `
                    -ContentMode Snapshot `
                    -DestinationVisibility public `
                    -ExistingDestinationArchiveName 'destination-archive' `
                    -CommitMessage 'Initial repository commit' `
                    -PlanOnly
            } | Should -Throw -ErrorId 'ExistingDestinationArchiveAlreadyExists,New-CgrMigrationPlan'
        }
    }
}

Describe 'Existing destination archive and replace confirmation' {
    It 'requires the exact destination archive and replacement names' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{ DestinationRepository = 'infoconex/destination'; ArchiveRepository = 'infoconex/destination-archive' }
            $expected = 'DESTINATION=infoconex/destination;ARCHIVE=infoconex/destination-archive;REPLACEMENT=infoconex/destination'

            Assert-CgrExistingDestinationReplacementConfirmation -Plan $plan -Confirmation $expected | Should -BeTrue
            { Assert-CgrExistingDestinationReplacementConfirmation -Plan $plan -Confirmation 'destination' } |
                Should -Throw -ErrorId 'ExistingDestinationReplacementConfirmationRequired,Assert-CgrExistingDestinationReplacementConfirmation'
        }
    }
}

Describe 'Existing destination archive and replace recovery' {
    It 'preserves the renamed destination and records recovery when replacement copy fails' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'infoconex/source'; Id = 10 }
            $existingDestination = [pscustomobject] @{ FullName = 'infoconex/destination'; Id = 20 }
            $sourceState = [pscustomobject] @{ ContentMode = 'Snapshot'; Repository = 'infoconex/source'; RepositoryId = 10; DefaultBranch = 'main'; CommitSha = 'source-commit'; TreeSha = 'source-tree' }
            $plan = [pscustomobject] @{
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                ArchiveRepository = 'infoconex/destination-archive'
                DestinationVisibility = 'public'
                ContentMode = 'Snapshot'
                SourceState = $sourceState
            }

            Mock Assert-CgrApprovedSourceState { [pscustomobject] @{ DefaultBranch = 'main'; CommitSha = 'source-commit'; TreeSha = 'source-tree' } }
            Mock Rename-CgrGitHubRepository { [pscustomobject] @{ FullName = 'infoconex/destination-archive'; Id = 20 } }
            Mock New-CgrGitHubRepository { [pscustomobject] @{ FullName = 'infoconex/destination'; Id = 30 } }
            Mock Invoke-CgrNewDestinationSnapshot { throw 'Synthetic copy failure.' }
            Mock Write-CgrExistingDestinationRecoveryReport { 'recovery.json' }

            {
                Invoke-CgrExistingDestinationReplacement `
                    -Plan $plan `
                    -SourceRepository $source `
                    -ExistingDestinationRepository $existingDestination
            } | Should -Throw '*Synthetic copy failure*'

            Should -Invoke Assert-CgrApprovedSourceState -Times 1 -Exactly
            Should -Invoke Rename-CgrGitHubRepository -Times 1 -Exactly
            Should -Invoke New-CgrGitHubRepository -Times 1 -Exactly
            Should -Invoke Write-CgrExistingDestinationRecoveryReport -Times 1 -Exactly -ParameterFilter {
                $ArchiveRepository.FullName -eq 'infoconex/destination-archive' -and
                $DestinationRepository.FullName -eq 'infoconex/destination' -and
                $FailureStage -eq 'CopySnapshot'
            }
        }
    }
}
