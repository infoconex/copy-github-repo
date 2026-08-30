BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'GitHub API read response parity' {
    It 'uses the same protected failure contract for required and optional reads' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{
                    ExitCode = 1
                    Output = @()
                    ErrorText = 'HTTP 403: Forbidden Authorization: Bearer github_pat_123456789012345678901234567890'
                }
            }

            foreach ($command in @('Required', 'Optional')) {
                $caught = $null
                try {
                    if ($command -eq 'Required') {
                        Get-CgrGitHubApi -Path '/repos/acme/widget'
                    }
                    else {
                        Get-CgrGitHubApiOptional -Path '/repos/acme/widget/pages'
                    }
                }
                catch {
                    $caught = $_
                }

                $caught.FullyQualifiedErrorId | Should -BeLike 'GitHubApiRequestFailed*'
                $caught.Exception.Message | Should -Match 'HTTP 403: Forbidden'
                $caught.Exception.Message | Should -Match '\[REDACTED\]'
                $caught.Exception.Message | Should -Not -Match 'github_pat_123456789012345678901234567890'
            }
        }
    }

    It 'uses the same protected invalid-response contract for required and optional reads' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{
                    ExitCode = 0
                    Output = @('{"token":"github_pat_123456789012345678901234567890"')
                    ErrorText = ''
                }
            }

            foreach ($command in @('Required', 'Optional')) {
                $caught = $null
                try {
                    if ($command -eq 'Required') {
                        Get-CgrGitHubApi -Path '/repos/acme/widget'
                    }
                    else {
                        Get-CgrGitHubApiOptional -Path '/repos/acme/widget/pages'
                    }
                }
                catch {
                    $caught = $_
                }

                $caught.FullyQualifiedErrorId | Should -BeLike 'GitHubApiResponseInvalid*'
                $caught.Exception.Message | Should -Match 'was not valid JSON'
                $caught.Exception.Message | Should -Not -Match 'github_pat_123456789012345678901234567890'
            }
        }
    }

    It 'keeps empty-response semantics distinct between required and optional reads' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
            }

            @(Get-CgrGitHubApi -Path '/repos/acme/widget/topics').Count | Should -Be 0
            Get-CgrGitHubApiOptional -Path '/repos/acme/widget/pages' | Should -BeNullOrEmpty
        }
    }

    It 'keeps optional not-found handling distinct from ordinary optional failures' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrNativeCommand {
                if ($ArgumentList -contains '/repos/acme/widget/pages') {
                    return [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = 'HTTP 404: Not Found' }
                }

                [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = 'HTTP 403: Forbidden' }
            }

            Get-CgrGitHubApiOptional -Path '/repos/acme/widget/pages' | Should -BeNullOrEmpty
            { Get-CgrGitHubApiOptional -Path '/repos/acme/widget/rulesets' } |
                Should -Throw -ErrorId 'GitHubApiRequestFailed,Get-CgrGitHubApiOptional'
        }
    }
}
