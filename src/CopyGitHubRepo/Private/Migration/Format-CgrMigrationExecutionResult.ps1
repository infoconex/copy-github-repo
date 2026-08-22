function Format-CgrMigrationExecutionResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [psobject] $Result,
        [Parameter(Mandatory)] [ValidateSet('Markdown', 'Json')] [string] $Format
    )

    process {
        if ($Format -eq 'Json') { return $Result | ConvertTo-Json -Depth 30 }

        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add('# GitHub Repository Copy Report')
        $lines.Add('')
        $lines.Add('| Field | Value |')
        $lines.Add('| --- | --- |')
        $lines.Add("| Status | $($Result.Status) |")
        $lines.Add("| Source | $($Result.SourceRepository) |")
        $lines.Add("| Destination | $($Result.DestinationRepository) |")
        $lines.Add("| Source visibility | $($Result.SourceVisibility) |")
        $lines.Add("| Destination visibility | $($Result.DestinationVisibility) |")
        $lines.Add("| Destination URL | $($Result.DestinationHtmlUrl) |")
        $lines.Add("| Destination branch | $($Result.DestinationBranch) |")
        $lines.Add("| Snapshot commit | $($Result.SnapshotCommitSha) |")
        $lines.Add("| Verified | $($Result.IsVerified) |")
        $lines.Add("| Settings restored | $($Result.SettingsRestored) |")
        if ($null -ne $Result.PSObject.Properties['ProtectionRestored']) {
            $lines.Add("| Protection restoration successful | $($Result.ProtectionRestored) |")
        }

        $plannedSourceState = Get-CgrObjectProperty -InputObject $Result -Name 'PlannedSourceState'
        if (-not $plannedSourceState) {
            $plan = Get-CgrObjectProperty -InputObject $Result -Name 'Plan'
            if ($plan) { $plannedSourceState = Get-CgrObjectProperty -InputObject $plan -Name 'SourceState' }
        }
        if ($plannedSourceState) {
            $lines.Add('')
            $lines.Add('## Approved Source State')
            $lines.Add('')
            $lines.Add('This is the immutable source fingerprint approved by the reviewed repository copy plan.')
            $lines.Add('')
            $lines.Add('| Field | Value |')
            $lines.Add('| --- | --- |')
            $lines.Add("| Repository | $(Get-CgrObjectProperty -InputObject $plannedSourceState -Name 'Repository') |")
            $lines.Add("| Repository ID | $(Get-CgrObjectProperty -InputObject $plannedSourceState -Name 'RepositoryId') |")
            $lines.Add("| Repository node ID | $(Get-CgrObjectProperty -InputObject $plannedSourceState -Name 'RepositoryNodeId') |")
            $lines.Add("| Content mode | $(Get-CgrObjectProperty -InputObject $plannedSourceState -Name 'ContentMode') |")
            $lines.Add("| Default branch | $(Get-CgrObjectProperty -InputObject $plannedSourceState -Name 'DefaultBranch') |")
            $capturedAtUtc = Get-CgrObjectProperty -InputObject $plannedSourceState -Name 'CapturedAtUtc'
            if ($capturedAtUtc) { $lines.Add("| Captured at UTC | $capturedAtUtc |") }

            if ((Get-CgrObjectProperty -InputObject $plannedSourceState -Name 'ContentMode') -eq 'FullHistory') {
                $refs = @(Get-CgrObjectProperty -InputObject $plannedSourceState -Name 'Refs')
                $branchTrees = @(Get-CgrObjectProperty -InputObject $plannedSourceState -Name 'BranchTrees')
                $lines.Add("| Approved branch/tag refs | $($refs.Count) |")
                $lines.Add("| Reachable commit count | $(Get-CgrObjectProperty -InputObject $plannedSourceState -Name 'ReachableCommitCount') |")
                $lines.Add("| Branch-tip trees | $($branchTrees.Count) |")
                $lines.Add("| Reachable Git LFS objects available | $(Get-CgrObjectProperty -InputObject $plannedSourceState -Name 'GitLfsObjectsAvailable') |")
            }
            else {
                $lines.Add("| Approved commit SHA | $(Get-CgrObjectProperty -InputObject $plannedSourceState -Name 'CommitSha') |")
                $lines.Add("| Approved tree SHA | $(Get-CgrObjectProperty -InputObject $plannedSourceState -Name 'TreeSha') |")
                $pointerFiles = @(Get-CgrObjectProperty -InputObject $plannedSourceState -Name 'GitLfsPointerFiles')
                $lines.Add("| Git LFS pointer files | $($pointerFiles.Count) |")
                $lines.Add("| Required Git LFS objects available | $(Get-CgrObjectProperty -InputObject $plannedSourceState -Name 'GitLfsObjectsAvailable') |")
            }
        }

        $replacementRepositoryId = Get-CgrObjectProperty -InputObject $Result -Name 'ReplacementDestinationRepositoryId'
        if ($null -ne $replacementRepositoryId) {
            $lines.Add('')
            $lines.Add('## Replacement Identity Evidence')
            $lines.Add('')
            $lines.Add('| Field | Value |')
            $lines.Add('| --- | --- |')
            $originalRepository = Get-CgrObjectProperty -InputObject $Result -Name 'OriginalRepository'
            if (-not $originalRepository) {
                $originalRepository = Get-CgrObjectProperty -InputObject $Result -Name 'OriginalDestinationRepository'
            }
            $originalRepositoryId = Get-CgrObjectProperty -InputObject $Result -Name 'OriginalRepositoryId'
            if ($null -eq $originalRepositoryId) {
                $originalRepositoryId = Get-CgrObjectProperty -InputObject $Result -Name 'OriginalDestinationRepositoryId'
            }
            $originalRepositoryNodeId = Get-CgrObjectProperty -InputObject $Result -Name 'OriginalRepositoryNodeId'
            if ($null -eq $originalRepositoryNodeId) {
                $originalRepositoryNodeId = Get-CgrObjectProperty -InputObject $Result -Name 'OriginalDestinationRepositoryNodeId'
            }
            $lines.Add("| Original repository | $originalRepository |")
            $lines.Add("| Original repository ID | $originalRepositoryId |")
            $lines.Add("| Original repository node ID | $originalRepositoryNodeId |")
            $lines.Add("| Archive repository | $(Get-CgrObjectProperty -InputObject $Result -Name 'ArchiveRepository') |")
            $lines.Add("| Archive repository ID | $(Get-CgrObjectProperty -InputObject $Result -Name 'ArchiveRepositoryId') |")
            $lines.Add("| Archive repository node ID | $(Get-CgrObjectProperty -InputObject $Result -Name 'ArchiveRepositoryNodeId') |")
            $lines.Add("| Archived original identity preserved | $(Get-CgrObjectProperty -InputObject $Result -Name 'ArchivedOriginalIdentityPreserved') |")
            $lines.Add("| Replacement repository | $(Get-CgrObjectProperty -InputObject $Result -Name 'ReplacementDestinationRepository') |")
            $lines.Add("| Replacement repository ID | $replacementRepositoryId |")
            $lines.Add("| Replacement repository node ID | $(Get-CgrObjectProperty -InputObject $Result -Name 'ReplacementDestinationRepositoryNodeId') |")
            $lines.Add("| Replacement has distinct identity | $(Get-CgrObjectProperty -InputObject $Result -Name 'ReplacementHasDistinctIdentity') |")
        }

        $provenance = Get-CgrObjectProperty -InputObject $Result -Name 'Provenance'
        if ($provenance) {
            $lines.Add('')
            $lines.Add('## Publication Provenance')
            $lines.Add('')
            $lines.Add('| Field | Value |')
            $lines.Add('| --- | --- |')
            $lines.Add("| Recorded at UTC | $(Get-CgrObjectProperty -InputObject $provenance -Name 'RecordedAtUtc') |")
            $lines.Add("| Content mode | $(Get-CgrObjectProperty -InputObject $provenance -Name 'ContentMode') |")
            $lines.Add("| Source repository | $(Get-CgrObjectProperty -InputObject $provenance -Name 'SourceRepository') |")
            $lines.Add("| Source repository ID | $(Get-CgrObjectProperty -InputObject $provenance -Name 'SourceRepositoryId') |")
            $lines.Add("| Source repository node ID | $(Get-CgrObjectProperty -InputObject $provenance -Name 'SourceRepositoryNodeId') |")
            $lines.Add("| Source default branch | $(Get-CgrObjectProperty -InputObject $provenance -Name 'SourceDefaultBranch') |")
            $lines.Add("| Source commit SHA | $(Get-CgrObjectProperty -InputObject $provenance -Name 'SourceCommitSha') |")
            $lines.Add("| Source tree SHA | $(Get-CgrObjectProperty -InputObject $provenance -Name 'SourceTreeSha') |")
            $archiveRepository = Get-CgrObjectProperty -InputObject $provenance -Name 'ArchiveRepository'
            if ($archiveRepository) {
                $lines.Add("| Archive repository | $archiveRepository |")
                $lines.Add("| Archive repository ID | $(Get-CgrObjectProperty -InputObject $provenance -Name 'ArchiveRepositoryId') |")
                $lines.Add("| Archive repository node ID | $(Get-CgrObjectProperty -InputObject $provenance -Name 'ArchiveRepositoryNodeId') |")
            }
            $lines.Add("| Destination repository | $(Get-CgrObjectProperty -InputObject $provenance -Name 'DestinationRepository') |")
            $lines.Add("| Destination repository ID | $(Get-CgrObjectProperty -InputObject $provenance -Name 'DestinationRepositoryId') |")
            $lines.Add("| Destination repository node ID | $(Get-CgrObjectProperty -InputObject $provenance -Name 'DestinationRepositoryNodeId') |")
            $lines.Add("| Destination root commit SHA | $(Get-CgrObjectProperty -InputObject $provenance -Name 'DestinationRootCommitSha') |")
            $lines.Add("| Destination tree SHA | $(Get-CgrObjectProperty -InputObject $provenance -Name 'DestinationTreeSha') |")
            $lines.Add("| Verification successful | $(Get-CgrObjectProperty -InputObject $provenance -Name 'VerificationSuccessful') |")
        }

        $lines.Add('')
        $lines.Add('## Completed Steps')
        $lines.Add('')
        $lines.Add('| Order | Step | Mutated GitHub | Verified |')
        $lines.Add('| ---: | --- | --- | --- |')
        foreach ($step in @($Result.CompletedSteps)) { $lines.Add("| $($step.Order) | $($step.Name) | $($step.MutatedGitHub) | $($step.Verified) |") }

        if ($Result.Verification) {
            $lines.Add(''); $lines.Add('## Verification Checks'); $lines.Add('')
            $lines.Add('| Check | Passed | Expected | Actual |'); $lines.Add('| --- | --- | --- | --- |')
            foreach ($check in @($Result.Verification.Checks)) {
                $expected = ([string] $check.Expected).Replace('|', '\|')
                $actual = ([string] $check.Actual).Replace('|', '\|')
                $lines.Add("| $($check.Name) | $($check.Passed) | $expected | $actual |")
            }
        }

        if ($Result.Settings) {
            $lines.Add(''); $lines.Add('## Settings'); $lines.Add('')
            $lines.Add('| Setting | Status | Value |'); $lines.Add('| --- | --- | --- |')
            foreach ($setting in @($Result.Settings.Restored)) {
                $value = ([string] $setting.Value).Replace('|', '\|')
                $lines.Add("| $($setting.Name) | $($setting.Status) | $value |")
            }
            foreach ($setting in @($Result.Settings.Skipped)) { $lines.Add("| $setting | Skipped |  |") }
            foreach ($setting in @($Result.Settings.Unsupported)) { $lines.Add("| $setting | Unsupported |  |") }
        }

        $protection = Get-CgrObjectProperty -InputObject $Result -Name 'Protection'
        if ($protection) {
            $lines.Add(''); $lines.Add('## Repository Protection'); $lines.Add('')
            $lines.Add('| Kind | Name | Status | Detail |'); $lines.Add('| --- | --- | --- | --- |')
            foreach ($item in @(Get-CgrObjectProperty -InputObject $protection -Name 'Restored')) {
                $lines.Add("| $($item.Kind) | $($item.Name) | Restored | verified |")
            }
            foreach ($item in @(Get-CgrObjectProperty -InputObject $protection -Name 'Skipped')) {
                if ($item -is [string]) { $lines.Add("| Protection |  | Skipped | $item |") }
                else { $lines.Add("| $($item.Kind) | $($item.Name) | Skipped | $($item.Reason) |") }
            }
        }

        return $lines -join [Environment]::NewLine
    }
}
