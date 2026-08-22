function Write-CgrSameNameRecoveryReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Plan,

        [Nullable[long]] $SourceRepositoryId,

        [psobject] $ArchiveRepository,

        [psobject] $DestinationRepository,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $FailureStage,

        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord,

        [object[]] $CompletedSteps = @(),

        [string] $SourceCommitSha,

        [string] $SourceTreeSha,

        [string] $DestinationRootCommitSha,

        [string] $DestinationTreeSha,

        [Nullable[int]] $SourceFullHistoryRefCount,

        [Nullable[int]] $SourceReachableCommitCount,

        [string] $PreferredReportPath
    )

    $reportPath = if (-not [string]::IsNullOrWhiteSpace($PreferredReportPath)) {
        "$PreferredReportPath.recovery.json"
    }
    else {
        $safeDestinationName = $Plan.DestinationRepository -replace '[^A-Za-z0-9_.-]', '-'
        $timestamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
        Join-Path (Join-Path (Get-Location) '.copy-github-repo/recovery') "$safeDestinationName-$timestamp.json"
    }

    $resolvedParent = Split-Path -Parent $reportPath
    if (-not [string]::IsNullOrWhiteSpace($resolvedParent)) {
        New-Item -Path $resolvedParent -ItemType Directory -Force | Out-Null
    }

    $sourceWasArchived = $null -ne $ArchiveRepository
    $destinationWasCreated = $null -ne $DestinationRepository
    $archiveRepositoryId = if ($ArchiveRepository) { Get-CgrObjectProperty -InputObject $ArchiveRepository -Name 'Id' } else { $null }
    $destinationRepositoryId = if ($DestinationRepository) { Get-CgrObjectProperty -InputObject $DestinationRepository -Name 'Id' } else { $null }
    $status = if ($destinationWasCreated) {
        'FailedAfterReplacementCreation'
    }
    elseif ($sourceWasArchived) {
        'FailedAfterSourceArchive'
    }
    else {
        'FailedDuringSameNamePreparation'
    }

    $provenance = if ($Plan.ContentMode -eq 'Snapshot') {
        [pscustomobject] @{
            ContentMode = 'Snapshot'
            SourceRepository = $Plan.SourceRepository
            SourceRepositoryId = $SourceRepositoryId
            SourceCommitSha = $SourceCommitSha
            SourceTreeSha = $SourceTreeSha
            ArchiveRepository = if ($ArchiveRepository) { $ArchiveRepository.FullName } else { $Plan.ArchiveRepository }
            ArchiveRepositoryId = $archiveRepositoryId
            DestinationRepository = $Plan.DestinationRepository
            DestinationRepositoryId = $destinationRepositoryId
            DestinationRootCommitSha = $DestinationRootCommitSha
            DestinationTreeSha = $DestinationTreeSha
        }
    }
    else {
        $null
    }

    $recoveryResult = [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.SameNameRecoveryResult'
        SchemaVersion = 1
        Status = $status
        RecordedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        SourceRepository = $Plan.SourceRepository
        SourceRepositoryId = $SourceRepositoryId
        ArchiveRepository = if ($ArchiveRepository) { $ArchiveRepository.FullName } else { $Plan.ArchiveRepository }
        ArchiveRepositoryId = if ($null -eq $archiveRepositoryId) { $null } else { [long] $archiveRepositoryId }
        ArchiveHtmlUrl = if ($ArchiveRepository) { $ArchiveRepository.HtmlUrl } else { $null }
        DestinationRepository = $Plan.DestinationRepository
        DestinationRepositoryId = if ($null -eq $destinationRepositoryId) { $null } else { [long] $destinationRepositoryId }
        DestinationHtmlUrl = if ($DestinationRepository) { $DestinationRepository.HtmlUrl } else { $null }
        SourceVisibility = $Plan.SourceVisibility
        DestinationVisibility = $Plan.DestinationVisibility
        ContentMode = $Plan.ContentMode
        BranchName = $Plan.SourceDefaultBranch
        SourceCommitSha = $SourceCommitSha
        SourceTreeSha = $SourceTreeSha
        DestinationRootCommitSha = $DestinationRootCommitSha
        DestinationTreeSha = $DestinationTreeSha
        SourceFullHistoryRefCount = $SourceFullHistoryRefCount
        SourceReachableCommitCount = $SourceReachableCommitCount
        Provenance = $provenance
        FailureStage = $FailureStage
        ErrorId = $ErrorRecord.FullyQualifiedErrorId
        ErrorMessage = $ErrorRecord.Exception.Message
        CompletedSteps = @($CompletedSteps)
        Recovery = [pscustomobject] @{
            SourceRepositoryMutated = $sourceWasArchived
            SourceWasArchived = $sourceWasArchived
            DestinationWasCreated = $destinationWasCreated
            AutomaticRollbackAttempted = $false
            AutomaticDeletionAttempted = $false
            RecommendedActions = @(
                'Do not delete or rename the archive until the failure is understood.'
                'Inspect the archive and replacement repositories named in this report before taking corrective action.'
                'If the replacement exists, run Test-GitHubRepositoryMigration with the recorded content mode before deciding whether another migration attempt is necessary.'
                'Do not rely on the original repository URL to reach the archive after the replacement name is reused.'
                'Perform any rollback, rename, or deletion manually only after verifying the current repository state.'
            )
        }
    }

    $recoveryResult |
        ConvertTo-Json -Depth 30 |
        Set-Content -Path $reportPath -Encoding utf8NoBOM

    return [System.IO.Path]::GetFullPath($reportPath)
}
