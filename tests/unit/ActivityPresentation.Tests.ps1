BeforeAll {
    $script:repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $script:repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force
}

Describe 'Wizard activity presentation' {
    It 'emits no structured output when no activity sink is installed' {
        InModuleScope CopyGitHubRepo {
            Remove-Variable -Name CgrActivitySink -Scope Script -ErrorAction SilentlyContinue
            $output = @(Send-CgrActivityEvent -Name Test -State Started -Message 'Testing')
            $output.Count | Should -Be 0
        }
    }

    It 'delivers semantic activity events to an installed sink without leaking them to the pipeline' {
        InModuleScope CopyGitHubRepo {
            $script:events = [System.Collections.Generic.List[object]]::new()
            $sink = { param($ActivityEvent) $script:events.Add($ActivityEvent) }

            $output = @(Invoke-CgrWithActivitySink -Sink $sink -Action {
                Send-CgrActivityEvent -Name Clone -State Started -Message 'Clone source'
                Send-CgrActivityEvent -Name Clone -State Completed -Message 'Clone source'
            })

            $output.Count | Should -Be 0
            $script:events.Count | Should -Be 2
            $script:events[0].PSTypeNames | Should -Contain 'CopyGitHubRepo.ActivityEvent'
            $script:events[0].Name | Should -Be 'Clone'
            $script:events[1].State | Should -Be 'Completed'
        }
    }

    It 'uses in-place progress only for an interactive terminal and retains a completed status line' {
        InModuleScope CopyGitHubRepo {
            Mock Test-CgrInteractiveTerminal { $true }
            Mock Write-Progress
            Mock Write-CgrWizardMessage
            $sink = New-CgrWizardActivitySink
            $started = [DateTimeOffset]::UtcNow.AddSeconds(-3)

            & $sink ([pscustomobject] @{ Name = 'Clone'; State = 'Started'; Message = 'Clone source'; Timestamp = $started; Current = $null; Total = $null })
            & $sink ([pscustomobject] @{ Name = 'Clone'; State = 'Completed'; Message = 'Clone source'; Timestamp = $started.AddSeconds(3); Current = $null; Total = $null })

            Should -Invoke Write-Progress -Times 2
            Should -Invoke Write-CgrWizardMessage -Times 1 -ParameterFilter {
                $Status -eq 'Success' -and $Message -match 'Clone source' -and $Message -match '3\.0s'
            }
        }
    }

    It 'uses line-oriented activity and no cursor progress when output is non-interactive' {
        InModuleScope CopyGitHubRepo {
            Mock Test-CgrInteractiveTerminal { $false }
            Mock Write-Progress
            Mock Write-CgrWizardMessage
            $sink = New-CgrWizardActivitySink
            $now = [DateTimeOffset]::UtcNow

            & $sink ([pscustomobject] @{ Name = 'Copy'; State = 'Started'; Message = 'Copy content'; Timestamp = $now; Current = $null; Total = $null })
            & $sink ([pscustomobject] @{ Name = 'Copy'; State = 'Completed'; Message = 'Copy content'; Timestamp = $now.AddSeconds(1); Current = $null; Total = $null })

            Should -Invoke Write-Progress -Times 0
            Should -Invoke Write-CgrWizardMessage -Times 1 -ParameterFilter { $Status -eq 'Info' }
            Should -Invoke Write-CgrWizardMessage -Times 1 -ParameterFilter { $Status -eq 'Success' }
        }
    }

    It 'renders a percentage only when a measurable current and total are supplied' {
        InModuleScope CopyGitHubRepo {
            Mock Test-CgrInteractiveTerminal { $true }
            Mock Write-Progress
            $sink = New-CgrWizardActivitySink
            $now = [DateTimeOffset]::UtcNow

            & $sink ([pscustomobject] @{ Name = 'Measured'; State = 'Progress'; Message = 'Measured work'; Timestamp = $now; Current = 2; Total = 4 })

            Should -Invoke Write-Progress -Times 1 -ParameterFilter { $PercentComplete -eq 50 }
        }
    }

    It 'marks a semantic stage failed when its action throws' {
        InModuleScope CopyGitHubRepo {
            $script:events = [System.Collections.Generic.List[object]]::new()
            $sink = { param($ActivityEvent) $script:events.Add($ActivityEvent) }

            { Invoke-CgrWithActivitySink -Sink $sink -Action {
                Invoke-CgrActivityStage -Name Verify -Message 'Verify content' -Action { throw 'failure' }
            } } | Should -Throw

            (@($script:events.State) -join ',') | Should -Be 'Started,Failed'
        }
    }
}
