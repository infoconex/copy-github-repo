BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $root 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Wizard application error classification' {
    It 'recognizes stable application error IDs without message matching' {
        InModuleScope CopyGitHubRepo {
            $exception = [System.InvalidOperationException]::new('Destination exists.')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'DestinationRepositoryAlreadyExists',
                [System.Management.Automation.ErrorCategory]::ResourceExists,
                'infoconex/destination'
            )

            Test-CgrExpectedWizardApplicationError -ErrorRecord $errorRecord | Should -BeTrue

            $unexpected = [System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new('Unexpected defect.'),
                'UnexpectedWizardDefect',
                [System.Management.Automation.ErrorCategory]::NotSpecified,
                $null
            )
            Test-CgrExpectedWizardApplicationError -ErrorRecord $unexpected | Should -BeFalse
        }
    }
}

Describe 'Wizard application error presentation' {
    It 'renders an expected application error as a clean wizard result without PowerShell invocation details' {
        InModuleScope CopyGitHubRepo {
            $messages = [System.Collections.Generic.List[string]]::new()
            Mock Write-CgrWizardMessage {
                param($Message)
                if ($null -ne $Message) {
                    $messages.Add([string] $Message)
                }
            }
            Mock Invoke-CgrRepositoryCopyWizard {
                $exception = [System.InvalidOperationException]::new(
                    "Destination repository 'infoconex/destination' already exists. The tool will not overwrite an existing repository."
                )
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'DestinationRepositoryAlreadyExists',
                    [System.Management.Automation.ErrorCategory]::ResourceExists,
                    'infoconex/destination'
                )
                Write-Error -ErrorRecord $errorRecord -ErrorAction Stop
            }

            $result = Start-CopyGitHubRepositoryWizard
            $rendered = $messages -join "`n"

            $result.PSTypeNames[0] | Should -Be 'CopyGitHubRepo.WizardResult'
            $result.Status | Should -Be 'ApplicationError'
            $result.MutatedGitHub | Should -BeFalse
            $result.ErrorId | Should -Be 'DestinationRepositoryAlreadyExists'
            $result.Message | Should -Match 'already exists'
            $rendered | Should -Match 'Unable to continue'
            $rendered | Should -Match 'already exists'
            $rendered | Should -Not -Match 'Line \|'
            $rendered | Should -Not -Match '\.ps1:'
            $rendered | Should -Not -Match 'New-CgrMigrationPlan:'
        }
    }

    It 'rethrows unexpected defects so diagnostics are not hidden' {
        InModuleScope CopyGitHubRepo {
            Mock Write-CgrWizardMessage
            Mock Invoke-CgrRepositoryCopyWizard {
                throw 'Unexpected wizard defect.'
            }

            {
                Start-CopyGitHubRepositoryWizard
            } | Should -Throw '*Unexpected wizard defect*'
        }
    }
}

Describe 'Direct command error contract' {
    It 'keeps the structured destination-exists terminating error for automation' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{
                FullName = 'infoconex/source'
                Owner = 'infoconex'
                Visibility = 'public'
                DefaultBranch = 'main'
            }

            Mock Get-CgrPrerequisiteStatus {
                [pscustomobject] @{
                    Git = [pscustomobject] @{ Found = $true }
                    GitHubCli = [pscustomobject] @{ Found = $true }
                    Authentication = [pscustomobject] @{ Authenticated = $true; Message = 'Authenticated.' }
                }
            }
            Mock Get-CgrRepository { $source }
            Mock Test-CgrGitHubRepositoryExistence { $true }

            {
                Copy-GitHubRepository `
                    -SourceRepository 'infoconex/source' `
                    -DestinationRepository 'infoconex/destination' `
                    -PlanOnly
            } | Should -Throw -ErrorId 'DestinationRepositoryAlreadyExists,New-CgrMigrationPlan'
        }
    }
}
