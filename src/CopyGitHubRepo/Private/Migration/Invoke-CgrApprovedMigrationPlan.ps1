function Invoke-CgrApprovedMigrationPlan {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'ShouldProcess and exact replacement confirmation are enforced by the public command or wizard before this approved-plan execution boundary.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Plan,

        [Parameter(Mandatory)]
        [psobject] $SourceRepository,

        [string] $SameNameConfirmation,

        [string] $ExistingDestinationConfirmation,

        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com',

        [string] $ReportPath
    )

    $sourceState = Get-CgrObjectProperty -InputObject $Plan -Name 'SourceState'
    if ($null -eq $sourceState) {
        $message = 'The approved repository copy plan does not contain immutable source-state evidence. Recreate and review the plan before execution.'
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'ApprovedSourceStateMissing',
            [System.Management.Automation.ErrorCategory]::InvalidData,
            $Plan.SourceRepository
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    Assert-CgrApprovedSourceState -Repository $SourceRepository -SourceState $sourceState | Out-Null
    Assert-CgrLocalResourcePreflight -Plan $Plan | Out-Null

    $previousGuardVariable = Get-Variable -Name CgrPagesWorkflowActivationGuardRequested -Scope Script -ErrorAction SilentlyContinue
    $script:CgrPagesWorkflowActivationGuardRequested = [bool] (Get-CgrObjectProperty -InputObject $Plan -Name 'RestorePages')

    try {
        if ($Plan.Mode -eq 'SameNameReplacement') {
            Assert-CgrSameNameReplacementConfirmation -Plan $Plan -Confirmation $SameNameConfirmation | Out-Null
            if ($Plan.ContentMode -eq 'FullHistory') {
                return Invoke-CgrSameNameFullHistoryReplacement -Plan $Plan -SourceRepository $SourceRepository -HostName $HostName -ReportPath $ReportPath
            }

            return Invoke-CgrSameNameSnapshotReplacement -Plan $Plan -SourceRepository $SourceRepository -HostName $HostName -ReportPath $ReportPath
        }

        if ($Plan.Mode -eq 'ExistingDestinationReplacement') {
            Assert-CgrExistingDestinationReplacementConfirmation -Plan $Plan -Confirmation $ExistingDestinationConfirmation | Out-Null
            $existingDestination = Get-CgrRepository -Repository $Plan.DestinationRepository -HostName $HostName
            return Invoke-CgrExistingDestinationReplacement `
                -Plan $Plan `
                -SourceRepository $SourceRepository `
                -ExistingDestinationRepository $existingDestination `
                -HostName $HostName `
                -ReportPath $ReportPath
        }

        $destination = New-CgrGitHubRepository -Repository $Plan.DestinationRepository -Visibility $Plan.DestinationVisibility -HostName $HostName
        if ($Plan.ContentMode -eq 'FullHistory') {
            return Invoke-CgrNewDestinationFullHistory -Plan $Plan -SourceRepository $SourceRepository -DestinationRepository $destination -HostName $HostName -ReportPath $ReportPath
        }

        return Invoke-CgrNewDestinationSnapshot -Plan $Plan -SourceRepository $SourceRepository -DestinationRepository $destination -HostName $HostName -ReportPath $ReportPath
    }
    finally {
        if ($previousGuardVariable) {
            $script:CgrPagesWorkflowActivationGuardRequested = $previousGuardVariable.Value
        }
        else {
            Remove-Variable -Name CgrPagesWorkflowActivationGuardRequested -Scope Script -ErrorAction SilentlyContinue
        }
    }
}
