BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $root 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Wizard contextual help navigation' {
    It 'recognizes question mark as Help only when help is available' {
        InModuleScope CopyGitHubRepo {
            $help = Resolve-CgrWizardNavigationInput -InputText '?' -AllowHelp
            $help.Action | Should -Be 'Help'

            Resolve-CgrWizardNavigationInput -InputText '?' | Should -BeNullOrEmpty
        }
    }

    It 'shows choice help and returns to the same prompt without changing the selected value' {
        InModuleScope CopyGitHubRepo {
            $script:inputs = [System.Collections.Generic.Queue[string]]::new()
            $script:inputs.Enqueue('?')
            $script:inputs.Enqueue('')
            $script:inputs.Enqueue('')
            $script:messages = [System.Collections.Generic.List[string]]::new()
            Mock Read-CgrWizardInput { $script:inputs.Dequeue() }
            Mock Write-CgrWizardMessage {
                param($Message)
                if ($null -ne $Message) {
                    $script:messages.Add([string] $Message)
                }
            }

            $result = Read-CgrWizardChoice `
                -Title 'Content mode' `
                -Choices @('Snapshot', 'FullHistory') `
                -DefaultValue Snapshot `
                -HelpTopic ContentMode `
                -AllowCancel

            $result.Action | Should -Be 'Next'
            $result.Value | Should -Be 'Snapshot'
            ($script:messages -join "`n") | Should -Match 'Content mode help'
            ($script:messages -join "`n") | Should -Match 'FullHistory'
            Should -Invoke Read-CgrWizardInput -Times 3 -Exactly
        }
    }

    It 'shows text-input help and preserves a previously accepted value' {
        InModuleScope CopyGitHubRepo {
            $script:inputs = [System.Collections.Generic.Queue[string]]::new()
            $script:inputs.Enqueue('?')
            $script:inputs.Enqueue('')
            $script:inputs.Enqueue('')
            Mock Read-CgrWizardInput { $script:inputs.Dequeue() }
            Mock Write-CgrWizardMessage

            $result = Read-CgrWizardTextValue `
                -Title 'Snapshot commit message' `
                -DefaultValue 'Initial repository commit' `
                -CurrentValue 'Imported repository baseline' `
                -HelpTopic SnapshotCommitMessage `
                -AllowBack `
                -AllowCancel

            $result.Action | Should -Be 'Next'
            $result.Value | Should -Be 'Imported repository baseline'
            Should -Invoke Read-CgrWizardInput -Times 3 -Exactly
        }
    }

    It 'supports repeated help before normal Back navigation' {
        InModuleScope CopyGitHubRepo {
            $script:inputs = [System.Collections.Generic.Queue[string]]::new()
            $script:inputs.Enqueue('?')
            $script:inputs.Enqueue('')
            $script:inputs.Enqueue('?')
            $script:inputs.Enqueue('')
            $script:inputs.Enqueue('b')
            Mock Read-CgrWizardInput { $script:inputs.Dequeue() }
            Mock Write-CgrWizardMessage

            $result = Read-CgrWizardChoice `
                -Title 'Destination visibility' `
                -Choices @('public', 'private') `
                -DefaultValue public `
                -HelpTopic DestinationVisibility `
                -AllowBack `
                -AllowCancel

            $result.Action | Should -Be 'Back'
            Should -Invoke Read-CgrWizardInput -Times 5 -Exactly
        }
    }
}

Describe 'Wizard help isolation' {
    It 'keeps contextual help free of migration and GitHub mutation command calls' {
        $helpPath = Join-Path $root 'src/CopyGitHubRepo/Private/Wizard/Show-CgrWizardHelp.ps1'
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $helpPath,
            [ref] $tokens,
            [ref] $parseErrors
        )
        @($parseErrors).Count | Should -Be 0

        $commandNames = @(
            $ast.FindAll(
                {
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst]
                },
                $true
            ) |
                ForEach-Object { $_.GetCommandName() }
        )

        $commandNames | Should -Not -Contain 'Copy-GitHubRepository'
        $commandNames | Should -Not -Contain 'New-CgrGitHubRepository'
        $commandNames | Should -Not -Contain 'Rename-CgrGitHubRepository'
        $commandNames | Should -Not -Contain 'Set-CgrGitHubRepositorySetting'
    }
}
