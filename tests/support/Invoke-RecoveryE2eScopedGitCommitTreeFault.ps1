function Invoke-RecoveryE2eScopedGitCommitTreeFault {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock] $Action
    )

    # Test-only interception in the imported module. No production function
    # or process-wide environment variable is permanently changed.
    $module = Get-Module CopyGitHubRepo -ErrorAction Stop
    if (-not $module) {
        throw 'Scoped Git fault requires the loaded CopyGitHubRepo module.'
    }

    $capturedError = $null
    $actionOutput = @()
    $commitTreeCalls = 0
    try {
        & $module {
            $script:RecoveryE2eOriginalNativeCommand = (Get-Item Function:Invoke-CgrNativeCommand -ErrorAction Stop).ScriptBlock
            $script:RecoveryE2eCommitTreeCalls = 0
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
                $isCommitTree = $FilePath -eq 'git' -and @($ArgumentList) -contains 'commit-tree'
                if ($isCommitTree) {
                    $script:RecoveryE2eCommitTreeCalls++
                    if ($script:RecoveryE2eCommitTreeCalls -ne 1) {
                        throw 'Copy-fault probe encountered more than one native Git commit-tree invocation.'
                    }
                    $nativeArgs = @{}
                    foreach ($name in $PSBoundParameters.Keys) { $nativeArgs[$name] = $PSBoundParameters[$name] }
                    $scopedEnvironment = @{}
                    foreach ($name in $Environment.Keys) { $scopedEnvironment[$name] = $Environment[$name] }
                    $scopedEnvironment['GIT_AUTHOR_DATE'] = 'not-a-valid-date'
                    $scopedEnvironment['GIT_COMMITTER_DATE'] = 'not-a-valid-date'
                    $nativeArgs['Environment'] = $scopedEnvironment
                    return & $script:RecoveryE2eOriginalNativeCommand @nativeArgs
                }
                return & $script:RecoveryE2eOriginalNativeCommand @PSBoundParameters
            }
        }
        try {
            $actionOutput = @(& $Action)
        }
        catch {
            $capturedError = $_
        }
    }
    finally {
        $commitTreeCalls = & $module {
            try { $script:RecoveryE2eCommitTreeCalls }
            finally {
                if ($script:RecoveryE2eOriginalNativeCommand) {
                    Set-Item -Path Function:script:Invoke-CgrNativeCommand -Value $script:RecoveryE2eOriginalNativeCommand
                }
                Remove-Variable -Name RecoveryE2eOriginalNativeCommand -Scope Script -ErrorAction SilentlyContinue
                Remove-Variable -Name RecoveryE2eCommitTreeCalls -Scope Script -ErrorAction SilentlyContinue
            }
        }
    }

    [pscustomobject] @{
        OriginalError = $capturedError
        ScopedNativeCommitTreeCalls = $commitTreeCalls
        Output = @($actionOutput)
    }
}
