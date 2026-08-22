function Test-CgrGitHubRepositoryExistence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
        [string] $Repository,

        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com'
    )

    $normalizedRepository = ConvertTo-CgrRepositoryName -Repository $Repository
    $path = "repos/$normalizedRepository"
    $result = Invoke-CgrNativeCommand `
        -FilePath 'gh' `
        -ArgumentList @('api', '--hostname', $HostName, $path)

    if ($result.ExitCode -eq 0) {
        return $true
    }

    if ($result.ErrorText -match '\b404\b|Not Found') {
        return $false
    }

    $message = "GitHub CLI API request failed while checking '$normalizedRepository'. $($result.ErrorText)"
    $exception = [System.InvalidOperationException]::new($message.Trim())
    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
        $exception,
        'GitHubRepositoryExistenceCheckFailed',
        [System.Management.Automation.ErrorCategory]::InvalidOperation,
        $normalizedRepository
    )
    $PSCmdlet.ThrowTerminatingError($errorRecord)
}
