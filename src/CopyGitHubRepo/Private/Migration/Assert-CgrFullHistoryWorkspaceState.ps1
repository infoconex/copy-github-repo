function Assert-CgrFullHistoryWorkspaceState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RepositoryPath,

        [Parameter(Mandatory)]
        [psobject] $ApprovedSourceState,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RepositoryName
    )

    $refsResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $RepositoryPath, 'for-each-ref', '--format=%(refname) %(objectname)', 'refs/heads', 'refs/tags')
    $commitCountResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $RepositoryPath, 'rev-list', '--all', '--count')
    $branchesResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $RepositoryPath, 'for-each-ref', '--format=%(refname)', 'refs/heads')
    foreach ($command in @($refsResult, $commitCountResult, $branchesResult)) {
        if ($command.ExitCode -ne 0) {
            $message = "Git failed while checking the cloned FullHistory source state for '$RepositoryName'. $($command.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'FullHistoryApprovedStateReadFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $RepositoryName)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }

    $branches = @($branchesResult.Output | ForEach-Object { $_.ToString() } | Sort-Object)
    $branchTrees = [System.Collections.Generic.List[string]]::new()
    foreach ($branch in $branches) {
        $treeResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $RepositoryPath, 'rev-parse', "$branch^{tree}")
        if ($treeResult.ExitCode -ne 0) {
            $message = "Git failed to read branch-tip tree '$branch' while checking the approved FullHistory source state."
            $exception = [System.InvalidOperationException]::new($message)
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'FullHistoryApprovedStateBranchTreeReadFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $branch)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
        $branchTrees.Add("$branch $([string] @($treeResult.Output)[0])")
    }

    $actualRefs = @($refsResult.Output | ForEach-Object { $_.ToString() } | Sort-Object)
    $actualCommitCount = [int] ([string] @($commitCountResult.Output)[0])
    $expectedRefs = @(Get-CgrObjectProperty -InputObject $ApprovedSourceState -Name 'Refs') | Sort-Object
    $expectedBranchTrees = @(Get-CgrObjectProperty -InputObject $ApprovedSourceState -Name 'BranchTrees') | Sort-Object
    $stateMatches = ($actualRefs -join "`n") -eq ($expectedRefs -join "`n") -and
    $actualCommitCount -eq (Get-CgrObjectProperty -InputObject $ApprovedSourceState -Name 'ReachableCommitCount') -and
    (($branchTrees.ToArray() | Sort-Object) -join "`n") -eq ($expectedBranchTrees -join "`n")

    if (-not $stateMatches) {
        $message = "Source repository '$RepositoryName' no longer matches the approved FullHistory source state. Nothing was published. Recreate and review the repository copy plan."
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'SourceStateChangedSincePlanning', [System.Management.Automation.ErrorCategory]::InvalidResult, $RepositoryName)
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    [pscustomobject] @{
        Refs = $actualRefs
        ReachableCommitCount = $actualCommitCount
        BranchTrees = @($branchTrees.ToArray() | Sort-Object)
    }
}
