function Get-CgrGitHubApiOptional {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com'
    )

    $result = Invoke-CgrGitHubApiReadRequest `
        -ArgumentList @('api', '--hostname', $HostName, $Path)

    if ($result.ExitCode -ne 0) {
        $errorText = Protect-CgrDiagnosticText -Text ([string] $result.ErrorText)
        if ($errorText -match '404|Not Found') {
            return $null
        }

        $attemptText = if ($result.RetryAttempts -gt 1) {
            " after $($result.RetryAttempts) attempts"
        }
        else {
            ''
        }
        $retryDiagnostic = if ([string]::IsNullOrWhiteSpace([string] $result.RetryDiagnostic)) {
            ''
        }
        else {
            ' ' + (Protect-CgrDiagnosticText -Text ([string] $result.RetryDiagnostic))
        }
        $message = "GitHub CLI API request failed for '$Path'$attemptText. $errorText$retryDiagnostic"
        $exception = [System.InvalidOperationException]::new($message.Trim())
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'GitHubApiRequestFailed',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $Path
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $json = ($result.Output | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($json)) {
        return $null
    }

    try {
        return $json | ConvertFrom-Json -Depth 100 -ErrorAction Stop
    }
    catch {
        $diagnostic = Protect-CgrDiagnosticText -Text $_.Exception.Message
        $message = "GitHub CLI API response for '$Path' was not valid JSON. $diagnostic"
        $exception = [System.IO.InvalidDataException]::new($message.Trim(), $_.Exception)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'GitHubApiResponseInvalid',
            [System.Management.Automation.ErrorCategory]::InvalidData,
            $Path
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
}
