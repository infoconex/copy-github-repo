function Copy-CgrRepositoryFullHistory {
    <#
    .SYNOPSIS
    Copies approved Git history, refs, and reachable Git LFS objects to a destination.

    .DESCRIPTION
    Creates a temporary bare clone, validates the workspace against reviewed
    FullHistory evidence when supplied, transfers reachable Git LFS objects, pushes
    all branches and tags, sets the destination default branch, and returns copied
    source evidence for later verification.

    .NOTES
    This is a Git/GitHub mutation boundary entered only after the public
    ShouldProcess decision. Git LFS is mandatory in FullHistory mode so reachable
    LFS availability can be preserved rather than silently omitted. Temporary
    workspace cleanup runs regardless of success or failure.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'The public Copy-GitHubRepository command performs the ShouldProcess check before calling this migration boundary.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $SourceRepository,
        [Parameter(Mandatory)] [psobject] $DestinationRepository,
        [ValidateNotNullOrEmpty()] [string] $HostName = 'github.com',
        [psobject] $ApprovedSourceState
    )

    $workspacePath = Join-Path ([System.IO.Path]::GetTempPath()) "copy-github-repo-fullhistory-$([guid]::NewGuid().ToString('N'))"
    $sourcePath = Join-Path $workspacePath 'source.git'
    $destinationRemoteName = 'cgr-destination'

    try {
        New-Item -Path $workspacePath -ItemType Directory -Force | Out-Null

        $gitLfsVersionResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('lfs', 'version')
        if ($gitLfsVersionResult.ExitCode -ne 0) {
            $message = 'Git LFS is required for FullHistory migration so LFS object availability can be preserved and verified across all branches and tags.'
            $exception = [System.InvalidOperationException]::new($message)
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'GitLfsRequiredForFullHistory', [System.Management.Automation.ErrorCategory]::ResourceUnavailable, 'git-lfs')
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        Send-CgrActivityEvent -Name 'CloneFullHistory' -State Started -Message "Clone full Git history from '$($SourceRepository.FullName)'"
        $cloneResult = Invoke-CgrGitCommand -HostName $SourceRepository.HostName -ArgumentList @('clone', '--bare', $SourceRepository.CloneUrl, $sourcePath)
        if ($cloneResult.ExitCode -ne 0) {
            Send-CgrActivityEvent -Name 'CloneFullHistory' -State Failed -Message "Clone full Git history from '$($SourceRepository.FullName)'"
            $message = "Git failed to clone full history from '$($SourceRepository.FullName)'. $($cloneResult.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'SourceFullHistoryCloneFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $SourceRepository.FullName)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
        Send-CgrActivityEvent -Name 'CloneFullHistory' -State Completed -Message "Clone full Git history from '$($SourceRepository.FullName)'"

        Send-CgrActivityEvent -Name 'InspectGitLfs' -State Started -Message "Inspect Git LFS content in '$($SourceRepository.FullName)'"
        $lfsListResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $sourcePath, 'lfs', 'ls-files', '--all', '--name-only')
        if ($lfsListResult.ExitCode -ne 0) {
            Send-CgrActivityEvent -Name 'InspectGitLfs' -State Failed -Message "Inspect Git LFS content in '$($SourceRepository.FullName)'"
            $message = "Git LFS failed to enumerate tracked paths in '$($SourceRepository.FullName)'. $($lfsListResult.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'SourceFullHistoryGitLfsListFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $SourceRepository.FullName)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $lfsPaths = @($lfsListResult.Output | Where-Object { -not [string]::IsNullOrWhiteSpace([string] $_) })
        $sourceUsesGitLfs = $lfsPaths.Count -gt 0
        $lfsInspectionMessage = if ($sourceUsesGitLfs) {
            "Found Git LFS content for $($lfsPaths.Count) tracked path(s)."
        }
        else {
            'No Git LFS objects found; no transfer required.'
        }
        Send-CgrActivityEvent -Name 'InspectGitLfs' -State Completed -Message $lfsInspectionMessage

        if ($sourceUsesGitLfs) {
            Send-CgrActivityEvent -Name 'FetchGitLfs' -State Started -Message "Fetch reachable Git LFS objects from '$($SourceRepository.FullName)'"
            $lfsFetchResult = Invoke-CgrGitCommand -HostName $SourceRepository.HostName -ArgumentList @('-C', $sourcePath, 'lfs', 'fetch', '--all', 'origin')
            if ($lfsFetchResult.ExitCode -ne 0) {
                Send-CgrActivityEvent -Name 'FetchGitLfs' -State Failed -Message "Fetch reachable Git LFS objects from '$($SourceRepository.FullName)'"
                $message = "Git LFS failed to fetch all reachable objects from '$($SourceRepository.FullName)'. $($lfsFetchResult.ErrorText)"
                $exception = [System.InvalidOperationException]::new($message.Trim())
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'SourceFullHistoryGitLfsFetchFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $SourceRepository.FullName)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
            Send-CgrActivityEvent -Name 'FetchGitLfs' -State Completed -Message "Fetched reachable Git LFS objects from '$($SourceRepository.FullName)'"
        }

        $copiedSourceEvidence = $null
        if ($ApprovedSourceState) {
            $copiedSourceEvidence = Assert-CgrFullHistoryWorkspaceState `
                -RepositoryPath $sourcePath `
                -ApprovedSourceState $ApprovedSourceState `
                -RepositoryName $SourceRepository.FullName
        }

        $addRemoteResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $sourcePath, 'remote', 'add', $destinationRemoteName, $DestinationRepository.CloneUrl)
        if ($addRemoteResult.ExitCode -ne 0) {
            $message = "Git failed to configure destination '$($DestinationRepository.FullName)' for FullHistory migration. $($addRemoteResult.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationFullHistoryRemoteConfigurationFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $DestinationRepository.FullName)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        if ($sourceUsesGitLfs) {
            Send-CgrActivityEvent -Name 'PushGitLfs' -State Started -Message "Publish Git LFS objects to '$($DestinationRepository.FullName)'"
            $lfsPushResult = Invoke-CgrGitCommand -HostName $DestinationRepository.HostName -ArgumentList @('-C', $sourcePath, 'lfs', 'push', '--all', $destinationRemoteName)
            if ($lfsPushResult.ExitCode -ne 0) {
                Send-CgrActivityEvent -Name 'PushGitLfs' -State Failed -Message "Publish Git LFS objects to '$($DestinationRepository.FullName)'"
                $message = "Git LFS failed to push all reachable objects to '$($DestinationRepository.FullName)'. $($lfsPushResult.ErrorText)"
                $exception = [System.InvalidOperationException]::new($message.Trim())
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationFullHistoryGitLfsPushFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $DestinationRepository.FullName)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
            Send-CgrActivityEvent -Name 'PushGitLfs' -State Completed -Message "Published Git LFS objects to '$($DestinationRepository.FullName)'"
        }

        Send-CgrActivityEvent -Name 'PublishFullHistoryBranches' -State Started -Message "Publish FullHistory branches to '$($DestinationRepository.FullName)'"
        $branchPushResult = Invoke-CgrGitCommand -HostName $DestinationRepository.HostName -ArgumentList @('-C', $sourcePath, 'push', $destinationRemoteName, '--all')
        if ($branchPushResult.ExitCode -ne 0) {
            Send-CgrActivityEvent -Name 'PublishFullHistoryBranches' -State Failed -Message "Publish FullHistory branches to '$($DestinationRepository.FullName)'"
            $message = "Git failed to push branches to '$($DestinationRepository.FullName)'. $($branchPushResult.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationFullHistoryBranchPushFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $DestinationRepository.FullName)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
        Send-CgrActivityEvent -Name 'PublishFullHistoryBranches' -State Completed -Message "Publish FullHistory branches to '$($DestinationRepository.FullName)'"

        Send-CgrActivityEvent -Name 'PublishFullHistoryTags' -State Started -Message "Publish FullHistory tags to '$($DestinationRepository.FullName)'"
        $tagPushResult = Invoke-CgrGitCommand -HostName $DestinationRepository.HostName -ArgumentList @('-C', $sourcePath, 'push', $destinationRemoteName, '--tags')
        if ($tagPushResult.ExitCode -ne 0) {
            Send-CgrActivityEvent -Name 'PublishFullHistoryTags' -State Failed -Message "Publish FullHistory tags to '$($DestinationRepository.FullName)'"
            $message = "Git failed to push tags to '$($DestinationRepository.FullName)'. $($tagPushResult.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationFullHistoryTagPushFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $DestinationRepository.FullName)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
        Send-CgrActivityEvent -Name 'PublishFullHistoryTags' -State Completed -Message "Publish FullHistory tags to '$($DestinationRepository.FullName)'"

        $defaultBranchResult = Invoke-CgrNativeCommand `
            -FilePath 'gh' `
            -ArgumentList @('api', '--hostname', $HostName, '-X', 'PATCH', "repos/$($DestinationRepository.FullName)", '-f', "default_branch=$($SourceRepository.DefaultBranch)")
        if ($defaultBranchResult.ExitCode -ne 0) {
            $message = "GitHub failed to set default branch '$($SourceRepository.DefaultBranch)' on '$($DestinationRepository.FullName)'. $($defaultBranchResult.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationFullHistoryDefaultBranchUpdateFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $DestinationRepository.FullName)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $verifiedDestination = Get-CgrRepository -Repository $DestinationRepository.FullName -HostName $HostName
        [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.FullHistoryCopyResult'
            SourceRepository = $SourceRepository.FullName
            DestinationRepository = $verifiedDestination.FullName
            DefaultBranch = $verifiedDestination.DefaultBranch
            ApprovedSourceState = $ApprovedSourceState
            CopiedSourceEvidence = $copiedSourceEvidence
            BranchesCopied = $true
            TagsCopied = $true
            SourceUsesGitLfs = $sourceUsesGitLfs
            GitLfsTrackedPaths = @($lfsPaths)
            GitLfsObjectsCopied = $sourceUsesGitLfs
            IsSuccessful = $true
        }
    }
    finally {
        if (Test-Path -LiteralPath $workspacePath) {
            Remove-Item -LiteralPath $workspacePath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
