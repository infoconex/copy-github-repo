BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $root 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Local temporary-storage preflight' {
    It 'fails when free temp capacity is below the observed planning workspace before mutation' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                SourceState = [pscustomobject] @{ PlanningWorkspaceBytes = 1000L }
            }

            { Assert-CgrLocalResourcePreflight -Plan $plan -AvailableBytes 999L } |
                Should -Throw -ErrorId 'LocalTempSpaceInsufficient,Assert-CgrLocalResourcePreflight'
        }
    }

    It 'returns an advisory when capacity exceeds the lower bound but not 2x headroom' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                SourceState = [pscustomobject] @{ PlanningWorkspaceBytes = 1000L }
            }
            $warnings = @()

            $result = Assert-CgrLocalResourcePreflight -Plan $plan -AvailableBytes 1500L -WarningVariable warnings

            $result.Status | Should -Be 'Advisory'
            $result.ObservedPlanningWorkspaceBytes | Should -Be 1000L
            $result.AvailableBytes | Should -Be 1500L
            $result.AdvisoryHeadroomBytes | Should -Be 2000L
            @($warnings).Count | Should -Be 1
        }
    }

    It 'passes without warning when capacity is at least the advisory headroom' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                SourceState = [pscustomobject] @{ PlanningWorkspaceBytes = 1000L }
            }
            $warnings = @()

            $result = Assert-CgrLocalResourcePreflight -Plan $plan -AvailableBytes 2000L -WarningVariable warnings

            $result.Status | Should -Be 'Passed'
            @($warnings).Count | Should -Be 0
        }
    }

    It 'blocks destination creation when the execution-boundary resource preflight fails' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'infoconex/source' }
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'
                ContentMode = 'Snapshot'
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                DestinationVisibility = 'private'
                SourceState = [pscustomobject] @{ PlanningWorkspaceBytes = 1000L }
            }

            Mock Assert-CgrApprovedSourceState { $true }
            Mock Assert-CgrLocalResourcePreflight {
                $exception = [System.InvalidOperationException]::new('Insufficient temporary storage.')
                throw [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'LocalTempSpaceInsufficient',
                    [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
                    'temporary storage'
                )
            }
            Mock New-CgrGitHubRepository { throw 'must not create destination' }

            { Invoke-CgrApprovedMigrationPlan -Plan $plan -SourceRepository $source } |
                Should -Throw -ErrorId 'LocalTempSpaceInsufficient'
            Should -Invoke New-CgrGitHubRepository -Times 0 -Exactly
        }
    }
}
