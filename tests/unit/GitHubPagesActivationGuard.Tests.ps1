BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'GitHub Pages workflow activation guard' {
    It 'disables and verifies Actions on a fresh destination before repository creation returns when Pages restoration is reviewed' {
        InModuleScope CopyGitHubRepo {
            $script:CgrPagesWorkflowActivationGuardRequested = $true
            $script:activationEvents = [System.Collections.Generic.List[string]]::new()
            Mock Send-CgrActivityEvent {}
            Mock Invoke-CgrNativeCommand {
                $script:activationEvents.Add('CreateRepository')
                [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
            }
            Mock Get-CgrRepository {
                [pscustomobject] @{ FullName = 'acme/destination'; HtmlUrl = 'https://github.com/acme/destination' }
            }
            Mock Invoke-CgrGitHubApiMutation {
                $script:activationEvents.Add('GuardActions')
            }
            Mock Get-CgrGitHubApi {
                $script:activationEvents.Add('VerifyGuard')
                [pscustomobject] @{ enabled = $false }
            }

            $result = New-CgrGitHubRepository -Repository 'acme/destination' -Visibility public

            $result.FullName | Should -Be 'acme/destination'
            @($script:activationEvents) | Should -Be @('CreateRepository', 'GuardActions', 'VerifyGuard')
            Should -Invoke Invoke-CgrGitHubApiMutation -Times 1 -ParameterFilter {
                $Method -eq 'PUT' -and
                $Path -eq '/repos/acme/destination/actions/permissions' -and
                $Body.enabled -eq $false
            }
            Remove-Variable -Name CgrPagesWorkflowActivationGuardRequested -Scope Script -ErrorAction SilentlyContinue
        }
    }

    It 'fails closed before publication when the activation guard cannot be verified' {
        InModuleScope CopyGitHubRepo {
            $script:CgrPagesWorkflowActivationGuardRequested = $true
            Mock Send-CgrActivityEvent {}
            Mock Invoke-CgrNativeCommand { [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' } }
            Mock Get-CgrRepository { [pscustomobject] @{ FullName = 'acme/destination' } }
            Mock Invoke-CgrGitHubApiMutation {}
            Mock Get-CgrGitHubApi { [pscustomobject] @{ enabled = $true } }

            { New-CgrGitHubRepository -Repository 'acme/destination' -Visibility public } |
                Should -Throw -ErrorId 'PagesWorkflowActivationGuardVerificationFailed'

            Remove-Variable -Name CgrPagesWorkflowActivationGuardRequested -Scope Script -ErrorAction SilentlyContinue
        }
    }

    It 'does not alter Actions when Pages restoration was not requested' {
        InModuleScope CopyGitHubRepo {
            Remove-Variable -Name CgrPagesWorkflowActivationGuardRequested -Scope Script -ErrorAction SilentlyContinue
            Mock Send-CgrActivityEvent {}
            Mock Invoke-CgrNativeCommand { [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' } }
            Mock Get-CgrRepository { [pscustomobject] @{ FullName = 'acme/destination' } }
            Mock Invoke-CgrGitHubApiMutation { throw 'must not change Actions' }
            Mock Get-CgrGitHubApi { throw 'must not read Actions permissions' }

            New-CgrGitHubRepository -Repository 'acme/destination' -Visibility public | Out-Null

            Should -Invoke Invoke-CgrGitHubApiMutation -Times 0
            Should -Invoke Get-CgrGitHubApi -Times 0
        }
    }

    It 'carries the reviewed guard across every migration dispatch path and restores prior execution context afterward' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'acme/source' }
            $sourceState = [pscustomobject] @{ RepositoryId = 1 }
            $observed = [System.Collections.Generic.List[string]]::new()

            Mock Assert-CgrApprovedSourceState {}
            Mock Assert-CgrLocalResourcePreflight {}
            Mock Assert-CgrSameNameReplacementConfirmation {}
            Mock Assert-CgrExistingDestinationReplacementConfirmation {}
            Mock Get-CgrRepository { [pscustomobject] @{ FullName = 'acme/destination' } }
            Mock New-CgrGitHubRepository {
                $value = Get-Variable -Name CgrPagesWorkflowActivationGuardRequested -Scope Script -ErrorAction SilentlyContinue
                $observed.Add("New:$([bool] $value.Value)")
                [pscustomobject] @{ FullName = 'acme/destination' }
            }
            Mock Invoke-CgrNewDestinationSnapshot { [pscustomobject] @{ Status = 'Snapshot' } }
            Mock Invoke-CgrNewDestinationFullHistory { [pscustomobject] @{ Status = 'FullHistory' } }
            Mock Invoke-CgrSameNameSnapshotReplacement {
                $value = Get-Variable -Name CgrPagesWorkflowActivationGuardRequested -Scope Script -ErrorAction SilentlyContinue
                $observed.Add("SameSnapshot:$([bool] $value.Value)")
                [pscustomobject] @{ Status = 'SameSnapshot' }
            }
            Mock Invoke-CgrSameNameFullHistoryReplacement {
                $value = Get-Variable -Name CgrPagesWorkflowActivationGuardRequested -Scope Script -ErrorAction SilentlyContinue
                $observed.Add("SameFullHistory:$([bool] $value.Value)")
                [pscustomobject] @{ Status = 'SameFullHistory' }
            }
            Mock Invoke-CgrExistingDestinationReplacement {
                $value = Get-Variable -Name CgrPagesWorkflowActivationGuardRequested -Scope Script -ErrorAction SilentlyContinue
                $observed.Add("Existing:$([bool] $value.Value)")
                [pscustomobject] @{ Status = 'Existing' }
            }

            foreach ($case in @(
                    @{ Mode = 'NewDestination'; ContentMode = 'Snapshot' },
                    @{ Mode = 'NewDestination'; ContentMode = 'FullHistory' },
                    @{ Mode = 'SameNameReplacement'; ContentMode = 'Snapshot' },
                    @{ Mode = 'SameNameReplacement'; ContentMode = 'FullHistory' },
                    @{ Mode = 'ExistingDestinationReplacement'; ContentMode = 'Snapshot' }
                )) {
                $plan = [pscustomobject] @{
                    SourceState = $sourceState
                    SourceRepository = 'acme/source'
                    DestinationRepository = 'acme/destination'
                    DestinationVisibility = 'public'
                    Mode = $case.Mode
                    ContentMode = $case.ContentMode
                    RestorePages = $true
                }
                Invoke-CgrApprovedMigrationPlan -Plan $plan -SourceRepository $source -SameNameConfirmation 'approved' -ExistingDestinationConfirmation 'approved' | Out-Null
            }

            @($observed) | Should -Be @('New:True', 'New:True', 'SameSnapshot:True', 'SameFullHistory:True', 'Existing:True')
            Get-Variable -Name CgrPagesWorkflowActivationGuardRequested -Scope Script -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
    }
}
