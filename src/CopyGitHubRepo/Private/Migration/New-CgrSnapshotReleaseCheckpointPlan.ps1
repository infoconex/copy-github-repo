function New-CgrSnapshotReleaseCheckpointPlan {
    <#
    .SYNOPSIS
    Builds immutable Snapshot release-checkpoint evidence from an approved release selection.

    .DESCRIPTION
    Consumes the already-resolved release selection, captures tag-reference and repository-tree
    evidence for each selected release, coalesces duplicate peeled commit targets, and derives
    the checkpoint sequence exclusively from Git ancestry. The helper is read-only and never
    re-runs release filtering or selection.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'This private helper captures read-only planning evidence and performs no mutation.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Repository,

        [Parameter(Mandatory)]
        [psobject] $ReleaseSelection,

        [Parameter(Mandatory)]
        [psobject] $SourceState,

        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com'
    )

    $releaseEvidence = [System.Collections.Generic.List[object]]::new()
    $selectedReleases = @($ReleaseSelection.Releases)
    $treeByCommit = @{}

    for ($selectionIndex = 0; $selectionIndex -lt $selectedReleases.Count; $selectionIndex++) {
        $release = $selectedReleases[$selectionIndex]
        $tagName = [string] $release.TagName
        $peeledCommitSha = [string] $release.TargetCommitSha

        $tagRefResult = Invoke-CgrGitHubApiReadRequest `
            -ArgumentList @('api', '--hostname', $HostName, "repos/$($Repository.FullName)/git/ref/tags/$([uri]::EscapeDataString($tagName))")
        if ($tagRefResult.ExitCode -ne 0) {
            $diagnostic = Protect-CgrDiagnosticText -Text ([string] $tagRefResult.ErrorText)
            $message = "Selected release tag '$tagName' could not be read while building Snapshot checkpoint evidence. The tag may have been deleted or moved. $diagnostic"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'SnapshotReleaseCheckpointTagReadFailed',
                [System.Management.Automation.ErrorCategory]::ReadError,
                $tagName
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $tagRefJson = ($tagRefResult.Output | ForEach-Object { [string] $_ }) -join "`n"
        $tagRef = $tagRefJson | ConvertFrom-Json -Depth 20
        $tagObjectType = [string] $tagRef.object.type
        $tagObjectSha = [string] $tagRef.object.sha
        if ($tagObjectType -notin @('commit', 'tag') -or [string]::IsNullOrWhiteSpace($tagObjectSha)) {
            $message = "Selected release tag '$tagName' does not resolve through a supported lightweight or annotated Git tag reference."
            $exception = [System.InvalidOperationException]::new($message)
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'SnapshotReleaseCheckpointTagUnsupported',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $tagName
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        if (-not $treeByCommit.ContainsKey($peeledCommitSha)) {
            $treeResult = Invoke-CgrGitHubApiReadRequest `
                -ArgumentList @('api', '--hostname', $HostName, "repos/$($Repository.FullName)/commits/$peeledCommitSha", '--jq', '.commit.tree.sha')
            if ($treeResult.ExitCode -ne 0) {
                $diagnostic = Protect-CgrDiagnosticText -Text ([string] $treeResult.ErrorText)
                $message = "Selected release tag '$tagName' resolved to commit '$peeledCommitSha', but its repository tree could not be captured for Snapshot checkpoint planning. $diagnostic"
                $exception = [System.InvalidOperationException]::new($message.Trim())
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'SnapshotReleaseCheckpointTreeReadFailed',
                    [System.Management.Automation.ErrorCategory]::ReadError,
                    $peeledCommitSha
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            $treeSha = [string] @($treeResult.Output)[0]
            if ([string]::IsNullOrWhiteSpace($treeSha)) {
                $message = "Selected release commit '$peeledCommitSha' did not return a tree SHA required for immutable Snapshot checkpoint evidence."
                $exception = [System.InvalidOperationException]::new($message)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'SnapshotReleaseCheckpointTreeMissing',
                    [System.Management.Automation.ErrorCategory]::InvalidData,
                    $peeledCommitSha
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
            $treeByCommit[$peeledCommitSha] = $treeSha
        }

        $releaseEvidence.Add([pscustomobject] @{
                SelectionOrder = $selectionIndex + 1
                ReleaseId = $release.ReleaseId
                TagName = $tagName
                TagObjectType = $tagObjectType
                TagObjectSha = $tagObjectSha
                PeeledCommitSha = $peeledCommitSha
                TreeSha = [string] $treeByCommit[$peeledCommitSha]
            })
    }

    $distinctCommitShas = @($releaseEvidence.PeeledCommitSha | Select-Object -Unique)
    $ancestorCountByCommit = @{}
    foreach ($commitSha in $distinctCommitShas) {
        $ancestorCountByCommit[$commitSha] = 0
    }

    for ($leftIndex = 0; $leftIndex -lt $distinctCommitShas.Count; $leftIndex++) {
        for ($rightIndex = $leftIndex + 1; $rightIndex -lt $distinctCommitShas.Count; $rightIndex++) {
            $leftSha = [string] $distinctCommitShas[$leftIndex]
            $rightSha = [string] $distinctCommitShas[$rightIndex]
            $compareResult = Invoke-CgrGitHubApiReadRequest `
                -ArgumentList @('api', '--hostname', $HostName, "repos/$($Repository.FullName)/compare/$leftSha...$rightSha", '--jq', '.status')
            if ($compareResult.ExitCode -ne 0) {
                $diagnostic = Protect-CgrDiagnosticText -Text ([string] $compareResult.ErrorText)
                $message = "Git ancestry could not be compared for selected Snapshot release commits '$leftSha' and '$rightSha'. Planning cannot invent checkpoint order. $diagnostic"
                $exception = [System.InvalidOperationException]::new($message.Trim())
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'SnapshotReleaseCheckpointTopologyReadFailed',
                    [System.Management.Automation.ErrorCategory]::ReadError,
                    "$leftSha...$rightSha"
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            $status = [string] @($compareResult.Output)[0]
            switch ($status) {
                'ahead' { $ancestorCountByCommit[$rightSha] = [int] $ancestorCountByCommit[$rightSha] + 1 }
                'behind' { $ancestorCountByCommit[$leftSha] = [int] $ancestorCountByCommit[$leftSha] + 1 }
                default {
                    $leftTags = @($releaseEvidence | Where-Object PeeledCommitSha -EQ $leftSha | ForEach-Object TagName) -join ', '
                    $rightTags = @($releaseEvidence | Where-Object PeeledCommitSha -EQ $rightSha | ForEach-Object TagName) -join ', '
                    $message = "Selected Snapshot release topology is incompatible: '$leftTags' ($leftSha) and '$rightTags' ($rightSha) are not on one comparable ancestry chain (Git compare status '$status'). Narrow the release selection to one linear release line."
                    $exception = [System.InvalidOperationException]::new($message)
                    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                        $exception,
                        'SnapshotReleaseCheckpointTopologyIncompatible',
                        [System.Management.Automation.ErrorCategory]::InvalidData,
                        "$leftSha...$rightSha"
                    )
                    $PSCmdlet.ThrowTerminatingError($errorRecord)
                }
            }
        }
    }

    $orderedCommitShas = @($distinctCommitShas | Sort-Object -Property @{ Expression = { [int] $ancestorCountByCommit[[string] $_] }; Ascending = $true })
    $checkpoints = [System.Collections.Generic.List[object]]::new()
    for ($checkpointIndex = 0; $checkpointIndex -lt $orderedCommitShas.Count; $checkpointIndex++) {
        $commitSha = [string] $orderedCommitShas[$checkpointIndex]
        $boundaryReleases = @($releaseEvidence | Where-Object PeeledCommitSha -EQ $commitSha | Sort-Object SelectionOrder)
        $checkpoints.Add([pscustomobject] @{
                Order = $checkpointIndex + 1
                SourceCommitSha = $commitSha
                SourceTreeSha = [string] $treeByCommit[$commitSha]
                ReleaseIds = @($boundaryReleases.ReleaseId)
                TagNames = @($boundaryReleases.TagName)
                SelectionOrders = @($boundaryReleases.SelectionOrder)
            })
    }

    $finalHeadCheckpointRequired = $true
    if ($checkpoints.Count -gt 0) {
        $finalCheckpoint = $checkpoints[$checkpoints.Count - 1]
        $finalHeadCheckpointRequired = [string] $finalCheckpoint.SourceTreeSha -ne [string] $SourceState.TreeSha

        if ($finalHeadCheckpointRequired -and [string] $finalCheckpoint.SourceCommitSha -ne [string] $SourceState.CommitSha) {
            $headCompareResult = Invoke-CgrGitHubApiReadRequest `
                -ArgumentList @('api', '--hostname', $HostName, "repos/$($Repository.FullName)/compare/$($finalCheckpoint.SourceCommitSha)...$($SourceState.CommitSha)", '--jq', '.status')
            if ($headCompareResult.ExitCode -ne 0) {
                $diagnostic = Protect-CgrDiagnosticText -Text ([string] $headCompareResult.ErrorText)
                $message = "The final selected release commit '$($finalCheckpoint.SourceCommitSha)' could not be compared with reviewed default-branch HEAD '$($SourceState.CommitSha)'. Planning cannot safely append current HEAD state. $diagnostic"
                $exception = [System.InvalidOperationException]::new($message.Trim())
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'SnapshotReleaseCheckpointHeadTopologyReadFailed',
                    [System.Management.Automation.ErrorCategory]::ReadError,
                    $SourceState.CommitSha
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            $headStatus = [string] @($headCompareResult.Output)[0]
            if ($headStatus -ne 'ahead') {
                $message = "The final selected Snapshot release commit '$($finalCheckpoint.SourceCommitSha)' is not an ancestor of reviewed default-branch HEAD '$($SourceState.CommitSha)' (Git compare status '$headStatus'). Planning cannot fabricate a release-to-HEAD checkpoint progression."
                $exception = [System.InvalidOperationException]::new($message)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'SnapshotReleaseCheckpointHeadTopologyIncompatible',
                    [System.Management.Automation.ErrorCategory]::InvalidData,
                    $SourceState.CommitSha
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
        }
    }

    [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.SnapshotReleaseCheckpointPlan'
        SchemaVersion = 1
        Repository = $Repository.FullName
        SelectedReleaseCount = $selectedReleases.Count
        CheckpointCount = $checkpoints.Count
        PlannedSnapshotCommitCount = $checkpoints.Count + $(if ($finalHeadCheckpointRequired) { 1 } else { 0 })
        ReleaseEvidence = $releaseEvidence.ToArray()
        Checkpoints = $checkpoints.ToArray()
        SourceHead = [pscustomobject] @{
            DefaultBranch = $SourceState.DefaultBranch
            CommitSha = $SourceState.CommitSha
            TreeSha = $SourceState.TreeSha
        }
        FinalHeadCheckpointRequired = [bool] $finalHeadCheckpointRequired
    }
}
