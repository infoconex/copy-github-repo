$script:ResolveCgrGitHubApiReadResponse = {
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

function Invoke-CgrGitHubApiReadRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $ArgumentList,

        [ValidateRange(1, 10)]
        [int] $MaxAttempts = 3,

        [ValidateRange(1, 60000)]
        [int] $BaseDelayMilliseconds = 250,

        [ValidateRange(1, 60000)]
        [int] $MaxDelayMilliseconds = 2000,

        [ValidateRange(1, 300)]
        [int] $MaxServerRetryAfterSeconds = 60
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $result = Invoke-CgrNativeCommand -FilePath 'gh' -ArgumentList $ArgumentList
        $result | Add-Member -NotePropertyName RetryAttempts -NotePropertyValue $attempt -Force
        $result | Add-Member -NotePropertyName RetryDiagnostic -NotePropertyValue $null -Force

        if ($result.ExitCode -eq 0) {
            return $result
        }

        $errorText = [string] $result.ErrorText
        $retryable = $errorText -match '(?i)(HTTP\s+(429|502|503|504)\b|secondary rate limit|rate limit exceeded|abuse detection|connection (was )?reset|connection timed out|temporary failure|TLS handshake timeout|server disconnected|unexpected EOF)'
        if (-not $retryable -or $attempt -ge $MaxAttempts) {
            return $result
        }

        $retryAfterSeconds = $null
        $retryAfterMatch = [regex]::Match(
            $errorText,
            '(?im)(?:Retry-After\s*[:=]\s*|retry after\s+)(?<seconds>\d+)\s*(?:seconds?)?'
        )
        if ($retryAfterMatch.Success) {
            $retryAfterSeconds = [int] $retryAfterMatch.Groups['seconds'].Value
        }

        if ($null -ne $retryAfterSeconds) {
            if ($retryAfterSeconds -gt $MaxServerRetryAfterSeconds) {
                $result.RetryDiagnostic = "Automatic retry was not attempted because the server requested a $retryAfterSeconds second delay, exceeding the $MaxServerRetryAfterSeconds second automatic-wait limit."
                return $result
            }

            $delayMilliseconds = $retryAfterSeconds * 1000
        }
        else {
            $exponentialDelay = [Math]::Min(
                $MaxDelayMilliseconds,
                $BaseDelayMilliseconds * [Math]::Pow(2, $attempt - 1)
            )
            $jitterCeiling = [Math]::Max(1, [int] [Math]::Ceiling($BaseDelayMilliseconds / 4))
            $jitterMilliseconds = Get-Random -Minimum 0 -Maximum ($jitterCeiling + 1)
            $delayMilliseconds = [int] [Math]::Min(
                $MaxDelayMilliseconds,
                $exponentialDelay + $jitterMilliseconds
            )
        }

        Start-Sleep -Milliseconds $delayMilliseconds
    }
}
