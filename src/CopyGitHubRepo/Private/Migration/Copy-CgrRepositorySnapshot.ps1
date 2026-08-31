function Copy-CgrRepositorySnapshot {
    <#
    .SYNOPSIS
    Publishes an approved source tree as a clean unrelated Snapshot history.

    .DESCRIPTION
    Clones only the approved source branch and verifies the cloned HEAD against reviewed
    source-state evidence. Plain Snapshot creates one unrelated root commit. When an
    immutable release-checkpoint plan is supplied, execution fetches only the reviewed
    source commits by SHA, verifies each reviewed tree, and constructs a new linear
    destination history in the exact reviewed checkpoint order. It never reruns live
    release selection or topology ordering.

    Generated checkpoint messages use the deterministic convention
    "Snapshot release checkpoint <order>: <reviewed tag names>" and an optional final
    reviewed HEAD commit uses "Snapshot current state". Destination commit identities,
    authorship, timestamps, and ancestry are intentionally new.

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
        [psobject] $ApprovedSourceState,
        [psobject] $ReleaseCheckpointPlan
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

        $checkpoints = @()
        $finalHeadCheckpointRequired = $false
        if ($ReleaseCheckpointPlan) {
            $plannedSourceHead = Get-CgrObjectProperty -InputObject $ReleaseCheckpointPlan -Name 'SourceHead'
            if ($null -eq $plannedSourceHead -or
                [string] (Get-CgrObjectProperty -InputObject $plannedSourceHead -Name 'CommitSha') -ne $sourceCommitSha -or
                [string] (Get-CgrObjectProperty -InputObject $plannedSourceHead -Name 'TreeSha') -ne $treeSha) {
                $message = 'The approved Snapshot release-checkpoint plan does not match the reviewed source HEAD state. Nothing was published. Recreate and review the repository copy plan.'
                $exception = [System.InvalidOperationException]::new($message)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'SnapshotReleaseCheckpointPlanSourceMismatch', [System.Management.Automation.ErrorCategory]::InvalidData, $SourceRepository.FullName)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
            $checkpoints = @(Get-CgrObjectProperty -InputObject $ReleaseCheckpointPlan -Name 'Checkpoints')
            $finalHeadCheckpointRequired = [bool] (Get-CgrObjectProperty -InputObject $ReleaseCheckpointPlan -Name 'FinalHeadCheckpointRequired')
            if ($checkpoints.Count -eq 0 -and -not $finalHeadCheckpointRequired) {
                $message = 'The approved Snapshot release-checkpoint plan contains no release checkpoints and does not require the reviewed HEAD state, so it cannot produce a Snapshot commit.'
                $exception = [System.InvalidOperationException]::new($message)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'SnapshotReleaseCheckpointPlanEmpty', [System.Management.Automation.ErrorCategory]::InvalidData, $SourceRepository.FullName)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
        }

        $commitIdentity = Get-CgrGitCommitIdentity -HostName $DestinationRepository.HostName
        $generatedCommits = [System.Collections.Generic.List[object]]::new()
        $parentCommitSha = $null

        Send-CgrActivityEvent -Name 'PublishSnapshot' -State Started -Message "Publish clean Snapshot to '$($DestinationRepository.FullName)'"

        foreach ($checkpoint in $checkpoints) {
            $reviewedSourceCommitSha = [string] (Get-CgrObjectProperty -InputObject $checkpoint -Name 'SourceCommitSha')
            $reviewedSourceTreeSha = [string] (Get-CgrObjectProperty -InputObject $checkpoint -Name 'SourceTreeSha')
            $checkpointOrder = [int] (Get-CgrObjectProperty -InputObject $checkpoint -Name 'Order')
            $tagNames = @(Get-CgrObjectProperty -InputObject $checkpoint -Name 'TagNames')

            $fetchCheckpointResult = Invoke-CgrGitCommand `
                -HostName $SourceRepository.HostName `
                -Environment @{ GIT_LFS_SKIP_SMUDGE = '1' } `
                -ArgumentList @('-C', $sourcePath, 'fetch', '--depth', '1', 'origin', $reviewedSourceCommitSha)
            if ($fetchCheckpointResult.ExitCode -ne 0) {
                Send-CgrActivityEvent -Name 'PublishSnapshot' -State Failed -Message "Publish clean Snapshot to '$($DestinationRepository.FullName)'"
                $message = "Git failed to fetch reviewed Snapshot checkpoint source commit '$reviewedSourceCommitSha'. $($fetchCheckpointResult.ErrorText)"
                $exception = [System.InvalidOperationException]::new($message.Trim())
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'SnapshotReleaseCheckpointFetchFailed', [System.Management.Automation.ErrorCategory]::ReadError, $reviewedSourceCommitSha)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            $checkpointTreeResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $sourcePath, 'rev-parse', "$reviewedSourceCommitSha^{tree}")
            if ($checkpointTreeResult.ExitCode -ne 0) {
                $message = "Git failed to read the fetched tree for reviewed Snapshot checkpoint '$reviewedSourceCommitSha'. $($checkpointTreeResult.ErrorText)"
                $exception = [System.InvalidOperationException]::new($message.Trim())
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'SnapshotReleaseCheckpointTreeReadFailed', [System.Management.Automation.ErrorCategory]::InvalidData, $reviewedSourceCommitSha)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
            $actualCheckpointTreeSha = [string] @($checkpointTreeResult.Output)[0]
            if ($actualCheckpointTreeSha -ne $reviewedSourceTreeSha) {
                $message = "Reviewed Snapshot checkpoint source commit '$reviewedSourceCommitSha' no longer resolves to planned tree '$reviewedSourceTreeSha'. Nothing was published."
                $exception = [System.InvalidOperationException]::new($message)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'SnapshotReleaseCheckpointTreeMismatch', [System.Management.Automation.ErrorCategory]::InvalidResult, $reviewedSourceCommitSha)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            $checkpointMessage = "Snapshot release checkpoint $checkpointOrder: $($tagNames -join ', ')"
            $checkpointCommitArguments = @('-C', $sourcePath, '-c', "user.name=$($commitIdentity.Name)", '-c', "user.email=$($commitIdentity.Email)", 'commit-tree', $reviewedSourceTreeSha)
            if ($parentCommitSha) {
                $checkpointCommitArguments += @('-p', $parentCommitSha)
            }
            $checkpointCommitArguments += @('-m', $checkpointMessage)
            $checkpointCommitResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList $checkpointCommitArguments
            if ($checkpointCommitResult.ExitCode -ne 0) {
                Send-CgrActivityEvent -Name 'PublishSnapshot' -State Failed -Message "Publish clean Snapshot to '$($DestinationRepository.FullName)'"
                $message = "Git failed to create Snapshot release checkpoint $checkpointOrder for '$($DestinationRepository.FullName)'. $($checkpointCommitResult.ErrorText)"
                $exception = [System.InvalidOperationException]::new($message.Trim())
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationRepositorySnapshotCheckpointCommitFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $DestinationRepository.FullName)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
            $parentCommitSha = [string] @($checkpointCommitResult.Output)[0]
            $generatedCommits.Add([pscustomobject] @{
                    Kind = 'ReleaseCheckpoint'
                    Order = $checkpointOrder
                    SourceCommitSha = $reviewedSourceCommitSha
                    SourceTreeSha = $reviewedSourceTreeSha
                    TagNames = $tagNames
                    CommitSha = $parentCommitSha
                    TreeSha = $reviewedSourceTreeSha
                    Message = $checkpointMessage
                })
        }

        if ($checkpoints.Count -eq 0 -or $finalHeadCheckpointRequired) {
            $currentStateMessage = if ($checkpoints.Count -eq 0) { $CommitMessage } else { 'Snapshot current state' }
            $currentStateCommitArguments = @('-C', $sourcePath, '-c', "user.name=$($commitIdentity.Name)", '-c', "user.email=$($commitIdentity.Email)", 'commit-tree', $treeSha)
            if ($parentCommitSha) {
                $currentStateCommitArguments += @('-p', $parentCommitSha)
            }
            $currentStateCommitArguments += @('-m', $currentStateMessage)
            $currentStateCommitResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList $currentStateCommitArguments
            if ($currentStateCommitResult.ExitCode -ne 0) {
                Send-CgrActivityEvent -Name 'PublishSnapshot' -State Failed -Message "Publish clean Snapshot to '$($DestinationRepository.FullName)'"
                $message = "Git failed to create snapshot commit for '$($DestinationRepository.FullName)'. $($currentStateCommitResult.ErrorText)"
                $exception = [System.InvalidOperationException]::new($message.Trim())
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationRepositorySnapshotCommitFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $DestinationRepository.FullName)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
            $parentCommitSha = [string] @($currentStateCommitResult.Output)[0]
            $generatedCommits.Add([pscustomobject] @{
                    Kind = if ($checkpoints.Count -eq 0) { 'SnapshotRoot' } else { 'CurrentHead' }
                    Order = $generatedCommits.Count + 1
                    SourceCommitSha = $sourceCommitSha
                    SourceTreeSha = $treeSha
                    TagNames = @()
                    CommitSha = $parentCommitSha
                    TreeSha = $treeSha
                    Message = $currentStateMessage
                })
        }

        $commitSha = $parentCommitSha
        $rootCommitSha = [string] (Get-CgrObjectProperty -InputObject $generatedCommits[0] -Name 'CommitSha')

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
            RootCommitSha = $rootCommitSha
            TreeSha = $treeSha
            GitLfs = $gitLfs
            ApprovedSourceState = $ApprovedSourceState
            ReleaseCheckpointPlan = $ReleaseCheckpointPlan
            GeneratedCommits = $generatedCommits.ToArray()
            FinalHeadCommitCreated = [bool] ($ReleaseCheckpointPlan -and $checkpoints.Count -gt 0 -and $finalHeadCheckpointRequired)
            Verified = $true
        }
    }
    finally {
        if (Test-Path -LiteralPath $workspacePath) {
            Remove-Item -LiteralPath $workspacePath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
