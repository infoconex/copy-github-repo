BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $root 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Wizard orchestration' {
    It 'plans before execution and executes the exact reviewed plan' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'infoconex/source'; Owner = 'infoconex'; Visibility = 'public' }
            $sourceState = [pscustomobject] @{ ContentMode = 'Snapshot'; CommitSha = 'source-commit'; TreeSha = 'source-tree'; DefaultBranch = 'main' }
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                ArchiveRepository = $null
                ContentMode = 'Snapshot'
                CommitMessage = 'Initial repository commit'
                DestinationVisibility = 'public'
                SourceState = $sourceState
                Steps = @([pscustomobject] @{ Description = 'Create destination.' })
            }
            Mock Write-CgrWizardMessage
            Mock Get-GitHubRepository { @($source) }
            Mock Select-CgrWizardRepository { ConvertTo-CgrWizardNavigationResult -Action Next -Value $source }
            Mock Test-CgrGitHubRepositoryExistence { $false }
            Mock Read-CgrWizardRepositoryName { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'infoconex/destination' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Snapshot' } -ParameterFilter { $Title -eq 'Content mode' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'public' } -ParameterFilter { $Title -eq 'Destination visibility' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Restore' } -ParameterFilter { $Title -eq 'Supported repository settings' }
            Mock Read-CgrWizardTextValue { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Initial repository commit' } -ParameterFilter { $Title -eq 'Snapshot commit message' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Execute' } -ParameterFilter { $Title -eq 'Repository copy plan' }
            Mock Copy-GitHubRepository { $plan } -ParameterFilter { $PlanOnly }
            Mock Invoke-CgrApprovedMigrationPlan {
                [pscustomobject] @{ Status = 'Completed'; Plan = $Plan; CompletedSteps = @() }
            }

            $result = Invoke-CgrRepositoryCopyWizard -HostName github.com -ExecutionGuard { $true }

            $result.Status | Should -Be 'Completed'
            $result.Plan | Should -Be $plan
            Should -Invoke Copy-GitHubRepository -Times 1 -Exactly -ParameterFilter {
                $PlanOnly -and $CommitMessage -eq 'Initial repository commit'
            }
            Should -Invoke Invoke-CgrApprovedMigrationPlan -Times 1 -Exactly -ParameterFilter {
                [object]::ReferenceEquals($Plan, $plan) -and $SourceRepository.FullName -eq 'infoconex/source'
            }
        }
    }

    It 'returns cancellation without planning' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'infoconex/source'; Owner = 'infoconex'; Visibility = 'public' }
            Mock Write-CgrWizardMessage
            Mock Get-GitHubRepository { @($source) }
            Mock Select-CgrWizardRepository { ConvertTo-CgrWizardNavigationResult -Action Next -Value $source }
            Mock Test-CgrGitHubRepositoryExistence { $false }
            Mock Read-CgrWizardRepositoryName { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'infoconex/destination' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Cancel } -ParameterFilter { $Title -eq 'Content mode' }
            Mock Copy-GitHubRepository
            Mock Invoke-CgrApprovedMigrationPlan

            $result = Invoke-CgrRepositoryCopyWizard -HostName github.com -ExecutionGuard { $true }

            $result.Status | Should -Be 'Cancelled'
            $result.MutatedGitHub | Should -BeFalse
            Should -Invoke Copy-GitHubRepository -Times 0 -Exactly
            Should -Invoke Invoke-CgrApprovedMigrationPlan -Times 0 -Exactly
        }
    }

    It 'can cancel after a real plan is created without invoking execution' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'infoconex/source'; Owner = 'infoconex'; Visibility = 'public' }
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                ArchiveRepository = $null
                ContentMode = 'Snapshot'
                CommitMessage = 'Initial repository commit'
                DestinationVisibility = 'public'
                SourceState = [pscustomobject] @{ ContentMode = 'Snapshot'; CommitSha = 'source-commit'; TreeSha = 'source-tree'; DefaultBranch = 'main' }
                Steps = @([pscustomobject] @{ Description = 'Create destination.' })
            }
            Mock Write-CgrWizardMessage
            Mock Get-GitHubRepository { @($source) }
            Mock Select-CgrWizardRepository { ConvertTo-CgrWizardNavigationResult -Action Next -Value $source }
            Mock Test-CgrGitHubRepositoryExistence { $false }
            Mock Read-CgrWizardRepositoryName { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'infoconex/destination' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Snapshot' } -ParameterFilter { $Title -eq 'Content mode' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'public' } -ParameterFilter { $Title -eq 'Destination visibility' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Restore' } -ParameterFilter { $Title -eq 'Supported repository settings' }
            Mock Read-CgrWizardTextValue { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Initial repository commit' } -ParameterFilter { $Title -eq 'Snapshot commit message' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Cancel } -ParameterFilter { $Title -eq 'Repository copy plan' }
            Mock Copy-GitHubRepository { $plan } -ParameterFilter { $PlanOnly }
            Mock Invoke-CgrApprovedMigrationPlan { throw 'Execution must not be invoked after plan-review cancellation.' }

            $result = Invoke-CgrRepositoryCopyWizard -HostName github.com -ExecutionGuard { $true }

            $result.Status | Should -Be 'Cancelled'
            $result.MutatedGitHub | Should -BeFalse
            Should -Invoke Copy-GitHubRepository -Times 1 -Exactly -ParameterFilter { $PlanOnly }
            Should -Invoke Invoke-CgrApprovedMigrationPlan -Times 0 -Exactly
        }
    }
}
