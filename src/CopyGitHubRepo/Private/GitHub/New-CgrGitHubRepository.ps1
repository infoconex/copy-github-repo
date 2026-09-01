function New-CgrGitHubRepository {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'The public Copy-GitHubRepository command performs the ShouldProcess check before calling this GitHub CLI boundary.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
        [string] $Repository,

        [Parameter(Mandatory)]
        [ValidateSet('public', 'private', 'internal')]
        [string] $Visibility,

        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com'
    )

    $normalizedRepository = ConvertTo-CgrRepositoryName -Repository $Repository
    $visibilityArgument = switch ($Visibility) {
        'public' { '--public' }
        'private' { '--private' }
        'internal' { '--internal' }
    }

    Send-CgrActivityEvent -Name 'CreateRepository' -State Started -Message "Create repository '$normalizedRepository'"
    $result = Invoke-CgrNativeCommand `
        -FilePath 'gh' `
        -ArgumentList @('repo', 'create', $normalizedRepository, $visibilityArgument)

    if ($result.ExitCode -ne 0) {
        Send-CgrActivityEvent -Name 'CreateRepository' -State Failed -Message "Create repository '$normalizedRepository'"
        $message = "GitHub CLI failed to create repository '$normalizedRepository'. $($result.ErrorText)"
        $exception = [System.InvalidOperationException]::new($message.Trim())
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'GitHubRepositoryCreateFailed',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $normalizedRepository
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    try {
        $createdRepository = Get-CgrRepository -Repository $normalizedRepository -HostName $HostName
        $guardRequested = Get-Variable -Name CgrPagesWorkflowActivationGuardRequested -Scope Script -ErrorAction SilentlyContinue
        if ($guardRequested -and [bool] $guardRequested.Value) {
            Set-CgrPagesWorkflowActivationGuard -Repository $normalizedRepository -Guarded $true -HostName $HostName | Out-Null
        }
    }
    catch {
        Send-CgrActivityEvent -Name 'CreateRepository' -State Failed -Message "Create repository '$normalizedRepository'"
        throw
    }

    Send-CgrActivityEvent -Name 'CreateRepository' -State Completed -Message "Create repository '$normalizedRepository'"
    return $createdRepository
}
