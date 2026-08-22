function Invoke-CgrRepositorySnapshotVerification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $SourceRepository,

        [Parameter(Mandatory)]
        [psobject] $DestinationRepository,

        [psobject] $ApprovedSourceState
    )

    $branchName = if ($ApprovedSourceState) {
        [string] (Get-CgrObjectProperty -InputObject $ApprovedSourceState -Name 'DefaultBranch')
    }
    else {
        $SourceRepository.DefaultBranch
    }
    $sourceHostName = ([uri] $SourceRepository.CloneUrl).Host
    $destinationHostName = ([uri] $DestinationRepository.CloneUrl).Host

    if ($SourceRepository.PSObject.Properties.Name -contains 'HostName') {
        $sourceHostName = $SourceRepository.HostName
    }

    if ($DestinationRepository.PSObject.Properties.Name -contains 'HostName') {
        $destinationHostName = $DestinationRepository.HostName
    }

    $workspacePath = Join-Path ([System.IO.Path]::GetTempPath()) "copy-github-repo-verify-$([guid]::NewGuid().ToString('N'))"
    $sourcePath = Join-Path $workspacePath 'source'
    $destinationPath = Join-Path $workspacePath 'destination'

    try {
        New-Item -Path $workspacePath -ItemType Directory -Force | Out-Null

        $sourceTree = if ($ApprovedSourceState) {
            [string] (Get-CgrObjectProperty -InputObject $ApprovedSourceState -Name 'TreeSha')
        }
        else {
            $cloneSourceResult = Invoke-CgrGitCommand `
                -HostName $sourceHostName `
                -ArgumentList @('clone', '--depth', '1', '--branch', $branchName, $SourceRepository.CloneUrl, $sourcePath)
            if ($cloneSourceResult.ExitCode -ne 0) {
                $message = "Git failed to clone source repository '$($SourceRepository.FullName)' for verification. $($cloneSourceResult.ErrorText)"
                $exception = [System.InvalidOperationException]::new($message.Trim())
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'VerificationSourceRepositoryCloneFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $SourceRepository.FullName)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
            $sourceTreeResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $sourcePath, 'rev-parse', 'HEAD^{tree}')
            if ($sourceTreeResult.ExitCode -ne 0) {
                $message = "Git verification command failed for '$($SourceRepository.FullName)'. $($sourceTreeResult.ErrorText)"
                $exception = [System.InvalidOperationException]::new($message.Trim())
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'VerificationSourceTreeReadFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $SourceRepository.FullName)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
            [string] @($sourceTreeResult.Output)[0]
        }

        $cloneDestinationResult = Invoke-CgrGitCommand `
            -HostName $destinationHostName `
            -ArgumentList @('clone', '--depth', '2', '--branch', $branchName, $DestinationRepository.CloneUrl, $destinationPath)
        if ($cloneDestinationResult.ExitCode -ne 0) {
            $message = "Git failed to clone destination repository '$($DestinationRepository.FullName)' for verification. $($cloneDestinationResult.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'VerificationDestinationRepositoryCloneFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $DestinationRepository.FullName)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $destinationTreeResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $destinationPath, 'rev-parse', 'HEAD^{tree}')
        $destinationCommitResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $destinationPath, 'rev-parse', 'HEAD')
        $destinationCommitCountResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $destinationPath, 'rev-list', '--count', 'HEAD')
        $destinationParentResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $destinationPath, 'rev-list', '--parents', '-n', '1', 'HEAD')

        $verificationCommands = @(
            [pscustomobject] @{ Result = $destinationTreeResult; ErrorId = 'VerificationDestinationTreeReadFailed'; Target = $DestinationRepository.FullName }
            [pscustomobject] @{ Result = $destinationCommitResult; ErrorId = 'VerificationDestinationCommitReadFailed'; Target = $DestinationRepository.FullName }
            [pscustomobject] @{ Result = $destinationCommitCountResult; ErrorId = 'VerificationDestinationCommitCountReadFailed'; Target = $DestinationRepository.FullName }
            [pscustomobject] @{ Result = $destinationParentResult; ErrorId = 'VerificationDestinationParentReadFailed'; Target = $DestinationRepository.FullName }
        )
        foreach ($command in $verificationCommands) {
            if ($command.Result.ExitCode -ne 0) {
                $message = "Git verification command failed for '$($command.Target)'. $($command.Result.ErrorText)"
                $exception = [System.InvalidOperationException]::new($message.Trim())
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, $command.ErrorId, [System.Management.Automation.ErrorCategory]::InvalidOperation, $command.Target)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
        }

        $destinationTree = [string] @($destinationTreeResult.Output)[0]
        $destinationCommit = [string] @($destinationCommitResult.Output)[0]
        $destinationCommitCount = [int] ([string] @($destinationCommitCountResult.Output)[0])
        $parentLine = [string] @($destinationParentResult.Output)[0]
        $parentCount = @($parentLine.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)).Count - 1

        $checks = @(
            [pscustomobject] @{ Name = 'DestinationExists'; Passed = $true; Expected = $DestinationRepository.FullName; Actual = $DestinationRepository.FullName }
            [pscustomobject] @{ Name = 'DefaultBranchMatches'; Passed = $DestinationRepository.DefaultBranch -eq $branchName; Expected = $branchName; Actual = $DestinationRepository.DefaultBranch }
            [pscustomobject] @{ Name = 'GitTreeMatches'; Passed = $destinationTree -eq $sourceTree; Expected = $sourceTree; Actual = $destinationTree }
            [pscustomobject] @{ Name = 'DestinationHasOneCommit'; Passed = $destinationCommitCount -eq 1; Expected = 1; Actual = $destinationCommitCount }
            [pscustomobject] @{ Name = 'DestinationCommitHasNoParents'; Passed = $parentCount -eq 0; Expected = 0; Actual = $parentCount }
        )

        return [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.MigrationVerificationResult'
            SchemaVersion = 1
            ContentMode = 'Snapshot'
            SourceRepository = $SourceRepository.FullName
            ApprovedSourceState = $ApprovedSourceState
            DestinationRepository = $DestinationRepository.FullName
            BranchName = $branchName
            SourceTree = $sourceTree
            DestinationTree = $destinationTree
            DestinationCommit = $destinationCommit
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
