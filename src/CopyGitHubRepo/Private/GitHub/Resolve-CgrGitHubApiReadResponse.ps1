function Resolve-CgrGitHubApiReadResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Result,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [switch] $AllowNotFound
    )

    if ($Result.ExitCode -ne 0) {
        $errorText = Protect-CgrDiagnosticText -Text ([string] $Result.ErrorText)
        if ($AllowNotFound -and $errorText -match '404|Not Found') {
            return [pscustomobject] @{
                Status = 'NotFound'
                Data = $null
                ErrorRecord = $null
            }
        }

        $attemptText = if ($Result.RetryAttempts -gt 1) {
            " after $($Result.RetryAttempts) attempts"
        }
        else {
            ''
        }
        $retryDiagnostic = if ([string]::IsNullOrWhiteSpace([string] $Result.RetryDiagnostic)) {
            ''
        }
        else {
            ' ' + (Protect-CgrDiagnosticText -Text ([string] $Result.RetryDiagnostic))
        }
        $message = "GitHub CLI API request failed for '$Path'$attemptText. $errorText$retryDiagnostic"
        $exception = [System.InvalidOperationException]::new($message.Trim())
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'GitHubApiRequestFailed',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $Path
        )

        return [pscustomobject] @{
            Status = 'Error'
            Data = $null
            ErrorRecord = $errorRecord
        }
    }

    $json = ($Result.Output | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($json)) {
        return [pscustomobject] @{
            Status = 'Empty'
            Data = $null
            ErrorRecord = $null
        }
    }

    try {
        $data = $json | ConvertFrom-Json -Depth 100 -ErrorAction Stop
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

        return [pscustomobject] @{
            Status = 'Error'
            Data = $null
            ErrorRecord = $errorRecord
        }
    }

    return [pscustomobject] @{
        Status = 'Success'
        Data = $data
        ErrorRecord = $null
    }
}
