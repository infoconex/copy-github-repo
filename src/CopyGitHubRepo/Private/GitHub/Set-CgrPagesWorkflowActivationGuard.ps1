function Set-CgrPagesWorkflowActivationGuard {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'The public command already approved migration mutation before this internal safety boundary.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Repository,
        [Parameter(Mandatory)] [bool] $Guarded,
        [string] $HostName = 'github.com'
    )

    $normalizedRepository = ConvertTo-CgrRepositoryName -Repository $Repository
    $path = "/repos/$normalizedRepository/actions/permissions"
    $expectedActionsEnabled = -not $Guarded

    Invoke-CgrGitHubApiMutation -Method PUT -Path $path -Body @{ enabled = $expectedActionsEnabled } -HostName $HostName | Out-Null
    $permissions = Get-CgrGitHubApi -Path $path -HostName $HostName
    $actualActionsEnabled = [bool] (Get-CgrObjectProperty -InputObject $permissions -Name 'enabled')

    if ($actualActionsEnabled -ne $expectedActionsEnabled) {
        $message = "The GitHub Pages workflow activation guard could not be verified for '$normalizedRepository'. Migration cannot safely continue."
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'PagesWorkflowActivationGuardVerificationFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $normalizedRepository)
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    [pscustomobject] @{ Repository = $normalizedRepository; Guarded = $Guarded; ActionsEnabled = $actualActionsEnabled; Verified = $true }
}
