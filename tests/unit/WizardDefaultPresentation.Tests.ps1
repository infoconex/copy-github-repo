BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $root 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Wizard default presentation' {
    It 'marks and forwards the Enter-to-accept default for a listed choice' {
        InModuleScope CopyGitHubRepo {
            $script:messages = [System.Collections.Generic.List[string]]::new()
            $script:prompt = $null
            $script:defaultValue = $null
            Mock Write-CgrWizardMessage {
                param($Message)
                if ($null -ne $Message) { $script:messages.Add([string] $Message) }
            }
            Mock Read-CgrWizardInput {
                param($Prompt, $DefaultValue)
                $script:prompt = $Prompt
                $script:defaultValue = $DefaultValue
                ''
            }

            $result = Read-CgrWizardChoice -Title 'Content mode' -Choices @('Snapshot', 'FullHistory') -DefaultValue Snapshot -HelpTopic ContentMode

            $result.Value | Should -Be 'Snapshot'
            ($script:messages -join "`n") | Should -Match '1\. Snapshot \(default\)'
            $script:prompt | Should -Be 'Choose an option'
            $script:defaultValue | Should -Be 'Snapshot'
        }
    }

    It 'uses the current listed value as the displayed Enter default when revisiting a step' {
        InModuleScope CopyGitHubRepo {
            $script:prompt = $null
            $script:defaultValue = $null
            Mock Write-CgrWizardMessage
            Mock Read-CgrWizardInput {
                param($Prompt, $DefaultValue)
                $script:prompt = $Prompt
                $script:defaultValue = $DefaultValue
                ''
            }

            $result = Read-CgrWizardChoice -Title 'Content mode' -Choices @('Snapshot', 'FullHistory') -DefaultValue Snapshot -CurrentValue FullHistory

            $result.Value | Should -Be 'FullHistory'
            $script:prompt | Should -Be 'Choose an option'
            $script:defaultValue | Should -Be 'FullHistory'
        }
    }

    It 'forwards a free-text effective default to the shared prompt renderer' {
        InModuleScope CopyGitHubRepo {
            $script:prompt = $null
            $script:defaultValue = $null
            Mock Write-CgrWizardMessage
            Mock Read-CgrWizardInput {
                param($Prompt, $DefaultValue)
                $script:prompt = $Prompt
                $script:defaultValue = $DefaultValue
                ''
            }

            $result = Read-CgrWizardTextValue -Title 'Snapshot commit message' -DefaultValue 'Initial repository commit' -HelpTopic SnapshotCommitMessage

            $result.Value | Should -Be 'Initial repository commit'
            $script:prompt | Should -Be 'Snapshot commit message'
            $script:defaultValue | Should -Be 'Initial repository commit'
        }
    }

    It 'forwards a current repository name to the shared prompt renderer' {
        InModuleScope CopyGitHubRepo {
            $script:prompt = $null
            $script:defaultValue = $null
            Mock Write-CgrWizardMessage
            Mock Read-CgrWizardInput {
                param($Prompt, $DefaultValue)
                $script:prompt = $Prompt
                $script:defaultValue = $DefaultValue
                ''
            }

            $result = Read-CgrWizardRepositoryName -Kind Archive -CurrentValue 'destination-archive-20260813-2212'

            $result.Value | Should -Be 'destination-archive-20260813-2212'
            $script:prompt | Should -Be 'Archive repository name'
            $script:defaultValue | Should -Be 'destination-archive-20260813-2212'
        }
    }

    It 'renders navigation hints and trailing defaults as plain text when styling is unavailable' {
        InModuleScope CopyGitHubRepo {
            Mock Test-CgrConsoleStylingAvailable { $false }
            Mock Read-Host { param($Prompt) $script:renderedPrompt = $Prompt; '' }
            $script:renderedPrompt = $null

            Read-CgrWizardInput -Prompt 'Choose an option' -DefaultValue Snapshot -AllowHelp -AllowBack -AllowCancel | Out-Null

            $script:renderedPrompt | Should -Be 'Choose an option   [? help]  [B back]  [C cancel]   (Snapshot)'
            $script:renderedPrompt | Should -Not -Match '\x1b'
        }
    }

    It 'uses gray italic styling for prompt affordances and defaults when styling is available' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
        InModuleScope CopyGitHubRepo {
            Mock Test-CgrConsoleStylingAvailable { $true }
            $hint = Format-CgrWizardText -Text '[? help]  (Snapshot)' -Style Hint
            $italic = "`e[3m"

            $hint.Contains($PSStyle.Foreground.BrightBlack) | Should -BeTrue
            $hint.Contains($italic) | Should -BeTrue
            $hint.EndsWith($PSStyle.Reset) | Should -BeTrue
        }
    }
}
