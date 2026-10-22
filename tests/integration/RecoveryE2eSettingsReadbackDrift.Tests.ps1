BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1') -Force -ErrorAction Stop
    . (Join-Path $repositoryRoot 'tests/support/Invoke-RecoveryE2eScopedSettingsReadbackDrift.ps1')
}

Describe 'Recovery E2E scoped settings readback drift' {
    It 'delegates a production-shaped PATCH, induces one scoped drift and restores the executor' {
        $module = Get-Module CopyGitHubRepo -ErrorAction Stop
        $destination = 'infoconex/copy-github-repo-recovery-e2e-123456789a-settingsfault-destination'
        $archive = 'infoconex/copy-github-repo-recovery-e2e-123456789a-settingsfault-archive'
        $approved = 'Approved disposable description'
        $drift = 'Independent description drift'

        & $module {
            param($destinationName, $archiveName)
            $script:RecoverySettingsFixtureOriginalNative = (Get-Item Function:Invoke-CgrNativeCommand).ScriptBlock
            $script:RecoverySettingsFixtureRequests = [System.Collections.Generic.List[string]]::new()
            $script:RecoverySettingsFixtureRepositories = @{
                "repos/$archiveName" = @{
                    full_name = $archiveName
                    id = 12345
                    private = $true
                    description = 'Old destination remains preserved'
                }
                "repos/$destinationName" = @{
                    full_name = $destinationName
                    id = 67890
                    private = $true
                    description = $null
                }
            }
            Set-Item -Path Function:script:Invoke-CgrNativeCommand -Value {
                [CmdletBinding()]
                param(
                    [Parameter(Mandatory)][string] $FilePath,
                    [string[]] $ArgumentList = @(),
                    [string[]] $PrefixArgumentList = @(),
                    [hashtable] $Environment = @{},
                    [TimeSpan] $Timeout = [System.Threading.Timeout]::InfiniteTimeSpan,
                    [System.Threading.CancellationToken] $CancellationToken = [System.Threading.CancellationToken]::None
                )
                if (@($PrefixArgumentList).Count -ne 0 -or $Environment.Count -ne 0 -or
                    $Timeout -ne [System.Threading.Timeout]::InfiniteTimeSpan -or $CancellationToken.CanBeCanceled) {
                    throw 'Fixture rejects unexpected native options.'
                }
                $arguments = @($ArgumentList)
                if ($FilePath -cne 'gh' -or $arguments.Count -lt 4 -or
                    $arguments[0] -cne 'api' -or $arguments[1] -cne '--hostname' -or
                    $arguments[2] -cne 'github.com') {
                    throw 'Fixture received an unexpected native invocation.'
                }
                $repoPath = if ($arguments.Count -ge 6) { [string] $arguments[5] } else { [string] $arguments[3] }
                if (-not $script:RecoverySettingsFixtureRepositories.ContainsKey($repoPath)) {
                    throw 'Fixture rejected an unexpected repository path.'
                }
                $target = $script:RecoverySettingsFixtureRepositories[$repoPath]
                if ($arguments.Count -ge 8 -and $arguments[3] -ceq '-X' -and
                    $arguments[4] -ceq 'PATCH') {
                    if ($arguments[6] -cne '-f' -or $arguments[7] -cnotmatch '^description=') {
                        throw 'Fixture supports only a test-owned description PATCH.'
                    }
                    $target.description = [string] $arguments[7].Substring('description='.Length)
                    $script:RecoverySettingsFixtureRequests.Add("PATCH:$($target.description)")
                }
                else { $script:RecoverySettingsFixtureRequests.Add("GET:$repoPath") }
                [pscustomobject] @{
                    ExitCode = 0
                    Output = @(([pscustomobject] $target | ConvertTo-Json -Compress))
                    ErrorText = ''
                }
            }
        } $destination $archive

        try {
            $fixtureExecutor = & $module { (Get-Item Function:Invoke-CgrNativeCommand).ScriptBlock.ToString() }
            $probeArgs = @{
                ExpectedDestination = $destination
                ExpectedArchive = $archive
                ExpectedOriginalRepositoryId = '12345'
                ApprovedDescription = $approved
                DriftDescription = $drift
                HostName = 'github.com'
                Action = {
                    $patch = & $module {
                        param($name, $description)
                        Invoke-CgrNativeCommand -FilePath 'gh' -ArgumentList @(
                            'api', '--hostname', 'github.com', '-X', 'PATCH',
                            "repos/$name", '-f', "description=$description"
                        )
                    } $destination $approved
                    $readback = & $module {
                        param($name)
                        Invoke-CgrNativeCommand -FilePath 'gh' -ArgumentList @(
                            'api', '--hostname', 'github.com', "repos/$name"
                        )
                    } $destination
                    $actual = (@($readback.Output) -join [Environment]::NewLine) | ConvertFrom-Json
                    [pscustomobject] @{
                        ProductionPatchExitCode = $patch.ExitCode
                        ActualDescription = $actual.description
                    }
                }
            }
            $result = Invoke-RecoveryE2eScopedSettingsReadbackDrift @probeArgs
            $result.OriginalError | Should -BeNullOrEmpty
            $result.ProductionPatchCalls | Should -Be 1
            $result.AuthenticatedDriftWrites | Should -Be 1
            $result.ReplacementRepositoryId | Should -Be '67890'
            @($result.Output).Count | Should -Be 1
            $result.Output[0].ProductionPatchExitCode | Should -Be 0
            $result.Output[0].ActualDescription | Should -BeExactly $drift
            $requests = & $module { @($script:RecoverySettingsFixtureRequests) }
            @($requests | Where-Object { $_ -like 'PATCH:*' }).Count | Should -Be 2
            @($requests | Where-Object { $_ -ceq "PATCH:$approved" }).Count | Should -Be 1
            @($requests | Where-Object { $_ -ceq "PATCH:$drift" }).Count | Should -Be 1
            (& $module { (Get-Item Function:Invoke-CgrNativeCommand).ScriptBlock.ToString() }) |
                Should -BeExactly $fixtureExecutor
        }
        finally {
            & $module {
                if ($script:RecoverySettingsFixtureOriginalNative) {
                    Set-Item -Path Function:script:Invoke-CgrNativeCommand -Value $script:RecoverySettingsFixtureOriginalNative
                }
                Remove-Variable -Name RecoverySettingsFixtureOriginalNative -Scope Script -ErrorAction SilentlyContinue
                Remove-Variable -Name RecoverySettingsFixtureRequests -Scope Script -ErrorAction SilentlyContinue
                Remove-Variable -Name RecoverySettingsFixtureRepositories -Scope Script -ErrorAction SilentlyContinue
            }
        }
    }

    It 'rejects unsafe or unowned destination names before installation' {
        $badArgs = @{
            ExpectedDestination = 'infoconex/valuable-repository'
            ExpectedArchive = 'infoconex/valuable-archive'
            ExpectedOriginalRepositoryId = '12345'
            ApprovedDescription = 'approved'
            DriftDescription = 'drift'
            HostName = 'github.com'
            Action = { throw 'This action must never run' }
        }
        { Invoke-RecoveryE2eScopedSettingsReadbackDrift @badArgs } |
            Should -Throw '*run-scoped test identities*'
    }
}
