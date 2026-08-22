BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $root 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Snapshot commit identity resolution' {
    It 'uses the caller Git configuration when name and email are available' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrNativeCommand {
                if ($ArgumentList[-1] -eq 'user.name') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('Jim Scott'); ErrorText = '' }
                }

                if ($ArgumentList[-1] -eq 'user.email') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('jim@example.com'); ErrorText = '' }
                }

                throw "Unexpected command: $FilePath $($ArgumentList -join ' ')"
            }

            $identity = Get-CgrGitCommitIdentity -HostName 'github.com'

            $identity.Name | Should -Be 'Jim Scott'
            $identity.Email | Should -Be 'jim@example.com'
            $identity.Source | Should -Be 'GitConfig'
            Should -Invoke Invoke-CgrNativeCommand -Times 2 -Exactly
        }
    }

    It 'falls back to the authenticated GitHub account when Git identity is not configured' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrNativeCommand {
                if ($FilePath -eq 'git') {
                    return [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = '' }
                }

                if ($FilePath -eq 'gh') {
                    return [pscustomobject] @{
                        ExitCode = 0
                        Output = @('{"login":"octocat","id":12345,"name":"Octo Cat","email":null}')
                        ErrorText = ''
                    }
                }

                throw "Unexpected command: $FilePath $($ArgumentList -join ' ')"
            }

            $identity = Get-CgrGitCommitIdentity -HostName 'github.com'

            $identity.Name | Should -Be 'Octo Cat'
            $identity.Email | Should -Be '12345+octocat@users.noreply.github.com'
            $identity.Source | Should -Be 'GitHubCLI'
            Should -Invoke Invoke-CgrNativeCommand -Times 3 -Exactly
        }
    }
}
