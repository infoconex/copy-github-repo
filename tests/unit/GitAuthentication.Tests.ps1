BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force
}

Describe 'Git authentication isolation' {
    It 'uses GitHub CLI as a non-interactive per-command credential helper' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{
                    PSTypeName = 'CopyGitHubRepo.NativeCommandResult'
                    ExitCode = 0
                    Output = @('ok')
                    ErrorText = ''
                }
            }

            $result = Invoke-CgrGitCommand `
                -HostName 'github.com' `
                -ArgumentList @('ls-remote', 'https://github.com/infoconex/private-repository.git')

            $result.ExitCode | Should -Be 0
            Should -Invoke Invoke-CgrNativeCommand -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq 'git' -and
                ($ArgumentList -join ' ') -eq 'ls-remote https://github.com/infoconex/private-repository.git' -and
                @($PrefixArgumentList).Count -eq 4 -and
                $PrefixArgumentList[0] -eq '-c' -and
                $PrefixArgumentList[1] -eq 'credential.https://github.com.helper=' -and
                $PrefixArgumentList[2] -eq '-c' -and
                $PrefixArgumentList[3] -eq 'credential.https://github.com.helper=!gh auth git-credential' -and
                $Environment.GIT_TERMINAL_PROMPT -eq '0'
            }
        }
    }

    It 'scopes the credential helper to the requested GitHub host' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{
                    PSTypeName = 'CopyGitHubRepo.NativeCommandResult'
                    ExitCode = 0
                    Output = @('ok')
                    ErrorText = ''
                }
            }

            Invoke-CgrGitCommand `
                -HostName 'github.example.com' `
                -ArgumentList @('clone', 'https://github.example.com/example/private.git') | Out-Null

            Should -Invoke Invoke-CgrNativeCommand -Times 1 -Exactly -ParameterFilter {
                $PrefixArgumentList[1] -eq 'credential.https://github.example.com.helper=' -and
                $PrefixArgumentList[3] -eq 'credential.https://github.example.com.helper=!gh auth git-credential'
            }
        }
    }

    It 'passes environment overrides only to the native child process' {
        InModuleScope CopyGitHubRepo {
            $variableName = 'CGR_NATIVE_COMMAND_TEST'
            $originalValue = [Environment]::GetEnvironmentVariable($variableName, 'Process')

            try {
                [Environment]::SetEnvironmentVariable($variableName, 'parent', 'Process')
                $powerShellPath = (Get-Command pwsh -ErrorAction Stop).Source
                $command = "[Environment]::GetEnvironmentVariable('$variableName', 'Process')"

                $result = Invoke-CgrNativeCommand `
                    -FilePath $powerShellPath `
                    -PrefixArgumentList @('-NoLogo') `
                    -ArgumentList @('-NoProfile', '-Command', $command) `
                    -Environment @{
                        $variableName = 'child'
                    }

                $result.ExitCode | Should -Be 0
                @($result.Output)[0].ToString() | Should -Be 'child'
                [Environment]::GetEnvironmentVariable($variableName, 'Process') | Should -Be 'parent'
                @($result.Arguments)[0] | Should -Be '-NoLogo'
            }
            finally {
                [Environment]::SetEnvironmentVariable($variableName, $originalValue, 'Process')
            }
        }
    }

    It 'captures stdout stderr and a non-zero native exit code separately' {
        InModuleScope CopyGitHubRepo {
            $powerShellPath = (Get-Command pwsh -ErrorAction Stop).Source
            $command = "[Console]::Out.WriteLine('stdout-marker'); [Console]::Error.WriteLine('stderr-marker'); exit 23"

            $result = Invoke-CgrNativeCommand `
                -FilePath $powerShellPath `
                -ArgumentList @('-NoLogo', '-NoProfile', '-Command', $command)

            $result.ExitCode | Should -Be 23
            (@($result.StandardOutput) -join '|') | Should -Match 'stdout-marker'
            (@($result.StandardOutput) -join '|') | Should -Not -Match 'stderr-marker'
            (@($result.StandardError) -join '|') | Should -Match 'stderr-marker'
            (@($result.StandardError) -join '|') | Should -Not -Match 'stdout-marker'
            (@($result.Output) -join '|') | Should -Match 'stdout-marker'
            (@($result.Output) -join '|') | Should -Not -Match 'stderr-marker'
            $result.ErrorText | Should -Not -Match 'stdout-marker'
            $result.ErrorText | Should -Match 'stderr-marker'
        }
    }

    It 'keeps overlapping native command environment overrides isolated from each other and the parent' {
        $variableName = 'CGR_NATIVE_COMMAND_CONCURRENT_TEST'
        $originalValue = [Environment]::GetEnvironmentVariable($variableName, 'Process')
        $workerScript = {
            param(
                [string] $ModulePath,
                [string] $VariableName,
                [string] $ChildValue
            )

            Import-Module $ModulePath -Force
            $module = Get-Module CopyGitHubRepo -ErrorAction Stop

            & $module {
                param(
                    [string] $VariableName,
                    [string] $ChildValue
                )

                $powerShellPath = (Get-Command pwsh -ErrorAction Stop).Source
                $command = "Start-Sleep -Milliseconds 500; [Environment]::GetEnvironmentVariable('$VariableName', 'Process')"
                Invoke-CgrNativeCommand `
                    -FilePath $powerShellPath `
                    -ArgumentList @('-NoLogo', '-NoProfile', '-Command', $command) `
                    -Environment @{
                        $VariableName = $ChildValue
                    }
            } $VariableName $ChildValue
        }

        $firstPowerShell = [PowerShell]::Create()
        $secondPowerShell = [PowerShell]::Create()

        try {
            [Environment]::SetEnvironmentVariable($variableName, 'parent', 'Process')

            [void] $firstPowerShell.AddScript($workerScript.ToString()).AddArgument($script:modulePath).AddArgument($variableName).AddArgument('first-child')
            [void] $secondPowerShell.AddScript($workerScript.ToString()).AddArgument($script:modulePath).AddArgument($variableName).AddArgument('second-child')

            $firstAsync = $firstPowerShell.BeginInvoke()
            $secondAsync = $secondPowerShell.BeginInvoke()
            Start-Sleep -Milliseconds 100

            [Environment]::GetEnvironmentVariable($variableName, 'Process') | Should -Be 'parent'

            $firstResult = @($firstPowerShell.EndInvoke($firstAsync))[-1]
            $secondResult = @($secondPowerShell.EndInvoke($secondAsync))[-1]

            $firstResult.ExitCode | Should -Be 0
            $secondResult.ExitCode | Should -Be 0
            @($firstResult.Output)[0].ToString() | Should -Be 'first-child'
            @($secondResult.Output)[0].ToString() | Should -Be 'second-child'
            [Environment]::GetEnvironmentVariable($variableName, 'Process') | Should -Be 'parent'
        }
        finally {
            $firstPowerShell.Dispose()
            $secondPowerShell.Dispose()
            [Environment]::SetEnvironmentVariable($variableName, $originalValue, 'Process')
        }
    }
}
