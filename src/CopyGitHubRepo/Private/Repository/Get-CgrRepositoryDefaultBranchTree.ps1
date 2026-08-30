function Get-CgrRepositoryDefaultBranchTree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Repository
    )

    if ([string]::IsNullOrWhiteSpace([string] $Repository.DefaultBranch)) {
        $message = "Repository '$($Repository.FullName)' has no default branch whose tree can be inspected."
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'RepositoryDefaultBranchMissing',
            [System.Management.Automation.ErrorCategory]::InvalidData,
            $Repository.FullName
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) "copy-github-repo-tree-$([guid]::NewGuid().ToString('N'))"
    try {
        $cloneResult = Invoke-CgrGitCommand `
            -HostName $Repository.HostName `
            -ArgumentList @('clone', '--depth', '1', '--branch', $Repository.DefaultBranch, $Repository.CloneUrl, $tempPath) `
            -Environment @{ GIT_LFS_SKIP_SMUDGE = '1' }
        if ($cloneResult.ExitCode -ne 0) {
            $message = "Git failed to clone '$($Repository.FullName)' while reading its default-branch tree. $($cloneResult.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'RepositoryTreeCloneFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $Repository.FullName)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $commitResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $tempPath, 'rev-parse', 'HEAD')
        if ($commitResult.ExitCode -ne 0 -or @($commitResult.Output).Count -eq 0) {
            $message = "Git failed to resolve the default-branch commit for '$($Repository.FullName)'. $($commitResult.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'RepositoryCommitResolutionFailed', [System.Management.Automation.ErrorCategory]::InvalidData, $Repository.FullName)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $treeResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $tempPath, 'rev-parse', 'HEAD^{tree}')
        if ($treeResult.ExitCode -ne 0 -or @($treeResult.Output).Count -eq 0) {
            $message = "Git failed to resolve the default-branch tree for '$($Repository.FullName)'. $($treeResult.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'RepositoryTreeResolutionFailed', [System.Management.Automation.ErrorCategory]::InvalidData, $Repository.FullName)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $pointerFiles = @()
        $gitLfsObjectsAvailable = $true
        $attributeFiles = if ([System.IO.Directory]::Exists($tempPath)) {
            @([System.IO.Directory]::EnumerateFiles($tempPath, '.gitattributes', [System.IO.SearchOption]::AllDirectories) |
                    Where-Object { $_ -notmatch '[\\/]\.git[\\/]' })
        }
        else {
            @()
        }

        $usesGitLfs = $false
        foreach ($attributeFile in $attributeFiles) {
            foreach ($line in [System.IO.File]::ReadAllLines($attributeFile)) {
                $trimmedLine = $line.Trim()
                if (-not $trimmedLine.StartsWith('#') -and $trimmedLine -match '(^|\s)filter=lfs(\s|$)') {
                    $usesGitLfs = $true
                    break
                }
            }
            if ($usesGitLfs) { break }
        }

        if ($usesGitLfs) {
            $gitLfsVersionResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('lfs', 'version')
            if ($gitLfsVersionResult.ExitCode -ne 0) {
                $message = "Source repository '$($Repository.FullName)' uses Git LFS, but Git LFS is unavailable while capturing the approved Snapshot source state."
                $exception = [System.InvalidOperationException]::new($message)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'GitLfsRequiredForSnapshotPlanning', [System.Management.Automation.ErrorCategory]::ResourceUnavailable, 'git-lfs')
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            $listResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $tempPath, 'lfs', 'ls-files', '--name-only')
            if ($listResult.ExitCode -ne 0) {
                $message = "Git LFS failed to enumerate Snapshot pointer files for '$($Repository.FullName)'. $($listResult.ErrorText)"
                $exception = [System.InvalidOperationException]::new($message.Trim())
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'SnapshotPlanningGitLfsEnumerationFailed', [System.Management.Automation.ErrorCategory]::InvalidData, $Repository.FullName)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
            $pointerFiles = @($listResult.Output | ForEach-Object { $_.ToString() } | Sort-Object)

            if ($pointerFiles.Count -gt 0) {
                $fetchResult = Invoke-CgrGitCommand -HostName $Repository.HostName -ArgumentList @('-C', $tempPath, 'lfs', 'fetch', 'origin', $Repository.DefaultBranch)
                $gitLfsObjectsAvailable = $fetchResult.ExitCode -eq 0
                if (-not $gitLfsObjectsAvailable) {
                    $message = "Git LFS objects referenced by the approved Snapshot source state for '$($Repository.FullName)' could not be fetched. $($fetchResult.ErrorText)"
                    $exception = [System.InvalidOperationException]::new($message.Trim())
                    $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'SnapshotPlanningGitLfsFetchFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $Repository.FullName)
                    $PSCmdlet.ThrowTerminatingError($errorRecord)
                }
            }
        }

        $workspaceBytes = 0L
        if ([System.IO.Directory]::Exists($tempPath)) {
            $measuredWorkspaceBytes = (Get-ChildItem -LiteralPath $tempPath -File -Recurse -Force |
                    Measure-Object -Property Length -Sum).Sum
            if ($null -ne $measuredWorkspaceBytes) {
                $workspaceBytes = [long] $measuredWorkspaceBytes
            }
        }

        return [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.RepositoryTreeIdentity'
            Repository = $Repository.FullName
            BranchName = $Repository.DefaultBranch
            CommitSha = [string] @($commitResult.Output)[0]
            TreeSha = [string] @($treeResult.Output)[0]
            GitLfsObjectsAvailable = $gitLfsObjectsAvailable
            GitLfsPointerFiles = $pointerFiles
            PlanningWorkspaceBytes = [long] $workspaceBytes
        }
    }
    finally {
        Remove-Item -LiteralPath $tempPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
