function Invoke-CgrGitHubApiMutation {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Callers are orchestration helpers reached only after the public command ShouldProcess gate.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('POST', 'PUT', 'PATCH', 'DELETE')]
        [string] $Method,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [AllowNull()]
        [psobject] $Body,

        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com'
    )

    $arguments = [System.Collections.Generic.List[string]]::new()
    $arguments.Add('api')
    $arguments.Add('--hostname')
    $arguments.Add($HostName)
    $arguments.Add('-X')
    $arguments.Add($Method)
    $arguments.Add($Path)

    $inputPath = $null
    try {
        if ($null -ne $Body) {
            $inputPath = Join-Path ([System.IO.Path]::GetTempPath()) "copy-github-repo-api-$([guid]::NewGuid().ToString('N')).json"
            $Body |
                ConvertTo-Json -Depth 100 -Compress |
                Set-Content -LiteralPath $inputPath -Encoding utf8NoBOM
            $arguments.Add('--input')
            $arguments.Add($inputPath)
        }

        $result = Invoke-CgrNativeCommand -FilePath 'gh' -ArgumentList $arguments.ToArray()
        if ($result.ExitCode -ne 0) {
            $errorText = Protect-CgrDiagnosticText -Text ([string] $result.ErrorText)
            $message = "GitHub CLI API $Method request failed for '$Path'. $errorText"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'GitHubApiMutationFailed',
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
            $message = "GitHub CLI API $Method response for '$Path' was not valid JSON. $diagnostic"
            $exception = [System.IO.InvalidDataException]::new($message.Trim(), $_.Exception)
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'GitHubApiMutationResponseInvalid',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $Path
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }
    finally {
        if ($inputPath) {
            Remove-Item -LiteralPath $inputPath -Force -ErrorAction SilentlyContinue
        }
    }
}
