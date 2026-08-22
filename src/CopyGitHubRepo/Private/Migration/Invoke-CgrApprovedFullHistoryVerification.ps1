function Invoke-CgrApprovedFullHistoryVerification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $SourceRepository,

        [Parameter(Mandatory)]
        [psobject] $DestinationRepository,

        [Parameter(Mandatory)]
        [psobject] $ApprovedSourceState
    )

    $workspacePath = Join-Path ([System.IO.Path]::GetTempPath()) "copy-github-repo-fullhistory-approved-verify-$([guid]::NewGuid().ToString('N'))"
    $destinationPath = Join-Path $workspacePath 'destination.git'
    try {
        New-Item -Path $workspacePath -ItemType Directory -Force | Out-Null
        $cloneResult = Invoke-CgrGitCommand -HostName $DestinationRepository.HostName -ArgumentList @('clone', '--bare', $DestinationRepository.CloneUrl, $destinationPath)
        if ($cloneResult.ExitCode -ne 0) {
            $message = "Git failed to clone destination '$($DestinationRepository.FullName)' for FullHistory verification. $($cloneResult.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'FullHistoryVerificationDestinationCloneFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $DestinationRepository.FullName)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $lfsResult = Invoke-CgrGitCommand -HostName $DestinationRepository.HostName -ArgumentList @('-C', $destinationPath, 'lfs', 'fetch', '--all', 'origin')
        if ($lfsResult.ExitCode -ne 0) {
            $message = "Git LFS failed to verify reachable objects in '$($DestinationRepository.FullName)'. $($lfsResult.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'FullHistoryVerificationDestinationGitLfsFetchFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $DestinationRepository.FullName)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $refsResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $destinationPath, 'for-each-ref', '--format=%(refname) %(objectname)', 'refs/heads', 'refs/tags')
        $commitCountResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $destinationPath, 'rev-list', '--all', '--count')
        $branchesResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $destinationPath, 'for-each-ref', '--format=%(refname)', 'refs/heads')
        foreach ($command in @($refsResult, $commitCountResult, $branchesResult)) {
            if ($command.ExitCode -ne 0) {
                $message = "Git failed while verifying FullHistory destination '$($DestinationRepository.FullName)'. $($command.ErrorText)"
                $exception = [System.InvalidOperationException]::new($message.Trim())
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'FullHistoryVerificationDestinationReadFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $DestinationRepository.FullName)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
        }

        $branches = @($branchesResult.Output | ForEach-Object { $_.ToString() } | Sort-Object)
        $destinationBranchTrees = [System.Collections.Generic.List[string]]::new()
        foreach ($branch in $branches) {
            $treeResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $destinationPath, 'rev-parse', "$branch^{tree}")
            if ($treeResult.ExitCode -ne 0) {
                $message = "Git failed to read destination branch-tip tree '$branch' during FullHistory verification."
                $exception = [System.InvalidOperationException]::new($message)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'FullHistoryVerificationBranchTreeReadFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $branch)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
            $destinationBranchTrees.Add("$branch $([string] @($treeResult.Output)[0])")
        }

        $expectedRefs = @(Get-CgrObjectProperty -InputObject $ApprovedSourceState -Name 'Refs') | Sort-Object
        $actualRefs = @($refsResult.Output | ForEach-Object { $_.ToString() } | Sort-Object)
        $expectedCommitCount = [int] (Get-CgrObjectProperty -InputObject $ApprovedSourceState -Name 'ReachableCommitCount')
        $actualCommitCount = [int] ([string] @($commitCountResult.Output)[0])
        $expectedBranchTrees = @(Get-CgrObjectProperty -InputObject $ApprovedSourceState -Name 'BranchTrees') | Sort-Object
        $actualBranchTrees = @($destinationBranchTrees.ToArray() | Sort-Object)
        $expectedDefaultBranch = [string] (Get-CgrObjectProperty -InputObject $ApprovedSourceState -Name 'DefaultBranch')

        $checks = @(
            [pscustomobject] @{ Name = 'DestinationExists'; Passed = $true; Expected = $DestinationRepository.FullName; Actual = $DestinationRepository.FullName }
            [pscustomobject] @{ Name = 'DefaultBranchMatches'; Passed = $DestinationRepository.DefaultBranch -eq $expectedDefaultBranch; Expected = $expectedDefaultBranch; Actual = $DestinationRepository.DefaultBranch }
            [pscustomobject] @{ Name = 'BranchAndTagTargetsMatch'; Passed = ($actualRefs -join "`n") -eq ($expectedRefs -join "`n"); Expected = $expectedRefs; Actual = $actualRefs }
            [pscustomobject] @{ Name = 'ReachableCommitCountMatches'; Passed = $actualCommitCount -eq $expectedCommitCount; Expected = $expectedCommitCount; Actual = $actualCommitCount }
            [pscustomobject] @{ Name = 'BranchTipTreesMatch'; Passed = ($actualBranchTrees -join "`n") -eq ($expectedBranchTrees -join "`n"); Expected = $expectedBranchTrees; Actual = $actualBranchTrees }
            [pscustomobject] @{ Name = 'GitLfsObjectsAvailable'; Passed = $true; Expected = [bool] (Get-CgrObjectProperty -InputObject $ApprovedSourceState -Name 'GitLfsObjectsAvailable'); Actual = $true }
        )

        [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.MigrationVerificationResult'
            SchemaVersion = 1
            ContentMode = 'FullHistory'
            SourceRepository = $SourceRepository.FullName
            ApprovedSourceState = $ApprovedSourceState
            DestinationRepository = $DestinationRepository.FullName
            BranchName = $expectedDefaultBranch
            SourceRefCount = $expectedRefs.Count
            DestinationRefCount = $actualRefs.Count
            SourceReachableCommitCount = $expectedCommitCount
            DestinationReachableCommitCount = $actualCommitCount
            IsSuccessful = -not ($checks | Where-Object { -not $_.Passed })
            Checks = $checks
        }
    }
    finally {
        if (Test-Path -LiteralPath $workspacePath) {
            Remove-Item -LiteralPath $workspacePath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
