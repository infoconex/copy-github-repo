function Invoke-CgrApprovedSnapshotReleaseVerification {
    <#
    .SYNOPSIS
    Verifies generated Snapshot release checkpoints from immutable reviewed evidence.

    .DESCRIPTION
    Reads only the destination Git repository and compares its generated linear Snapshot
    history with the reviewed release-checkpoint plan. Source commit identities are not
    expected to survive Snapshot publication; verification instead proves checkpoint
    order, parent relationships, tree equivalence, release-tag targets, and reviewed HEAD
    equivalence from immutable planning evidence.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $SourceRepository,

        [Parameter(Mandatory)]
        [psobject] $DestinationRepository,

        [Parameter(Mandatory)]
        [psobject] $ReleaseCheckpointPlan
    )

    $workspacePath = Join-Path ([System.IO.Path]::GetTempPath()) "copy-github-repo-snapshot-release-verify-$([guid]::NewGuid().ToString('N'))"
    $destinationPath = Join-Path $workspacePath 'destination.git'

    try {
        New-Item -Path $workspacePath -ItemType Directory -Force | Out-Null

        $destinationHostName = if ($DestinationRepository.PSObject.Properties.Name -contains 'HostName') {
            [string] $DestinationRepository.HostName
        }
        else {
            ([uri] $DestinationRepository.CloneUrl).Host
        }

        $cloneResult = Invoke-CgrGitCommand `
            -HostName $destinationHostName `
            -ArgumentList @('clone', '--bare', $DestinationRepository.CloneUrl, $destinationPath)
        if ($cloneResult.ExitCode -ne 0) {
            $message = "Git failed to clone destination repository '$($DestinationRepository.FullName)' for Snapshot release verification. $($cloneResult.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'SnapshotReleaseVerificationDestinationCloneFailed',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $DestinationRepository.FullName
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $sourceHead = Get-CgrObjectProperty -InputObject $ReleaseCheckpointPlan -Name 'SourceHead'
        $checkpoints = @(Get-CgrObjectProperty -InputObject $ReleaseCheckpointPlan -Name 'Checkpoints')
        $releaseEvidence = @(Get-CgrObjectProperty -InputObject $ReleaseCheckpointPlan -Name 'ReleaseEvidence')
        $expectedCommitCount = [int] (Get-CgrObjectProperty -InputObject $ReleaseCheckpointPlan -Name 'PlannedSnapshotCommitCount')
        $finalHeadCheckpointRequired = [bool] (Get-CgrObjectProperty -InputObject $ReleaseCheckpointPlan -Name 'FinalHeadCheckpointRequired')
        $expectedBranch = [string] (Get-CgrObjectProperty -InputObject $sourceHead -Name 'DefaultBranch')
        $expectedHeadTree = [string] (Get-CgrObjectProperty -InputObject $sourceHead -Name 'TreeSha')

        $historyResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $destinationPath, 'rev-list', '--reverse', "refs/heads/$expectedBranch")
        if ($historyResult.ExitCode -ne 0) {
            $message = "Git failed to read generated Snapshot history for destination '$($DestinationRepository.FullName)'. $($historyResult.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'SnapshotReleaseVerificationHistoryReadFailed',
                [System.Management.Automation.ErrorCategory]::ReadError,
                $DestinationRepository.FullName
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $destinationCommits = @($historyResult.Output | ForEach-Object { [string] $_ })
        $checks = [System.Collections.Generic.List[object]]::new()
        $checkpointResults = [System.Collections.Generic.List[object]]::new()
        $releaseTagResults = [System.Collections.Generic.List[object]]::new()

        $checks.Add([pscustomobject] @{
                Name = 'DestinationExists'
                Passed = $true
                Expected = $DestinationRepository.FullName
                Actual = $DestinationRepository.FullName
            })
        $checks.Add([pscustomobject] @{
                Name = 'DefaultBranchMatches'
                Passed = [string] $DestinationRepository.DefaultBranch -eq $expectedBranch
                Expected = $expectedBranch
                Actual = [string] $DestinationRepository.DefaultBranch
            })
        $checks.Add([pscustomobject] @{
                Name = 'SnapshotCommitCountMatchesReviewedPlan'
                Passed = $destinationCommits.Count -eq $expectedCommitCount
                Expected = $expectedCommitCount
                Actual = $destinationCommits.Count
            })

        for ($index = 0; $index -lt $destinationCommits.Count; $index++) {
            $commitSha = [string] $destinationCommits[$index]
            $parentsResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $destinationPath, 'rev-list', '--parents', '-n', '1', $commitSha)
            if ($parentsResult.ExitCode -ne 0) {
                $message = "Git failed to read parents for generated Snapshot commit '$commitSha'. $($parentsResult.ErrorText)"
                $exception = [System.InvalidOperationException]::new($message.Trim())
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'SnapshotReleaseVerificationParentReadFailed',
                    [System.Management.Automation.ErrorCategory]::ReadError,
                    $commitSha
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            $parts = @(([string] @($parentsResult.Output)[0]).Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries))
            $expectedParents = if ($index -eq 0) { @() } else { @([string] $destinationCommits[$index - 1]) }
            $actualParents = if ($parts.Count -gt 1) { @($parts[1..($parts.Count - 1)]) } else { @() }
            $checks.Add([pscustomobject] @{
                    Name = "SnapshotCommitParent:$($index + 1)"
                    Passed = ($actualParents -join "`n") -eq ($expectedParents -join "`n")
                    Expected = $expectedParents
                    Actual = $actualParents
                })
        }

        foreach ($checkpoint in $checkpoints) {
            $order = [int] (Get-CgrObjectProperty -InputObject $checkpoint -Name 'Order')
            $expectedTree = [string] (Get-CgrObjectProperty -InputObject $checkpoint -Name 'SourceTreeSha')
            $sourceCommitSha = [string] (Get-CgrObjectProperty -InputObject $checkpoint -Name 'SourceCommitSha')
            $destinationCommitSha = if ($order -ge 1 -and $order -le $destinationCommits.Count) {
                [string] $destinationCommits[$order - 1]
            }
            else {
                $null
            }

            $actualTree = $null
            if (-not [string]::IsNullOrWhiteSpace($destinationCommitSha)) {
                $treeResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $destinationPath, 'rev-parse', "$destinationCommitSha^{tree}")
                if ($treeResult.ExitCode -ne 0) {
                    $message = "Git failed to read tree for generated Snapshot checkpoint $order ('$destinationCommitSha'). $($treeResult.ErrorText)"
                    $exception = [System.InvalidOperationException]::new($message.Trim())
                    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                        $exception,
                        'SnapshotReleaseVerificationCheckpointTreeReadFailed',
                        [System.Management.Automation.ErrorCategory]::ReadError,
                        $destinationCommitSha
                    )
                    $PSCmdlet.ThrowTerminatingError($errorRecord)
                }
                $actualTree = [string] @($treeResult.Output)[0]
            }

            $checkpointPassed = -not [string]::IsNullOrWhiteSpace($destinationCommitSha) -and $actualTree -eq $expectedTree
            $checks.Add([pscustomobject] @{
                    Name = "SnapshotCheckpointTree:$order"
                    Passed = $checkpointPassed
                    Expected = $expectedTree
                    Actual = $actualTree
                })
            $checkpointResults.Add([pscustomobject] @{
                    Order = $order
                    SourceCommitSha = $sourceCommitSha
                    ExpectedTreeSha = $expectedTree
                    DestinationCommitSha = $destinationCommitSha
                    DestinationTreeSha = $actualTree
                    TagNames = @(Get-CgrObjectProperty -InputObject $checkpoint -Name 'TagNames')
                    IsSuccessful = $checkpointPassed
                })
        }

        $destinationHeadCommit = if ($destinationCommits.Count -gt 0) { [string] $destinationCommits[-1] } else { $null }
        $destinationHeadTree = $null
        if ($destinationHeadCommit) {
            $headTreeResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $destinationPath, 'rev-parse', "$destinationHeadCommit^{tree}")
            if ($headTreeResult.ExitCode -ne 0) {
                $message = "Git failed to read destination Snapshot HEAD tree. $($headTreeResult.ErrorText)"
                $exception = [System.InvalidOperationException]::new($message.Trim())
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'SnapshotReleaseVerificationHeadTreeReadFailed',
                    [System.Management.Automation.ErrorCategory]::ReadError,
                    $DestinationRepository.FullName
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
            $destinationHeadTree = [string] @($headTreeResult.Output)[0]
        }

        $checks.Add([pscustomobject] @{
                Name = 'SnapshotHeadTreeMatchesReviewedSourceHead'
                Passed = $destinationHeadTree -eq $expectedHeadTree
                Expected = $expectedHeadTree
                Actual = $destinationHeadTree
            })

        $expectedFinalCommitKind = if ($finalHeadCheckpointRequired) { 'CurrentStateCheckpoint' } else { 'LatestReleaseCheckpoint' }
        $actualFinalCommitKind = if ($destinationCommits.Count -ne $expectedCommitCount) {
            'UnexpectedCommitCount'
        }
        elseif ($finalHeadCheckpointRequired -and $destinationCommits.Count -gt $checkpoints.Count) {
            'CurrentStateCheckpoint'
        }
        elseif (-not $finalHeadCheckpointRequired -and $destinationCommits.Count -eq $checkpoints.Count) {
            'LatestReleaseCheckpoint'
        }
        else {
            'UnexpectedHistoryShape'
        }
        $checks.Add([pscustomobject] @{
                Name = 'SnapshotFinalHeadCheckpointShape'
                Passed = $actualFinalCommitKind -eq $expectedFinalCommitKind
                Expected = $expectedFinalCommitKind
                Actual = $actualFinalCommitKind
            })

        foreach ($evidence in $releaseEvidence) {
            $tagName = [string] (Get-CgrObjectProperty -InputObject $evidence -Name 'TagName')
            $sourceCommitSha = [string] (Get-CgrObjectProperty -InputObject $evidence -Name 'PeeledCommitSha')
            $mappedCheckpoint = @($checkpointResults | Where-Object SourceCommitSha -EQ $sourceCommitSha)
            $expectedDestinationCommit = if ($mappedCheckpoint.Count -eq 1) { [string] $mappedCheckpoint[0].DestinationCommitSha } else { $null }

            $tagResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $destinationPath, 'rev-parse', "refs/tags/$tagName^{commit}")
            $actualDestinationCommit = if ($tagResult.ExitCode -eq 0) { [string] @($tagResult.Output)[0] } else { $null }
            $tagPassed = -not [string]::IsNullOrWhiteSpace($expectedDestinationCommit) -and $actualDestinationCommit -eq $expectedDestinationCommit
            $checks.Add([pscustomobject] @{
                    Name = "SnapshotReleaseTagTarget:$tagName"
                    Passed = $tagPassed
                    Expected = $expectedDestinationCommit
                    Actual = $actualDestinationCommit
                })
            $releaseTagResults.Add([pscustomobject] @{
                    TagName = $tagName
                    SourceCommitSha = $sourceCommitSha
                    DestinationCommitSha = $actualDestinationCommit
                    ExpectedDestinationCommitSha = $expectedDestinationCommit
                    IsSuccessful = $tagPassed
                })
        }

        $tagListResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $destinationPath, 'for-each-ref', '--format=%(refname:strip=2)', 'refs/tags')
        if ($tagListResult.ExitCode -ne 0) {
            $message = "Git failed to enumerate destination Snapshot release tags. $($tagListResult.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'SnapshotReleaseVerificationTagEnumerationFailed',
                [System.Management.Automation.ErrorCategory]::ReadError,
                $DestinationRepository.FullName
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
        $expectedTags = @($releaseEvidence | ForEach-Object { [string] (Get-CgrObjectProperty -InputObject $_ -Name 'TagName') } | Sort-Object)
        $actualTags = @($tagListResult.Output | ForEach-Object { [string] $_ } | Sort-Object)
        $checks.Add([pscustomobject] @{
                Name = 'SnapshotReleaseTagsMatchReviewedSelection'
                Passed = ($actualTags -join "`n") -eq ($expectedTags -join "`n")
                Expected = $expectedTags
                Actual = $actualTags
            })

        [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.MigrationVerificationResult'
            SchemaVersion = 1
            ContentMode = 'Snapshot'
            IncludeReleases = $true
            SourceRepository = $SourceRepository.FullName
            DestinationRepository = $DestinationRepository.FullName
            ApprovedReleaseCheckpointPlan = $ReleaseCheckpointPlan
            BranchName = $expectedBranch
            ExpectedCommitCount = $expectedCommitCount
            DestinationCommitCount = $destinationCommits.Count
            FinalHeadCheckpointRequired = $finalHeadCheckpointRequired
            DestinationHeadCommitSha = $destinationHeadCommit
            SourceHeadTreeSha = $expectedHeadTree
            DestinationHeadTreeSha = $destinationHeadTree
            Checkpoints = $checkpointResults.ToArray()
            ReleaseTags = $releaseTagResults.ToArray()
            Checks = $checks.ToArray()
            IsSuccessful = -not ($checks | Where-Object { -not $_.Passed })
        }
    }
    finally {
        if (Test-Path -LiteralPath $workspacePath) {
            Remove-Item -LiteralPath $workspacePath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
