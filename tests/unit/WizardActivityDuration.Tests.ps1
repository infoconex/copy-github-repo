BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $root 'src/CopyGitHubRepo/CopyGitHubRepo.psd1') -Force
}

Describe 'Wizard activity duration convention' {
    It 'shows elapsed time for a completed short stage' {
        InModuleScope CopyGitHubRepo {
            Mock Test-CgrInteractiveTerminal { $false }
            $script:messages = [System.Collections.Generic.List[object]]::new()
            Mock Write-CgrWizardMessage {
                param($Message, $Style, $Status)
                $script:messages.Add([pscustomobject] @{ Message = [string] $Message; Style = $Style; Status = $Status })
            }
            $sink = New-CgrWizardActivitySink
            $start = [DateTimeOffset]::UtcNow
            & $sink ([pscustomobject] @{ Name = 'ShortStage'; State = 'Started'; Message = 'Short work'; Timestamp = $start; Current = $null; Total = $null })
            & $sink ([pscustomobject] @{ Name = 'ShortStage'; State = 'Completed'; Message = 'Short work'; Timestamp = $start.AddMilliseconds(250); Current = $null; Total = $null })

            $completion = @($script:messages | Where-Object { $_.Status -eq 'Success' })
            $completion.Count | Should -Be 1
            $completion[0].Message | Should -Match '^Short work \([0-9]+\.[0-9]s\)$'
        }
    }
}
