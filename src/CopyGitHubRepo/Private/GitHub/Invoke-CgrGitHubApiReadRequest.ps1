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
