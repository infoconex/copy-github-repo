function Invoke-CgrNativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $FilePath,

        [string[]] $ArgumentList = @(),

        [string[]] $PrefixArgumentList = @(),

        [hashtable] $Environment = @{},

        [ValidateScript({
                $_ -eq [System.Threading.Timeout]::InfiniteTimeSpan -or $_ -gt [TimeSpan]::Zero
            })]
        [TimeSpan] $Timeout = [System.Threading.Timeout]::InfiniteTimeSpan,

        [System.Threading.CancellationToken] $CancellationToken = [System.Threading.CancellationToken]::None
    )

    $effectiveArgumentList = @($PrefixArgumentList) + @($ArgumentList)
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    foreach ($argument in $effectiveArgumentList) {
        [void] $startInfo.ArgumentList.Add($argument)
    }

    foreach ($name in $Environment.Keys) {
        if ($null -eq $Environment[$name]) {
            [void] $startInfo.Environment.Remove($name)
            continue
        }

        $startInfo.Environment[$name] = [string] $Environment[$name]
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $timeoutCancellationSource = $null
    $linkedCancellationSource = $null

    try {
        if (-not $process.Start()) {
            throw "Failed to start native command '$FilePath'."
        }

        $standardOutputTask = $process.StandardOutput.ReadToEndAsync()
        $standardErrorTask = $process.StandardError.ReadToEndAsync()
        $terminationKind = $null
        $cleanupDiagnostic = $null

        try {
            $hasFiniteTimeout = $Timeout -ne [System.Threading.Timeout]::InfiniteTimeSpan
            if (-not $hasFiniteTimeout -and -not $CancellationToken.CanBeCanceled) {
                $process.WaitForExit()
            }
            else {
                $effectiveCancellationToken = $CancellationToken

                if ($hasFiniteTimeout) {
                    $timeoutCancellationSource = [System.Threading.CancellationTokenSource]::new($Timeout)
                    if ($CancellationToken.CanBeCanceled) {
                        $linkedCancellationSource = [System.Threading.CancellationTokenSource]::CreateLinkedTokenSource(
                            $CancellationToken,
                            $timeoutCancellationSource.Token
                        )
                        $effectiveCancellationToken = $linkedCancellationSource.Token
                    }
                    else {
                        $effectiveCancellationToken = $timeoutCancellationSource.Token
                    }
                }

                $process.WaitForExitAsync($effectiveCancellationToken).GetAwaiter().GetResult()
            }
        }
        catch [System.OperationCanceledException] {
            if ($CancellationToken.IsCancellationRequested) {
                $terminationKind = 'Cancelled'
            }
            else {
                $terminationKind = 'TimedOut'
            }

            try {
                if (-not $process.HasExited) {
                    $process.Kill($true)
                    $process.WaitForExit()
                }
            }
            catch {
                $cleanupDiagnostic = $_.Exception.Message
            }
        }

        $standardOutputText = $standardOutputTask.GetAwaiter().GetResult()
        $standardErrorText = $standardErrorTask.GetAwaiter().GetResult()
        $standardOutput = [System.Collections.Generic.List[string]]::new()
        $standardError = [System.Collections.Generic.List[string]]::new()

        $standardOutputReader = [System.IO.StringReader]::new($standardOutputText)
        try {
            while ($null -ne ($line = $standardOutputReader.ReadLine())) {
                $standardOutput.Add($line)
            }
        }
        finally {
            $standardOutputReader.Dispose()
        }

        $standardErrorReader = [System.IO.StringReader]::new($standardErrorText)
        try {
            while ($null -ne ($line = $standardErrorReader.ReadLine())) {
                $standardError.Add($line)
            }
        }
        finally {
            $standardErrorReader.Dispose()
        }

        $standardOutputLines = @($standardOutput)
        $standardErrorLines = @($standardError)

        if ($null -ne $terminationKind) {
            if ($terminationKind -eq 'Cancelled') {
                $message = "Native command '$FilePath' was cancelled."
                $errorId = 'NativeCommandCancelled'
            }
            else {
                $message = "Native command '$FilePath' timed out after $($Timeout.TotalSeconds) second(s)."
                $errorId = 'NativeCommandTimedOut'
            }

            $exception = [System.OperationCanceledException]::new($message)
            $exception.Data['FilePath'] = $FilePath
            $exception.Data['StandardOutput'] = $standardOutputLines
            $exception.Data['StandardError'] = $standardErrorLines
            if ($terminationKind -eq 'TimedOut') {
                $exception.Data['Timeout'] = $Timeout
            }
            if (-not [string]::IsNullOrWhiteSpace($cleanupDiagnostic)) {
                $exception.Data['ProcessCleanupDiagnostic'] = $cleanupDiagnostic
            }

            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                $errorId,
                [System.Management.Automation.ErrorCategory]::OperationTimeout,
                $FilePath
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.NativeCommandResult'
            FilePath = $FilePath
            Arguments = $effectiveArgumentList
            ExitCode = $process.ExitCode
            StandardOutput = $standardOutputLines
            StandardError = $standardErrorLines
            Output = $standardOutputLines
            ErrorText = ($standardErrorLines | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        }
    }
    finally {
        if ($null -ne $linkedCancellationSource) {
            $linkedCancellationSource.Dispose()
        }
        if ($null -ne $timeoutCancellationSource) {
            $timeoutCancellationSource.Dispose()
        }
        $process.Dispose()
    }
}
