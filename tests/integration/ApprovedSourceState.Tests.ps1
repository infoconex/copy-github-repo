BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $root 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Approved repository copy source state' {
    It 'fails closed before creating a new destination when the approved source state has drifted' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'infoconex/source'; Id = 10L; NodeId = 'R_source' }
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'
                ContentMode = 'Snapshot'
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                DestinationVisibility = 'private'
                SourceState = [pscustomobject] @{ Repository = 'infoconex/source'; RepositoryId = 10L; RepositoryNodeId = 'R_source'; ContentMode = 'Snapshot' }
            }

            Mock Assert-CgrApprovedSourceState {
                $exception = [System.InvalidOperationException]::new('Source changed after plan review.')
                throw [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'SourceStateChangedSincePlanning',
                    [System.Management.Automation.ErrorCategory]::InvalidResult,
                    'infoconex/source'
                )
            }
            Mock New-CgrGitHubRepository { throw 'must not create destination' }

            { Invoke-CgrApprovedMigrationPlan -Plan $plan -SourceRepository $source } |
                Should -Throw -ErrorId 'SourceStateChangedSincePlanning'
            Should -Invoke New-CgrGitHubRepository -Times 0 -Exactly
        }
    }

    It 'fails closed before archiving an existing destination when source state has drifted' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'infoconex/source'; Id = 10L; NodeId = 'R_source' }
            $existing = [pscustomobject] @{ FullName = 'infoconex/destination'; Id = 20L; NodeId = 'R_destination' }
            $plan = [pscustomobject] @{
                Mode = 'ExistingDestinationReplacement'
                ContentMode = 'Snapshot'
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                ArchiveRepository = 'infoconex/destination-archive'
                DestinationVisibility = 'private'
                SourceState = [pscustomobject] @{ Repository = 'infoconex/source'; RepositoryId = 10L; RepositoryNodeId = 'R_source'; ContentMode = 'Snapshot' }
            }

            Mock Assert-CgrApprovedSourceState {
                $exception = [System.InvalidOperationException]::new('Source changed after plan review.')
                throw [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'SourceStateChangedSincePlanning',
                    [System.Management.Automation.ErrorCategory]::InvalidResult,
                    'infoconex/source'
                )
            }
            Mock Rename-CgrGitHubRepository { throw 'must not archive destination' }
            Mock Write-CgrExistingDestinationRecoveryReport { $null }

            { Invoke-CgrExistingDestinationReplacement -Plan $plan -SourceRepository $source -ExistingDestinationRepository $existing } |
                Should -Throw -ErrorId 'SourceStateChangedSincePlanning'
            Should -Invoke Rename-CgrGitHubRepository -Times 0 -Exactly
        }
    }

    It 'requires immutable source-state evidence at the approved execution boundary' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'infoconex/source' }
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'
                ContentMode = 'Snapshot'
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                DestinationVisibility = 'private'
            }

            { Invoke-CgrApprovedMigrationPlan -Plan $plan -SourceRepository $source } |
                Should -Throw -ErrorId 'ApprovedSourceStateMissing,Invoke-CgrApprovedMigrationPlan'
        }
    }
}
