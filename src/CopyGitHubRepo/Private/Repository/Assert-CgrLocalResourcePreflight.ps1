function Assert-CgrLocalResourcePreflight {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Plan,

        [Nullable[long]] $AvailableBytes
    )

    $sourceState = Get-CgrObjectProperty -InputObject $Plan -Name 'SourceState'
    $observedBytesValue = Get-CgrObjectProperty -InputObject $sourceState -Name 'PlanningWorkspaceBytes'
    $observedBytes = if ($null -eq $observedBytesValue) { 0L } else { [long] $observedBytesValue }

    if (-not $PSBoundParameters.ContainsKey('AvailableBytes')) {
        try {
            $tempPath = [System.IO.Path]::GetTempPath()
            $root = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($tempPath))
            if ([string]::IsNullOrWhiteSpace($root)) {
                throw 'Temporary storage volume could not be resolved.'
            }
            $AvailableBytes = [System.IO.DriveInfo]::new($root).AvailableFreeSpace
        }
        catch {
            Write-Warning 'Local temporary-storage free space could not be determined. The repository copy can continue, but disk-capacity preflight is advisory/unknown for this run.'
            return [pscustomobject] @{
                PSTypeName = 'CopyGitHubRepo.LocalResourcePreflight'
                Status = 'Unknown'
                ObservedPlanningWorkspaceBytes = $observedBytes
                AvailableBytes = $null
                AdvisoryHeadroomBytes = if ($observedBytes -gt 0) { [long] [Math]::Min([decimal] [long]::MaxValue, ([decimal] $observedBytes * 2)) } else { 0L }
            }
        }
    }

    $available = [long] $AvailableBytes
    if ($observedBytes -gt 0 -and $available -lt $observedBytes) {
        $message = "Insufficient free space is available on the local temporary-storage volume. The approved source-state planning workspace used $observedBytes bytes, but only $available bytes are currently free. No GitHub mutation was started. Free temporary storage and retry."
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'LocalTempSpaceInsufficient',
            [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
            'temporary storage'
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $advisoryHeadroom = if ($observedBytes -gt 0) {
        [long] [Math]::Min([decimal] [long]::MaxValue, ([decimal] $observedBytes * 2))
    }
    else {
        0L
    }

    $status = 'Passed'
    if ($observedBytes -le 0) {
        $status = 'UnknownRequirement'
        Write-Warning 'The approved source state does not contain an observed planning-workspace size. Exact temporary-storage demand cannot be predicted; continue only with adequate free space.'
    }
    elseif ($available -lt $advisoryHeadroom) {
        $status = 'Advisory'
        Write-Warning "Local temporary storage has $available free bytes. This exceeds the observed planning-workspace lower bound of $observedBytes bytes but is below the advisory 2x headroom of $advisoryHeadroom bytes. The copy may still succeed, but Snapshot/LFS and other Git operations can temporarily amplify disk use."
    }

    return [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.LocalResourcePreflight'
        Status = $status
        ObservedPlanningWorkspaceBytes = $observedBytes
        AvailableBytes = $available
        AdvisoryHeadroomBytes = $advisoryHeadroom
    }
}
