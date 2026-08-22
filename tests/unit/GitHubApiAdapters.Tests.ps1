BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'GitHub API adapter contracts' {
    It 'forwards hostname and pagination arguments and flattens paged results' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{
                    ExitCode = 0
                    Output = @('[[{"id":1}],[{"id":2}]]')
                    ErrorText = ''
                }
            }

            $result = @(Get-CgrGitHubApi -Path '/repos/acme/widget/tags?per_page=100' -HostName 'github.example.com' -Paginate)

            $result.Count | Should -Be 2
            $result[0].id | Should -Be 1
            $result[1].id | Should -Be 2
            Should -Invoke Invoke-CgrNativeCommand -Times 1 -ParameterFilter {
                $FilePath -eq 'gh' -and
                $ArgumentList -contains '--hostname' -and
                $ArgumentList -contains 'github.example.com' -and
                $ArgumentList -contains '--paginate' -and
                $ArgumentList -contains '--slurp' -and
                $ArgumentList -contains '/repos/acme/widget/tags?per_page=100'
            }
        }
    }

    It 'returns empty collections for successful empty GET responses' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
            }

            @(Get-CgrGitHubApi -Path '/repos/acme/widget/topics').Count | Should -Be 0
        }
    }

    It 'retries a bounded transient read failure and succeeds' {
        InModuleScope CopyGitHubRepo {
            $script:readAttempt = 0
            Mock Get-Random { 0 }
            Mock Start-Sleep {}
            Mock Invoke-CgrNativeCommand {
                $script:readAttempt++
                if ($script:readAttempt -eq 1) {
                    return [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = 'HTTP 503: Service Unavailable' }
                }

                [pscustomobject] @{ ExitCode = 0; Output = @('{"ok":true}'); ErrorText = '' }
            }

            $result = Get-CgrGitHubApi -Path '/repos/acme/widget'

            $result.ok | Should -BeTrue
            Should -Invoke Invoke-CgrNativeCommand -Times 2
            Should -Invoke Start-Sleep -Times 1 -ParameterFilter { $Milliseconds -eq 250 }
        }
    }

    It 'honors a surfaced Retry-After value for a retryable read' {
        InModuleScope CopyGitHubRepo {
            $script:readAttempt = 0
            Mock Start-Sleep {}
            Mock Invoke-CgrNativeCommand {
                $script:readAttempt++
                if ($script:readAttempt -eq 1) {
                    return [pscustomobject] @{
                        ExitCode = 1
                        Output = @()
                        ErrorText = 'HTTP 429: rate limit exceeded Retry-After: 1'
                    }
                }

                [pscustomobject] @{ ExitCode = 0; Output = @('{"ok":true}'); ErrorText = '' }
            }

            $result = Get-CgrGitHubApi -Path '/repos/acme/widget'

            $result.ok | Should -BeTrue
            Should -Invoke Invoke-CgrNativeCommand -Times 2
            Should -Invoke Start-Sleep -Times 1 -ParameterFilter { $Milliseconds -eq 1000 }
        }
    }

    It 'does not retry earlier than excessive server retry guidance' {
        InModuleScope CopyGitHubRepo {
            Mock Start-Sleep {}
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{
                    ExitCode = 1
                    Output = @()
                    ErrorText = 'HTTP 429: rate limit exceeded Retry-After: 120'
                }
            }

            $caught = $null
            try {
                Get-CgrGitHubApi -Path '/repos/acme/widget'
            }
            catch {
                $caught = $_
            }

            $caught.FullyQualifiedErrorId | Should -BeLike 'GitHubApiRequestFailed*'
            $caught.Exception.Message | Should -Match 'requested a 120 second delay'
            $caught.Exception.Message | Should -Match '60 second automatic-wait limit'
            Should -Invoke Invoke-CgrNativeCommand -Times 1
            Should -Invoke Start-Sleep -Times 0
        }
    }

    It 'does not retry ordinary authorization failures' {
        InModuleScope CopyGitHubRepo {
            Mock Start-Sleep {}
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = 'HTTP 403: Forbidden' }
            }

            { Get-CgrGitHubApi -Path '/repos/acme/widget' } | Should -Throw

            Should -Invoke Invoke-CgrNativeCommand -Times 1
            Should -Invoke Start-Sleep -Times 0
        }
    }

    It 'reports exhausted bounded retry attempts' {
        InModuleScope CopyGitHubRepo {
            Mock Get-Random { 0 }
            Mock Start-Sleep {}
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = 'HTTP 503: Service Unavailable' }
            }

            $caught = $null
            try {
                Get-CgrGitHubApi -Path '/repos/acme/widget'
            }
            catch {
                $caught = $_
            }

            $caught.FullyQualifiedErrorId | Should -BeLike 'GitHubApiRequestFailed*'
            $caught.Exception.Message | Should -Match 'after 3 attempts'
            Should -Invoke Invoke-CgrNativeCommand -Times 3
            Should -Invoke Start-Sleep -Times 2
        }
    }

    It 'treats optional 404 responses as absent resources without retrying' {
        InModuleScope CopyGitHubRepo {
            Mock Start-Sleep {}
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = 'HTTP 404: Not Found' }
            }

            Get-CgrGitHubApiOptional -Path '/repos/acme/widget/pages' | Should -BeNullOrEmpty
            Should -Invoke Invoke-CgrNativeCommand -Times 1
            Should -Invoke Start-Sleep -Times 0
        }
    }

    It 'preserves useful failures while redacting authentication material' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{
                    ExitCode = 1
                    Output = @()
                    ErrorText = 'HTTP 403: Forbidden Authorization: Bearer github_pat_123456789012345678901234567890'
                }
            }

            $caught = $null
            try {
                Get-CgrGitHubApi -Path '/repos/acme/widget'
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

    It 'never automatically retries mutation failures' {
        InModuleScope CopyGitHubRepo {
            Mock Start-Sleep {}
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = 'HTTP 503: Service Unavailable' }
            }

            { Invoke-CgrGitHubApiMutation -Method PATCH -Path '/repos/acme/widget' -Body $null } |
                Should -Throw -ErrorId 'GitHubApiMutationFailed,Invoke-CgrGitHubApiMutation'

            Should -Invoke Invoke-CgrNativeCommand -Times 1
            Should -Invoke Start-Sleep -Times 0
        }
    }

    It 'wraps malformed mutation responses in the adapter error contract' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @('{not-json'); ErrorText = '' }
            }

            { Invoke-CgrGitHubApiMutation -Method PATCH -Path '/repos/acme/widget' -Body $null } |
                Should -Throw -ErrorId 'GitHubApiMutationResponseInvalid,Invoke-CgrGitHubApiMutation'
        }
    }

    It 'sends mutation method, hostname, path and JSON through an input file then removes it' {
        InModuleScope CopyGitHubRepo {
            $script:capturedArguments = $null
            $script:capturedBody = $null
            Mock Invoke-CgrNativeCommand {
                $script:capturedArguments = @($ArgumentList)
                $inputIndex = [array]::IndexOf($script:capturedArguments, '--input')
                $inputPath = $script:capturedArguments[$inputIndex + 1]
                $script:capturedBody = Get-Content -LiteralPath $inputPath -Raw
                [pscustomobject] @{ ExitCode = 0; Output = @('{"ok":true}'); ErrorText = '' }
            }

            $result = Invoke-CgrGitHubApiMutation `
                -Method PATCH `
                -Path '/repos/acme/widget' `
                -Body ([pscustomobject] @{ archived = $true }) `
                -HostName 'github.example.com'

            $result.ok | Should -BeTrue
            $script:capturedArguments | Should -Contain 'PATCH'
            $script:capturedArguments | Should -Contain 'github.example.com'
            $script:capturedArguments | Should -Contain '/repos/acme/widget'
            $script:capturedBody | Should -Match '"archived":true'
            $inputIndex = [array]::IndexOf($script:capturedArguments, '--input')
            Test-Path -LiteralPath $script:capturedArguments[$inputIndex + 1] | Should -BeFalse
        }
    }
}
