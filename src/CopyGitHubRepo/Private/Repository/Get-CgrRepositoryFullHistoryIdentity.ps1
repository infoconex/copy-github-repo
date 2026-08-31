function Get-CgrRepositoryFullHistoryIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Repository
    )

    $workspacePath = Join-Path ([System.IO.Path]::GetTempPath()) "copy-github-repo-fullhistory-identity-$([guid]::NewGuid().ToString('N'))"
    $repositoryPath = Join-Path $workspacePath 'repository.git'

    try {
        New-Item -Path $workspacePath -ItemType Directory -Force | Out-Null

        $gitLfsVersionResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('lfs', 'version')
        if ($gitLfsVersionResult.ExitCode -ne 0) {
            $message = 'Git LFS is required for FullHistory identity capture so reachable LFS object availability can be verified before same-name mutation.'
            $exception = [System.InvalidOperationException]::new($message)
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'GitLfsRequiredForFullHistoryIdentity',
                [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
                'git-lfs'
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $cloneResult = Invoke-CgrGitCommand `
            -HostName $Repository.HostName `
            -ArgumentList @('clone', '--bare', $Repository.CloneUrl, $repositoryPath)
        if ($cloneResult.ExitCode -ne 0) {
            $message = "Git failed to clone '$($Repository.FullName)' for FullHistory identity capture. $($cloneResult.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'FullHistoryIdentityCloneFailed',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $Repository.FullName
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $lfsFetchResult = Invoke-CgrGitCommand `
            -HostName $Repository.HostName `
            -ArgumentList @('-C', $repositoryPath, 'lfs', 'fetch', '--all', 'origin')
        if ($lfsFetchResult.ExitCode -ne 0) {
            $message = "Git LFS failed to fetch all reachable objects from '$($Repository.FullName)' during FullHistory identity capture. $($lfsFetchResult.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'FullHistoryIdentityGitLfsFetchFailed',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $Repository.FullName
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $refsResult = Invoke-CgrNativeCommand `
            -FilePath 'git' `
            -ArgumentList @('-C', $repositoryPath, 'for-each-ref', '--format=%(refname) %(objectname)', 'refs/heads', 'refs/tags')
        $commitCountResult = Invoke-CgrNativeCommand `
            -FilePath 'git' `
            -ArgumentList @('-C', $repositoryPath, 'rev-list', '--all', '--count')
        $branchesResult = Invoke-CgrNativeCommand `
            -FilePath 'git' `
            -ArgumentList @('-C', $repositoryPath, 'for-each-ref', '--format=%(refname)', 'refs/heads')

        foreach ($command in @($refsResult, $commitCountResult, $branchesResult)) {
            if ($command.ExitCode -ne 0) {
                $message = "Git failed to read FullHistory identity for '$($Repository.FullName)'. $($command.ErrorText)"
                $exception = [System.InvalidOperationException]::new($message.Trim())
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'FullHistoryIdentityReadFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $Repository.FullName
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
        }

        $branches = @($branchesResult.Output | ForEach-Object { $_.ToString() } | Sort-Object)
        $branchTrees = [System.Collections.Generic.List[string]]::new()
        foreach ($branch in $branches) {
            $treeResult = Invoke-CgrNativeCommand `
                -FilePath 'git' `
                -ArgumentList @('-C', $repositoryPath, 'rev-parse', "$branch^{tree}")
            if ($treeResult.ExitCode -ne 0) {
                $message = "Git failed to read branch-tip tree '$branch' for '$($Repository.FullName)'. $($treeResult.ErrorText)"
                $exception = [System.InvalidOperationException]::new($message.Trim())
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'FullHistoryIdentityBranchTreeReadFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $branch
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            $branchTrees.Add("$branch $([string] @($treeResult.Output)[0])")
        }

        $workspaceBytes = (Get-ChildItem -LiteralPath $workspacePath -File -Recurse -Force |
                Measure-Object -Property Length -Sum).Sum
        if ($null -eq $workspaceBytes) { $workspaceBytes = 0 }

        [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.FullHistoryIdentity'
            Repository = $Repository.FullName
            DefaultBranch = $Repository.DefaultBranch
            Refs = @($refsResult.Output | ForEach-Object { $_.ToString() } | Sort-Object)
            ReachableCommitCount = [int] ([string] @($commitCountResult.Output)[0])
            BranchTrees = @($branchTrees.ToArray() | Sort-Object)
            GitLfsObjectsAvailable = $true
            PlanningWorkspaceBytes = [long] $workspaceBytes
        }
    }
    finally {
        if (Test-Path -LiteralPath $workspacePath) {
            Remove-Item -LiteralPath $workspacePath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
