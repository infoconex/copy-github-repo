function Format-CgrMigrationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [psobject] $Plan,

        [Parameter(Mandatory)]
        [ValidateSet('Markdown', 'Json')]
        [string] $Format
    )

    process {
        if ($Format -eq 'Json') {
            return $Plan | ConvertTo-Json -Depth 20
        }

        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add('# GitHub Repository Copy Plan')
        $lines.Add('')
        $lines.Add('| Field | Value |')
        $lines.Add('| --- | --- |')
        $lines.Add("| Source | $($Plan.SourceRepository) |")
        $lines.Add("| Destination | $($Plan.DestinationRepository) |")
        $lines.Add("| Archive | $(if ($Plan.ArchiveRepository) { $Plan.ArchiveRepository } else { 'N/A' }) |")
        $lines.Add("| Mode | $($Plan.Mode) |")
        $lines.Add("| Content mode | $($Plan.ContentMode) |")
        $lines.Add("| Source visibility | $($Plan.SourceVisibility) |")
        $lines.Add("| Destination visibility | $($Plan.DestinationVisibility) |")
        $lines.Add("| Restore Pages | $($Plan.RestorePages) |")
        $lines.Add("| Enable Actions after copy | $($Plan.EnableActionsAfterMigration) |")
        $lines.Add("| Skip settings | $($Plan.SkipSettings) |")
        $lines.Add("| Plan only | $($Plan.PlanOnly) |")

        $sourceState = Get-CgrObjectProperty -InputObject $Plan -Name 'SourceState'
        if ($sourceState) {
            $lines.Add('')
            $lines.Add('## Approved Source State')
            $lines.Add('')
            $lines.Add('This immutable source fingerprint is the state approved by this plan. Execution fails closed if the source no longer matches it before mutation.')
            $lines.Add('')
            $lines.Add('| Field | Value |')
            $lines.Add('| --- | --- |')
            $lines.Add("| Repository | $(Get-CgrObjectProperty -InputObject $sourceState -Name 'Repository') |")
            $lines.Add("| Repository ID | $(Get-CgrObjectProperty -InputObject $sourceState -Name 'RepositoryId') |")
            $lines.Add("| Repository node ID | $(Get-CgrObjectProperty -InputObject $sourceState -Name 'RepositoryNodeId') |")
            $lines.Add("| Default branch | $(Get-CgrObjectProperty -InputObject $sourceState -Name 'DefaultBranch') |")
            $capturedAtUtc = Get-CgrObjectProperty -InputObject $sourceState -Name 'CapturedAtUtc'
            if ($capturedAtUtc) { $lines.Add("| Captured at UTC | $capturedAtUtc |") }

            if ($Plan.ContentMode -eq 'Snapshot') {
                $lines.Add("| Approved commit SHA | $(Get-CgrObjectProperty -InputObject $sourceState -Name 'CommitSha') |")
                $lines.Add("| Approved tree SHA | $(Get-CgrObjectProperty -InputObject $sourceState -Name 'TreeSha') |")
                $pointerFiles = @(Get-CgrObjectProperty -InputObject $sourceState -Name 'GitLfsPointerFiles')
                $lines.Add("| Git LFS pointer files | $($pointerFiles.Count) |")
                $lines.Add("| Required Git LFS objects available | $(Get-CgrObjectProperty -InputObject $sourceState -Name 'GitLfsObjectsAvailable') |")

                $historicalRecords = Get-CgrObjectProperty -InputObject $sourceState -Name 'HistoricalRecords'
                if ($historicalRecords) {
                    $tagCount = Get-CgrObjectProperty -InputObject $historicalRecords -Name 'TagCount'
                    $releaseCount = Get-CgrObjectProperty -InputObject $historicalRecords -Name 'ReleaseCount'
                    $tagCountSuffix = if (Get-CgrObjectProperty -InputObject $historicalRecords -Name 'TagCountMayBeTruncated') { '+' } else { '' }
                    $releaseCountSuffix = if (Get-CgrObjectProperty -InputObject $historicalRecords -Name 'ReleaseCountMayBeTruncated') { '+' } else { '' }
                    $lines.Add('')
                    $lines.Add('## Historical Tags and Releases')
                    $lines.Add('')
                    $lines.Add('| Record | Source | Snapshot behavior |')
                    $lines.Add('| --- | ---: | --- |')
                    $tagBehavior = if ($Plan.Mode -eq 'SameNameReplacement') { 'Not copied; retained by the archived original repository.' } else { 'Not copied to the clean destination.' }
                    $releaseBehavior = if ($Plan.Mode -eq 'SameNameReplacement') { 'Not copied; retained by the archived original repository.' } else { 'Not copied to the clean destination.' }
                    $lines.Add("| Git tags | $tagCount$tagCountSuffix | $tagBehavior |")
                    $lines.Add("| GitHub Releases | $releaseCount$releaseCountSuffix | $releaseBehavior |")

                    $tagNames = @(Get-CgrObjectProperty -InputObject $historicalRecords -Name 'TagNames')
                    if ($tagNames.Count -gt 0) {
                        $lines.Add('')
                        $lines.Add("Observed source tags: $($tagNames -join ', ')")
                    }

                    $versionLikeTags = @(Get-CgrObjectProperty -InputObject $historicalRecords -Name 'VersionLikeTagNames')
                    if ($versionLikeTags.Count -gt 0) {
                        $lines.Add('')
                        $lines.Add("Release-like source tags detected: $($versionLikeTags -join ', ')")
                    }

                    if ($Plan.Mode -eq 'SameNameReplacement' -and ($tagCount -gt 0 -or $releaseCount -gt 0)) {
                        $lines.Add('')
                        $lines.Add('**Release safety:** create the new release tag and GitHub Release on the clean replacement only after Snapshot publication and verification complete successfully.')
                    }
                }
            }
            else {
                $refs = @(Get-CgrObjectProperty -InputObject $sourceState -Name 'Refs')
                $branchTrees = @(Get-CgrObjectProperty -InputObject $sourceState -Name 'BranchTrees')
                $lines.Add("| Approved branch/tag refs | $($refs.Count) |")
                $lines.Add("| Reachable commit count | $(Get-CgrObjectProperty -InputObject $sourceState -Name 'ReachableCommitCount') |")
                $lines.Add("| Branch-tip trees | $($branchTrees.Count) |")
                $lines.Add("| Reachable Git LFS objects available | $(Get-CgrObjectProperty -InputObject $sourceState -Name 'GitLfsObjectsAvailable') |")
            }
        }

        $lines.Add('')
        $lines.Add('## Steps')
        $lines.Add('')
        $lines.Add('| Order | Step | Mutates GitHub | Description |')
        $lines.Add('| ---: | --- | --- | --- |')

        foreach ($step in @($Plan.Steps)) {
            $description = ([string] $step.Description).Replace('|', '\|')
            $lines.Add("| $($step.Order) | $($step.Name) | $($step.MutatesGitHub) | $description |")
        }

        $lines.Add('')
        $lines.Add('This report is a dry-run repository copy plan. No GitHub repository was created, renamed, overwritten, or deleted.')

        return $lines -join [Environment]::NewLine
    }
}
