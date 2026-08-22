function Copy-CgrRepositorySnapshot {
    <#
    .SYNOPSIS
    Publishes an approved source tree as one clean Snapshot root commit.

    .DESCRIPTION
    Clones only the approved source branch, verifies the cloned commit and tree
    against reviewed source-state evidence when provided, creates an unrelated
    commit-tree root, transfers required Git LFS content, pushes the destination
    branch, and confirms the remote ref points to the new root commit.

    .NOTES
    This is a Git mutation boundary called after the public ShouldProcess decision.
    The temporary workspace is always removed. Approved-state mismatch stops before
    the destination branch is published so a reviewed plan cannot silently drift.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'The public Copy-GitHubRepository command performs the ShouldProcess check before calling this Git boundary.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $SourceRepository,
        [Parameter(Mandatory)] [psobject] $DestinationRepository,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $BranchName,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $CommitMessage,
        [psobject] $ApprovedSourceState
    )

    $workspacePath = Join-Path ([System.IO.Path]::GetTempPath()) "copy-github-repo-$([guid]::NewGuid().ToString('N'))"
    $sourcePath = Join-Path $workspacePath 'source'

    try {
        New-Item -Path $workspacePath -ItemType Directory -Force | Out-Null

        Send-CgrActivityEvent -Name 'CloneSourceContent' -State Started -Message "Clone source content from '$($SourceRepository.FullName)'"
        $cloneSourceResult = Invoke-CgrGitCommand `
            -HostName $SourceRepository.HostName `
            -Environment @{ GIT_LFS_SKIP_SMUDGE = '1' } `
            -ArgumentList @('clone', '--depth', '1', '--branch', $BranchName, $SourceRepository.CloneUrl, $sourcePath)

        if ($cloneSourceResult.ExitCode -ne 0) {
            Send-CgrActivityEvent -Name 'CloneSourceContent' -State Failed -Message "Clone source content from '$($SourceRepository.FullName)'"
            $message = "Git failed to clone source repository '$($SourceRepository.FullName)'. $($cloneSourceResult.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'SourceRepositoryCloneFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $SourceRepository.FullName)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
        Send-CgrActivityEvent -Name 'CloneSourceContent' -State Completed -Message "Clone source content from '$($SourceRepository.FullName)'"

        $sourceCommitResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $sourcePath, 'rev-parse', 'HEAD')
        if ($sourceCommitResult.ExitCode -ne 0) {
            $message = "Git failed to read source commit for '$($SourceRepository.FullName)'. $($sourceCommitResult.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'SourceRepositoryCommitReadFailed', [System.Management.Automation.ErrorCategory]::InvalidData, $SourceRepository.FullName)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
        $sourceCommitSha = [string] @($sourceCommitResult.Output)[0]

        $treeShaResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $sourcePath, 'rev-parse', 'HEAD^{tree}')
        if ($treeShaResult.ExitCode -ne 0) {
            $message = "Git failed to read source tree for '$($SourceRepository.FullName)'. $($treeShaResult.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'SourceRepositoryTreeReadFailed', [System.Management.Automation.ErrorCategory]::InvalidData, $SourceRepository.FullName)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
        $treeSha = [string] @($treeShaResult.Output)[0]

        if ($ApprovedSourceState) {
            $expectedCommitSha = [string] (Get-CgrObjectProperty -InputObject $ApprovedSourceState -Name 'CommitSha')
            $expectedTreeSha = [string] (Get-CgrObjectProperty -InputObject $ApprovedSourceState -Name 'TreeSha')
            $expectedBranch = [string] (Get-CgrObjectProperty -InputObject $ApprovedSourceState -Name 'DefaultBranch')
            if ($BranchName -ne $expectedBranch -or $sourceCommitSha -ne $expectedCommitSha -or $treeSha -ne $expectedTreeSha) {
                $message = "Source repository '$($SourceRepository.FullName)' no longer matches the approved Snapshot source state. Nothing was published. Recreate and review the repository copy plan."
                $exception = [System.InvalidOperationException]::new($message)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'SourceStateChangedSincePlanning', [System.Management.Automation.ErrorCategory]::InvalidResult, $SourceRepository.FullName)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
        }

        $commitIdentity = Get-CgrGitCommitIdentity -HostName $DestinationRepository.HostName

        Send-CgrActivityEvent -Name 'PublishSnapshot' -State Started -Message "Publish clean Snapshot to '$($DestinationRepository.FullName)'"
        $commitResult = Invoke-CgrNativeCommand `
            -FilePath 'git' `
            -ArgumentList @('-C', $sourcePath, '-c', "user.name=$($commitIdentity.Name)", '-c', "user.email=$($commitIdentity.Email)", 'commit-tree', $treeSha, '-m', $CommitMessage)
        if ($commitResult.ExitCode -ne 0) {
            Send-CgrActivityEvent -Name 'PublishSnapshot' -State Failed -Message "Publish clean Snapshot to '$($DestinationRepository.FullName)'"
            $message = "Git failed to create snapshot commit for '$($DestinationRepository.FullName)'. $($commitResult.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationRepositorySnapshotCommitFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $DestinationRepository.FullName)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
        $commitSha = [string] @($commitResult.Output)[0]

        $gitLfs = Invoke-CgrActivityStage `
            -Name 'TransferGitLfs' `
            -Message "Transfer Git LFS objects to '$($DestinationRepository.FullName)'" `
            -Action {
                Copy-CgrGitLfsObject -SourcePath $sourcePath -SourceRepository $SourceRepository -DestinationRepository $DestinationRepository -BranchName $BranchName
            }

        $pushRef = "$($commitSha):refs/heads/$BranchName"
        $pushResult = Invoke-CgrGitCommand -HostName $DestinationRepository.HostName -ArgumentList @('-C', $sourcePath, 'push', $DestinationRepository.CloneUrl, $pushRef)
        if ($pushResult.ExitCode -ne 0) {
            Send-CgrActivityEvent -Name 'PublishSnapshot' -State Failed -Message "Publish clean Snapshot to '$($DestinationRepository.FullName)'"
            $message = "Git failed to push snapshot commit to '$($DestinationRepository.FullName)'. $($pushResult.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationRepositorySnapshotPushFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $DestinationRepository.FullName)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $remoteRefResult = Invoke-CgrGitCommand -HostName $DestinationRepository.HostName -ArgumentList @('ls-remote', '--heads', $DestinationRepository.CloneUrl, $BranchName)
        if ($remoteRefResult.ExitCode -ne 0) {
            Send-CgrActivityEvent -Name 'PublishSnapshot' -State Failed -Message "Publish clean Snapshot to '$($DestinationRepository.FullName)'"
            $message = "Git failed to verify destination branch '$BranchName' for '$($DestinationRepository.FullName)'. $($remoteRefResult.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationRepositorySnapshotVerifyFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $DestinationRepository.FullName)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $remoteRef = (@($remoteRefResult.Output) | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        if ($remoteRef -notmatch [regex]::Escape($commitSha)) {
            Send-CgrActivityEvent -Name 'PublishSnapshot' -State Failed -Message "Publish clean Snapshot to '$($DestinationRepository.FullName)'"
            $message = "Destination branch '$BranchName' does not reference snapshot commit '$commitSha'."
            $exception = [System.InvalidOperationException]::new($message)
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationRepositorySnapshotVerifyMismatch', [System.Management.Automation.ErrorCategory]::InvalidData, $DestinationRepository.FullName)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
        Send-CgrActivityEvent -Name 'PublishSnapshot' -State Completed -Message "Publish clean Snapshot to '$($DestinationRepository.FullName)'"

        return [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.SnapshotCopyResult'
            SourceRepository = $SourceRepository.FullName
            SourceCommitSha = $sourceCommitSha
            DestinationRepository = $DestinationRepository.FullName
            BranchName = $BranchName
            CommitSha = $commitSha
            TreeSha = $treeSha
            GitLfs = $gitLfs
            ApprovedSourceState = $ApprovedSourceState
            Verified = $true
        }
    }
    finally {
        if (Test-Path -LiteralPath $workspacePath) {
            Remove-Item -LiteralPath $workspacePath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
