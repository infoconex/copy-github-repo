function Enable-CgrPagesWorkflowActivationAfterRestore {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This releases the temporary Pages-specific guard after the public command mutation gate and successful Pages verification.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $DestinationRepository,
        [ValidateNotNullOrEmpty()] [string] $HostName = 'github.com'
    )

    Invoke-CgrGitHubApiMutation -Method PUT -Path "/repos/$($DestinationRepository.FullName)/actions/permissions" -Body @{ enabled = $true } -HostName $HostName | Out-Null
    $permissions = Get-CgrGitHubApi -Path "repos/$($DestinationRepository.FullName)/actions/permissions" -HostName $HostName
    if (-not [bool] (Get-CgrObjectProperty -InputObject $permissions -Name 'enabled')) {
        $exception = [System.InvalidOperationException]::new("The temporary Pages workflow activation guard could not be released for '$($DestinationRepository.FullName)'.")
        throw [System.Management.Automation.ErrorRecord]::new($exception, 'PagesWorkflowActivationGuardReleaseFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $DestinationRepository.FullName)
    }
}
