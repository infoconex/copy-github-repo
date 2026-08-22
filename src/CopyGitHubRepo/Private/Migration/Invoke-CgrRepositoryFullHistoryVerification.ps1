function Invoke-CgrRepositoryFullHistoryVerification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $SourceRepository,

        [Parameter(Mandatory)]
        [psobject] $DestinationRepository
    )

    $workspacePath = Join-Path ([System.IO.Path]::GetTempPath()) "copy-github-repo-fullhistory-verify-$([guid]::NewGuid().ToString('N'))"
    $sourcePath = Join-Path $workspacePath 'source.git'
    $destinationPath = Join-Path $workspacePath 'destination.git'

    try {
        New-Item -Path $workspacePath -ItemType Directory -Force | Out-Null

        $gitLfsVersionResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('lfs', 'version')
        if ($gitLfsVersionResult.ExitCode -ne 0) {
            $message = 'Git LFS is required for FullHistory verification so object availability can be checked across all branches and tags.'
            $exception = [System.InvalidOperationException]::new($message)
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'GitLfsRequiredForFullHistoryVerification',
                [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
                'git-lfs'
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $sourceCloneResult = Invoke-CgrGitCommand `
            -HostName $SourceRepository.HostName `
            -ArgumentList @('clone', '--bare', $SourceRepository.CloneUrl, $sourcePath)
        if ($sourceCloneResult.ExitCode -ne 0) {
            $message = "Git failed to clone source '$($SourceRepository.FullName)' for FullHistory verification. $($sourceCloneResult.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'FullHistoryVerificationSourceCloneFailed',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $SourceRepository.FullName
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $destinationCloneResult = Invoke-CgrGitCommand `
            -HostName $DestinationRepository.HostName `
            -ArgumentList @('clone', '--bare', $DestinationRepository.CloneUrl, $destinationPath)
        if ($destinationCloneResult.ExitCode -ne 0) {
            $message = "Git failed to clone destination '$($DestinationRepository.FullName)' for FullHistory verification. $($destinationCloneResult.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'FullHistoryVerificationDestinationCloneFailed',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $DestinationRepository.FullName
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $sourceLfsResult = Invoke-CgrGitCommand `
            -HostName $SourceRepository.HostName `
            -ArgumentList @('-C', $sourcePath, 'lfs', 'fetch', '--all', 'origin')
        $destinationLfsResult = Invoke-CgrGitCommand `
            -HostName $DestinationRepository.HostName `
            -ArgumentList @('-C', $destinationPath, 'lfs', 'fetch', '--all', 'origin')

        $sourceRefsResult = Invoke-CgrNativeCommand `
            -FilePath 'git' `
            -ArgumentList @('-C', $sourcePath, 'for-each-ref', '--format=%(refname) %(objectname)', 'refs/heads', 'refs/tags')
        $destinationRefsResult = Invoke-CgrNativeCommand `
            -FilePath 'git' `
            -ArgumentList @('-C', $destinationPath, 'for-each-ref', '--format=%(refname) %(objectname)', 'refs/heads', 'refs/tags')
        $sourceCommitCountResult = Invoke-CgrNativeCommand `
            -FilePath 'git' `
            -ArgumentList @('-C', $sourcePath, 'rev-list', '--all', '--count')
        $destinationCommitCountResult = Invoke-CgrNativeCommand `
            -FilePath 'git' `
            -ArgumentList @('-C', $destinationPath, 'rev-list', '--all', '--count')
        $sourceBranchesResult = Invoke-CgrNativeCommand `
            -FilePath 'git' `
            -ArgumentList @('-C', $sourcePath, 'for-each-ref', '--format=%(refname)', 'refs/heads')

        $verificationCommands = @(
            [pscustomobject] @{ Result = $sourceLfsResult; ErrorId = 'FullHistoryVerificationSourceGitLfsFetchFailed'; Target = $SourceRepository.FullName }
            [pscustomobject] @{ Result = $destinationLfsResult; ErrorId = 'FullHistoryVerificationDestinationGitLfsFetchFailed'; Target = $DestinationRepository.FullName }
            [pscustomobject] @{ Result = $sourceRefsResult; ErrorId = 'FullHistoryVerificationSourceRefsReadFailed'; Target = $SourceRepository.FullName }
            [pscustomobject] @{ Result = $destinationRefsResult; ErrorId = 'FullHistoryVerificationDestinationRefsReadFailed'; Target = $DestinationRepository.FullName }
            [pscustomobject] @{ Result = $sourceCommitCountResult; ErrorId = 'FullHistoryVerificationSourceCommitCountReadFailed'; Target = $SourceRepository.FullName }
            [pscustomobject] @{ Result = $destinationCommitCountResult; ErrorId = 'FullHistoryVerificationDestinationCommitCountReadFailed'; Target = $DestinationRepository.FullName }
            [pscustomobject] @{ Result = $sourceBranchesResult; ErrorId = 'FullHistoryVerificationSourceBranchesReadFailed'; Target = $SourceRepository.FullName }
        )

        foreach ($command in $verificationCommands) {
            if ($command.Result.ExitCode -ne 0) {
                $message = "Git FullHistory verification command failed for '$($command.Target)'. $($command.Result.ErrorText)"
                $exception = [System.InvalidOperationException]::new($message.Trim())
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    $command.ErrorId,
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $command.Target
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
        }

        $sourceRefs = @($sourceRefsResult.Output | ForEach-Object { $_.ToString() } | Sort-Object)
        $destinationRefs = @($destinationRefsResult.Output | ForEach-Object { $_.ToString() } | Sort-Object)
        $sourceCommitCount = [int] ([string] @($sourceCommitCountResult.Output)[0])
        $destinationCommitCount = [int] ([string] @($destinationCommitCountResult.Output)[0])
        $branches = @($sourceBranchesResult.Output | ForEach-Object { $_.ToString() } | Sort-Object)

        $sourceBranchTrees = [System.Collections.Generic.List[string]]::new()
        $destinationBranchTrees = [System.Collections.Generic.List[string]]::new()
        foreach ($branch in $branches) {
            $sourceTreeResult = Invoke-CgrNativeCommand `
                -FilePath 'git' `
                -ArgumentList @('-C', $sourcePath, 'rev-parse', "$branch^{tree}")
            $destinationTreeResult = Invoke-CgrNativeCommand `
                -FilePath 'git' `
                -ArgumentList @('-C', $destinationPath, 'rev-parse', "$branch^{tree}")

            if ($sourceTreeResult.ExitCode -ne 0 -or $destinationTreeResult.ExitCode -ne 0) {
                $message = "Git failed to read branch-tip tree '$branch' during FullHistory verification."
                $exception = [System.InvalidOperationException]::new($message)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'FullHistoryVerificationBranchTreeReadFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $branch
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            $sourceBranchTrees.Add("$branch $([string] @($sourceTreeResult.Output)[0])")
            $destinationBranchTrees.Add("$branch $([string] @($destinationTreeResult.Output)[0])")
        }

        $refsMatch = ($sourceRefs -join "`n") -eq ($destinationRefs -join "`n")
        $branchTreesMatch = (($sourceBranchTrees.ToArray() | Sort-Object) -join "`n") -eq (($destinationBranchTrees.ToArray() | Sort-Object) -join "`n")

        $checks = @(
            [pscustomobject] @{
                Name = 'DestinationExists'
                Passed = $true
                Expected = $DestinationRepository.FullName
                Actual = $DestinationRepository.FullName
            }
            [pscustomobject] @{
                Name = 'DefaultBranchMatches'
                Passed = $DestinationRepository.DefaultBranch -eq $SourceRepository.DefaultBranch
                Expected = $SourceRepository.DefaultBranch
                Actual = $DestinationRepository.DefaultBranch
            }
            [pscustomobject] @{
                Name = 'BranchAndTagTargetsMatch'
                Passed = $refsMatch
                Expected = $sourceRefs
                Actual = $destinationRefs
            }
            [pscustomobject] @{
                Name = 'ReachableCommitCountMatches'
                Passed = $destinationCommitCount -eq $sourceCommitCount
                Expected = $sourceCommitCount
                Actual = $destinationCommitCount
            }
            [pscustomobject] @{
                Name = 'BranchTipTreesMatch'
                Passed = $branchTreesMatch
                Expected = $sourceBranchTrees.ToArray()
                Actual = $destinationBranchTrees.ToArray()
            }
            [pscustomobject] @{
                Name = 'GitLfsObjectsAvailable'
                Passed = $sourceLfsResult.ExitCode -eq 0 -and $destinationLfsResult.ExitCode -eq 0
                Expected = $true
                Actual = $sourceLfsResult.ExitCode -eq 0 -and $destinationLfsResult.ExitCode -eq 0
            }
        )

        [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.MigrationVerificationResult'
            SchemaVersion = 1
            ContentMode = 'FullHistory'
            SourceRepository = $SourceRepository.FullName
            DestinationRepository = $DestinationRepository.FullName
            BranchName = $SourceRepository.DefaultBranch
            SourceRefCount = $sourceRefs.Count
            DestinationRefCount = $destinationRefs.Count
            SourceReachableCommitCount = $sourceCommitCount
            DestinationReachableCommitCount = $destinationCommitCount
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
