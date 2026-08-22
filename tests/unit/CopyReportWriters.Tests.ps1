BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force
}

InModuleScope CopyGitHubRepo {
    Describe 'Repository copy report writers' {
        It 'writes a plan report in Markdown and creates the parent directory' {
            $root = Join-Path $TestDrive 'nested-plan'
            $path = Join-Path $root 'plan.md'
            $plan = [pscustomobject] @{ SourceRepository = 'infoconex/source' }
            Mock Format-CgrMigrationPlan { '# plan' } -ParameterFilter { $Format -eq 'Markdown' -and $Plan.SourceRepository -eq 'infoconex/source' }

            Write-CgrMigrationPlanReport -Plan $plan -Path $path

            Test-Path -LiteralPath $path | Should -BeTrue
            Get-Content -LiteralPath $path -Raw | Should -Match '# plan'
            Should -Invoke Format-CgrMigrationPlan -Times 1 -Exactly -ParameterFilter { $Format -eq 'Markdown' }
        }

        It 'writes a plan report in JSON when the extension is json' {
            $path = Join-Path $TestDrive 'plan.json'
            $plan = [pscustomobject] @{ SourceRepository = 'infoconex/source' }
            Mock Format-CgrMigrationPlan { '{"kind":"plan"}' } -ParameterFilter { $Format -eq 'Json' }

            Write-CgrMigrationPlanReport -Plan $plan -Path $path

            Get-Content -LiteralPath $path -Raw | Should -Match '"kind":"plan"'
            Should -Invoke Format-CgrMigrationPlan -Times 1 -Exactly -ParameterFilter { $Format -eq 'Json' }
        }

        It 'writes an execution report in Markdown and creates the parent directory' {
            $root = Join-Path $TestDrive 'nested-result'
            $path = Join-Path $root 'result.md'
            $result = [pscustomobject] @{ Status = 'Completed' }
            Mock Format-CgrMigrationExecutionResult { '# result' } -ParameterFilter { $Format -eq 'Markdown' -and $Result.Status -eq 'Completed' }

            Write-CgrMigrationExecutionReport -Result $result -Path $path

            Test-Path -LiteralPath $path | Should -BeTrue
            Get-Content -LiteralPath $path -Raw | Should -Match '# result'
            Should -Invoke Format-CgrMigrationExecutionResult -Times 1 -Exactly -ParameterFilter { $Format -eq 'Markdown' }
        }

        It 'writes an execution report in JSON when the extension is json' {
            $path = Join-Path $TestDrive 'result.json'
            $result = [pscustomobject] @{ Status = 'Completed' }
            Mock Format-CgrMigrationExecutionResult { '{"kind":"result"}' } -ParameterFilter { $Format -eq 'Json' }

            Write-CgrMigrationExecutionReport -Result $result -Path $path

            Get-Content -LiteralPath $path -Raw | Should -Match '"kind":"result"'
            Should -Invoke Format-CgrMigrationExecutionResult -Times 1 -Exactly -ParameterFilter { $Format -eq 'Json' }
        }
    }
}
