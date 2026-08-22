BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force
}

Describe 'Native command stream semantics' {
    It 'returns only stdout through the compatibility Output property' {
        InModuleScope CopyGitHubRepo {
            $powerShellPath = (Get-Command pwsh -ErrorAction Stop).Source
            $command = "[Console]::Out.WriteLine('stdout-only'); [Console]::Error.WriteLine('stderr-only')"

            $result = Invoke-CgrNativeCommand `
                -FilePath $powerShellPath `
                -ArgumentList @('-NoLogo', '-NoProfile', '-Command', $command)

            $result.ExitCode | Should -Be 0
            @($result.StandardOutput) | Should -Be @('stdout-only')
            @($result.StandardError) | Should -Be @('stderr-only')
            @($result.Output) | Should -Be @('stdout-only')
            $result.ErrorText | Should -Be 'stderr-only'
        }
    }

    It 'terminates a native command when an explicit finite timeout expires' {
        InModuleScope CopyGitHubRepo {
            $powerShellPath = (Get-Command pwsh -ErrorAction Stop).Source
            $command = "[Console]::Error.WriteLine('before-timeout'); Start-Sleep -Seconds 10"
            $caught = $null
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                Invoke-CgrNativeCommand `
                    -FilePath $powerShellPath `
                    -ArgumentList @('-NoLogo', '-NoProfile', '-Command', $command) `
                    -Timeout ([TimeSpan]::FromMilliseconds(500))
            }
            catch {
                $caught = $_
            }
            finally {
                $stopwatch.Stop()
            }

            $caught | Should -Not -BeNullOrEmpty
            $caught.FullyQualifiedErrorId | Should -Match '^NativeCommandTimedOut'
            $caught.Exception.Message | Should -Match 'timed out'
            @($caught.Exception.Data['StandardError']) | Should -Contain 'before-timeout'
            $stopwatch.Elapsed.TotalSeconds | Should -BeLessThan 5
        }
    }

    It 'distinguishes explicit cancellation from timeout' {
        InModuleScope CopyGitHubRepo {
            $powerShellPath = (Get-Command pwsh -ErrorAction Stop).Source
            $command = "[Console]::Error.WriteLine('before-cancel'); Start-Sleep -Seconds 10"
            $cancellationSource = [System.Threading.CancellationTokenSource]::new()
            $caught = $null

            try {
                $cancellationSource.CancelAfter(500)
                Invoke-CgrNativeCommand `
                    -FilePath $powerShellPath `
                    -ArgumentList @('-NoLogo', '-NoProfile', '-Command', $command) `
                    -CancellationToken $cancellationSource.Token
            }
            catch {
                $caught = $_
            }
            finally {
                $cancellationSource.Dispose()
            }

            $caught | Should -Not -BeNullOrEmpty
            $caught.FullyQualifiedErrorId | Should -Match '^NativeCommandCancelled'
            $caught.Exception.Message | Should -Match 'was cancelled'
            @($caught.Exception.Data['StandardError']) | Should -Contain 'before-cancel'
        }
    }

    It 'rejects non-positive finite timeout values' {
        InModuleScope CopyGitHubRepo {
            $powerShellPath = (Get-Command pwsh -ErrorAction Stop).Source

            {
                Invoke-CgrNativeCommand `
                    -FilePath $powerShellPath `
                    -ArgumentList @('-NoLogo', '-NoProfile', '-Command', 'exit 0') `
                    -Timeout ([TimeSpan]::Zero)
            } | Should -Throw
        }
    }

    It 'parses successful GitHub API JSON when stderr contains a warning' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{
                    PSTypeName = 'CopyGitHubRepo.NativeCommandResult'
                    ExitCode = 0
                    StandardOutput = @('{"id":123,"name":"source"}')
                    StandardError = @('warning: harmless diagnostic')
                    Output = @('{"id":123,"name":"source"}')
                    ErrorText = 'warning: harmless diagnostic'
                }
            }

            $result = Get-CgrGitHubApi -Path 'repos/infoconex/source'

            $result.id | Should -Be 123
            $result.name | Should -Be 'source'
        }
    }

    It 'retains stderr diagnostics for a failed GitHub API request' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{
                    PSTypeName = 'CopyGitHubRepo.NativeCommandResult'
                    ExitCode = 1
                    StandardOutput = @('response-body')
                    StandardError = @('HTTP 403: Forbidden')
                    Output = @('response-body')
                    ErrorText = 'HTTP 403: Forbidden'
                }
            }

            { Get-CgrGitHubApi -Path 'repos/infoconex/source' } |
                Should -Throw -ErrorId 'GitHubApiRequestFailed,Get-CgrGitHubApi' -ExpectedMessage '*HTTP 403: Forbidden*'
        }
    }
}
