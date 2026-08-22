BeforeAll {
    $script:repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $script:repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force
}

Describe 'Wizard navigation presentation' {
    It 'renders bracketed navigation hints in the standard order' {
        InModuleScope CopyGitHubRepo {
            Mock Format-CgrWizardText { param($Text) $Text }
            Mock Read-Host { '' }

            Read-CgrWizardInput -Prompt 'Choose a number' -AllowFilter -AllowHelp -AllowBack -AllowCancel | Out-Null

            Should -Invoke Read-Host -Times 1 -Exactly -ParameterFilter {
                $Prompt -eq 'Choose a number   [F filter]  [? help]  [B back]  [C cancel]'
            }
        }
    }

    It 'omits Back when the current screen does not support Back' {
        InModuleScope CopyGitHubRepo {
            Mock Format-CgrWizardText { param($Text) $Text }
            Mock Read-Host { '' }

            Read-CgrWizardInput -Prompt 'Choose a number' -AllowFilter -AllowHelp -AllowCancel | Out-Null

            Should -Invoke Read-Host -Times 1 -Exactly -ParameterFilter {
                $Prompt -eq 'Choose a number   [F filter]  [? help]  [C cancel]'
            }
        }
    }

    It 'accepts only the advertised short navigation keys' {
        InModuleScope CopyGitHubRepo {
            (Resolve-CgrWizardNavigationInput -InputText '?' -AllowHelp).Action | Should -Be 'Help'
            (Resolve-CgrWizardNavigationInput -InputText 'b' -AllowBack).Action | Should -Be 'Back'
            (Resolve-CgrWizardNavigationInput -InputText 'c' -AllowCancel).Action | Should -Be 'Cancel'
            Resolve-CgrWizardNavigationInput -InputText 'help' -AllowHelp | Should -BeNullOrEmpty
            Resolve-CgrWizardNavigationInput -InputText 'back' -AllowBack | Should -BeNullOrEmpty
            Resolve-CgrWizardNavigationInput -InputText 'cancel' -AllowCancel | Should -BeNullOrEmpty
        }
    }

    It 'advertises repository filtering through the same input abstraction' {
        InModuleScope CopyGitHubRepo {
            $repositories = @([pscustomobject] @{ FullName = 'infoconex/only' })
            Mock Write-CgrWizardMessage
            Mock Read-CgrWizardInput { '' } -ParameterFilter { $AllowFilter -and $AllowHelp -and $AllowCancel -and -not $AllowBack }

            $result = Select-CgrWizardRepository -Repositories $repositories -AllowCancel

            $result.Action | Should -Be 'Next'
            Should -Invoke Read-CgrWizardInput -Times 1 -Exactly -ParameterFilter { $AllowFilter -and $AllowHelp -and $AllowCancel -and -not $AllowBack }
        }
    }
}
