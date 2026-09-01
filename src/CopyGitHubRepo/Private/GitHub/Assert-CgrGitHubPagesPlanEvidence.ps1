function Assert-CgrGitHubPagesPlanEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $Plan,
        [Parameter(Mandatory)] [psobject] $SourceRepository,
        [ValidateNotNullOrEmpty()] [string] $HostName = 'github.com'
    )

    $pages = Get-CgrObjectProperty -InputObject $Plan -Name 'Pages'
    if ($null -eq $pages) {
        $exception = [System.InvalidOperationException]::new('Pages restoration was requested, but the approved migration plan does not contain immutable Pages evidence.')
        throw [System.Management.Automation.ErrorRecord]::new($exception, 'ApprovedPagesEvidenceMissing', [System.Management.Automation.ErrorCategory]::InvalidData, $Plan)
    }

    $representability = Get-CgrObjectProperty -InputObject $pages -Name 'Representability'
    $isRepresentable = if ($representability) { Get-CgrObjectProperty -InputObject $representability -Name 'IsRepresentable' } else { $true }
    if ($null -eq $isRepresentable -and $representability) {
        $isRepresentable = Get-CgrObjectProperty -InputObject $representability -Name 'Representable'
    }
    if ($representability -and -not [bool] $isRepresentable) {
        $reason = Get-CgrObjectProperty -InputObject $representability -Name 'Reason'
        $exception = [System.InvalidOperationException]::new("The reviewed Pages configuration is not representable at the destination. $reason")
        throw [System.Management.Automation.ErrorRecord]::new($exception, 'ApprovedPagesConfigurationNotRepresentable', [System.Management.Automation.ErrorCategory]::InvalidData, $pages)
    }

    $current = Get-CgrGitHubPagesPlanEvidence -Repository $SourceRepository -ContentMode $Plan.ContentMode -SourceState $Plan.SourceState -HostName $HostName
    $reviewedDrift = Get-CgrObjectProperty -InputObject $pages -Name 'DriftEvidence'
    $currentDrift = Get-CgrObjectProperty -InputObject $current -Name 'DriftEvidence'
    if ($null -eq $reviewedDrift -or $null -eq $currentDrift -or
        -not (Test-CgrGitHubPagesDriftEvidenceMatch -ReviewedEvidence $reviewedDrift -CurrentEvidence $currentDrift)) {
        $exception = [System.InvalidOperationException]::new("GitHub Pages configuration for '$($SourceRepository.FullName)' changed after planning. No destination Pages mutation was performed.")
        throw [System.Management.Automation.ErrorRecord]::new($exception, 'PagesStateChangedSincePlanning', [System.Management.Automation.ErrorCategory]::InvalidData, $SourceRepository.FullName)
    }

    return $pages
}
