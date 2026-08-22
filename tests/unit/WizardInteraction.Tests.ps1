BeforeAll {
    $script:repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $script:repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force

    $script:repositories = @(
        [pscustomobject] @{
            FullName = 'infoconex/alpha'
        }
        [pscustomobject] @{
            FullName = 'infoconex/beta'
        }
        [pscustomobject] @{
            FullName = 'other/gamma'
        }
    )
}

Describe 'Wizard interaction helpers' {
    It 'isolates interactive reads behind one mockable helper' {
        InModuleScope CopyGitHubRepo {
            Mock Format-CgrWizardText { $Text }
            Mock Read-Host { 'typed-value' }

            Read-CgrWizardInput -Prompt 'Value' | Should -Be 'typed-value'

            Should -Invoke Read-Host -Times 1 -Exactly -ParameterFilter {
                $Prompt -eq 'Value'
            }
        }
    }

    It 'accepts an explicit default constrained choice with Enter' {
        InModuleScope CopyGitHubRepo {
            Mock Write-CgrWizardMessage
            Mock Read-CgrWizardInput { '' }

            $result = Read-CgrWizardChoice `
                -Title 'Content mode' `
                -Choices @('Snapshot', 'FullHistory') `
                -DefaultValue Snapshot `
                -AllowCancel

            $result.Action | Should -Be 'Next'
            $result.Value | Should -Be 'Snapshot'
        }
    }

    It 'retries an invalid constrained choice before accepting a numbered choice' {
        InModuleScope CopyGitHubRepo {
            $script:inputs = [System.Collections.Generic.Queue[string]]::new()
            $script:inputs.Enqueue('9')
            $script:inputs.Enqueue('2')
            Mock Write-CgrWizardMessage
            Mock Read-CgrWizardInput { $script:inputs.Dequeue() }

            $result = Read-CgrWizardChoice `
                -Title 'Content mode' `
                -Choices @('Snapshot', 'FullHistory')

            $result.Action | Should -Be 'Next'
            $result.Value | Should -Be 'FullHistory'
            Should -Invoke Read-CgrWizardInput -Times 2 -Exactly
        }
    }

    It 'returns Back and Cancel as normal navigation outcomes' {
        InModuleScope CopyGitHubRepo {
            $script:inputs = [System.Collections.Generic.Queue[string]]::new()
            $script:inputs.Enqueue('b')
            $script:inputs.Enqueue('c')
            Mock Write-CgrWizardMessage
            Mock Read-CgrWizardInput { $script:inputs.Dequeue() }

            $back = Read-CgrWizardChoice `
                -Title 'Content mode' `
                -Choices @('Snapshot', 'FullHistory') `
                -AllowBack `
                -AllowCancel
            $cancel = Read-CgrWizardChoice `
                -Title 'Restore settings' `
                -Choices @('Yes', 'No') `
                -AllowBack `
                -AllowCancel

            $back.Action | Should -Be 'Back'
            $back.Value | Should -BeNullOrEmpty
            $cancel.Action | Should -Be 'Cancel'
            $cancel.Value | Should -BeNullOrEmpty
        }
    }

    It 'reuses a previously accepted constrained value when a step is revisited' {
        InModuleScope CopyGitHubRepo {
            Mock Write-CgrWizardMessage
            Mock Read-CgrWizardInput { '' }

            $result = Read-CgrWizardChoice `
                -Title 'Content mode' `
                -Choices @('Snapshot', 'FullHistory') `
                -CurrentValue FullHistory `
                -AllowBack

            $result.Action | Should -Be 'Next'
            $result.Value | Should -Be 'FullHistory'
        }
    }

    It 'rejects invalid destination repository input and accepts owner/name' {
        InModuleScope CopyGitHubRepo {
            $script:inputs = [System.Collections.Generic.Queue[string]]::new()
            $script:inputs.Enqueue('not-a-full-name')
            $script:inputs.Enqueue('infoconex/destination')
            Mock Write-CgrWizardMessage
            Mock Read-CgrWizardInput { $script:inputs.Dequeue() }

            $result = Read-CgrWizardRepositoryName -Kind Destination -AllowCancel

            $result.Action | Should -Be 'Next'
            $result.Value | Should -Be 'infoconex/destination'
            Should -Invoke Read-CgrWizardInput -Times 2 -Exactly
        }
    }

    It 'accepts and reuses a valid archive name when revisiting the step' {
        InModuleScope CopyGitHubRepo {
            Mock Write-CgrWizardMessage
            Mock Read-CgrWizardInput { '' }

            $result = Read-CgrWizardRepositoryName `
                -Kind Archive `
                -CurrentValue source-archive `
                -AllowBack `
                -AllowCancel

            $result.Action | Should -Be 'Next'
            $result.Value | Should -Be 'source-archive'
        }
    }

    It 'handles zero repository results through explicit navigation without throwing' {
        InModuleScope CopyGitHubRepo {
            Mock Write-CgrWizardMessage
            Mock Read-CgrWizardInput { 'b' }

            $result = Select-CgrWizardRepository `
                -Repositories @() `
                -AllowBack `
                -AllowCancel

            $result.Action | Should -Be 'Back'
            $result.Value | Should -BeNullOrEmpty
        }
    }

    It 'uses the only repository as the explicit default' {
        InModuleScope CopyGitHubRepo {
            $repository = [pscustomobject] @{
                FullName = 'infoconex/only'
            }
            Mock Write-CgrWizardMessage
            Mock Read-CgrWizardInput { '' }

            $result = Select-CgrWizardRepository -Repositories @($repository) -AllowCancel

            $result.Action | Should -Be 'Next'
            $result.Value.FullName | Should -Be 'infoconex/only'
        }
    }

    It 'filters a larger repository list before numbered selection' {
        InModuleScope CopyGitHubRepo -Parameters @{
            Repositories = $script:repositories
        } {
            $script:inputs = [System.Collections.Generic.Queue[string]]::new()
            $script:inputs.Enqueue('f')
            $script:inputs.Enqueue('beta')
            $script:inputs.Enqueue('1')
            Mock Write-CgrWizardMessage
            Mock Read-CgrWizardInput { $script:inputs.Dequeue() }

            $result = Select-CgrWizardRepository `
                -Repositories $Repositories `
                -AllowBack `
                -AllowCancel

            $result.Action | Should -Be 'Next'
            $result.Value.FullName | Should -Be 'infoconex/beta'
            Should -Invoke Read-CgrWizardInput -Times 3 -Exactly
        }
    }

    It 'retries an invalid repository number and then accepts a valid selection' {
        InModuleScope CopyGitHubRepo -Parameters @{
            Repositories = $script:repositories
        } {
            $script:inputs = [System.Collections.Generic.Queue[string]]::new()
            $script:inputs.Enqueue('8')
            $script:inputs.Enqueue('2')
            Mock Write-CgrWizardMessage
            Mock Read-CgrWizardInput { $script:inputs.Dequeue() }

            $result = Select-CgrWizardRepository -Repositories $Repositories -AllowCancel

            $result.Action | Should -Be 'Next'
            $result.Value.FullName | Should -Be 'infoconex/beta'
            Should -Invoke Read-CgrWizardInput -Times 2 -Exactly
        }
    }

    It 'reuses the previously selected repository when revisiting the step' {
        InModuleScope CopyGitHubRepo -Parameters @{
            Repositories = $script:repositories
            CurrentValue = $script:repositories[1]
        } {
            Mock Write-CgrWizardMessage
            Mock Read-CgrWizardInput { '' }

            $result = Select-CgrWizardRepository `
                -Repositories $Repositories `
                -CurrentValue $CurrentValue `
                -AllowBack `
                -AllowCancel

            $result.Action | Should -Be 'Next'
            $result.Value.FullName | Should -Be 'infoconex/beta'
        }
    }

    It 'keeps interaction helpers free of migration and GitHub mutation calls' {
        $wizardRoot = Join-Path $script:repositoryRoot 'src/CopyGitHubRepo/Private/Wizard'
        $helperPaths = @(
            'ConvertTo-CgrWizardNavigationResult.ps1'
            'Read-CgrWizardChoice.ps1'
            'Read-CgrWizardInput.ps1'
            'Read-CgrWizardRepositoryName.ps1'
            'Resolve-CgrWizardNavigationInput.ps1'
            'Select-CgrWizardRepository.ps1'
            'Write-CgrWizardMessage.ps1'
        )
        $helperText = $helperPaths |
            ForEach-Object { Get-Content -LiteralPath (Join-Path $wizardRoot $_) -Raw } |
            Out-String

        $helperText | Should -Not -Match '\bCopy-GitHubRepository\b'
        $helperText | Should -Not -Match '\bNew-CgrGitHubRepository\b'
        $helperText | Should -Not -Match '\bRename-CgrGitHubRepository\b'
        $helperText | Should -Not -Match '\bSet-CgrGitHubRepositorySetting\b'
    }
}
