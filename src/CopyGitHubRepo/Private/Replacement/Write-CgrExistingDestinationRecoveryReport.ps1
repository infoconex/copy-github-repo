function Write-CgrExistingDestinationRecoveryReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Plan,

        [Nullable[long]] $OriginalDestinationRepositoryId,

        [string] $OriginalDestinationRepositoryNodeId,

        [AllowNull()]
        [psobject] $ArchiveRepository,

        [AllowNull()]
        [psobject] $DestinationRepository,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $FailureStage,

        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord,

        [object[]] $CompletedSteps = @(),

        [psobject] $ReleasePreservation,

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

    $archiveRepositoryId = if ($ArchiveRepository) { Get-CgrObjectProperty -InputObject $ArchiveRepository -Name 'Id' } else { $null }
    $archiveRepositoryNodeId = if ($ArchiveRepository) { Get-CgrObjectProperty -InputObject $ArchiveRepository -Name 'NodeId' } else { $null }
    $replacementRepositoryId = if ($DestinationRepository) { Get-CgrObjectProperty -InputObject $DestinationRepository -Name 'Id' } else { $null }
    $replacementRepositoryNodeId = if ($DestinationRepository) { Get-CgrObjectProperty -InputObject $DestinationRepository -Name 'NodeId' } else { $null }
    $archiveIdentityPreserved = $null -ne $archiveRepositoryId -and $null -ne $OriginalDestinationRepositoryId -and $archiveRepositoryId -eq $OriginalDestinationRepositoryId
    $replacementDistinct = $null -ne $replacementRepositoryId -and $null -ne $OriginalDestinationRepositoryId -and $replacementRepositoryId -ne $OriginalDestinationRepositoryId
    $lastCompletedStep = @($CompletedSteps | Sort-Object Order | Select-Object -Last 1)
    if ($lastCompletedStep.Count -eq 0) { $lastCompletedStep = $null } else { $lastCompletedStep = $lastCompletedStep[0] }
    $customDomainHandoff = if ($ErrorRecord.TargetObject -and -not [string]::IsNullOrWhiteSpace([string] (Get-CgrObjectProperty -InputObject $ErrorRecord.TargetObject -Name 'ReviewedCustomDomain'))) {
        $ErrorRecord.TargetObject
    }
    else {
        $handoffStep = @($CompletedSteps | Where-Object { $_.PSObject.Properties['CustomDomainHandoff'] } | Select-Object -Last 1)
        if ($handoffStep.Count -gt 0) { $handoffStep[0].CustomDomainHandoff } else { $null }
    }

    $recoveryResult = [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.ExistingDestinationRecoveryResult'
        SchemaVersion = 1
        Status = 'ExistingDestinationReplacementFailed'
        RecordedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        SourceRepository = $Plan.SourceRepository
        OriginalDestinationRepository = $Plan.DestinationRepository
        OriginalDestinationRepositoryId = $OriginalDestinationRepositoryId
        OriginalDestinationRepositoryNodeId = $OriginalDestinationRepositoryNodeId
        DestinationRepository = $Plan.DestinationRepository
        ArchiveRepository = if ($ArchiveRepository) { $ArchiveRepository.FullName } else { $Plan.ArchiveRepository }
        ArchiveRepositoryId = $archiveRepositoryId
        ArchiveRepositoryNodeId = $archiveRepositoryNodeId
        ArchivedOriginalIdentityPreserved = $archiveIdentityPreserved
        ReplacementRepository = if ($DestinationRepository) { $DestinationRepository.FullName } else { $null }
        ReplacementRepositoryId = $replacementRepositoryId
        ReplacementRepositoryNodeId = $replacementRepositoryNodeId
        ReplacementHasDistinctIdentity = $replacementDistinct
        ContentMode = $Plan.ContentMode
        FailureStage = $FailureStage
        LastCompletedStep = $lastCompletedStep
        ErrorId = $ErrorRecord.FullyQualifiedErrorId
        ErrorMessage = $ErrorRecord.Exception.Message
        CompletedSteps = @($CompletedSteps)
        CustomDomainHandoff = $customDomainHandoff
        ReleasePreservation = $ReleasePreservation
        Recovery = [pscustomobject] @{
            ExistingDestinationWasDeleted = $false
            ExistingDestinationPreservedAsArchive = [bool] $ArchiveRepository
            ArchivedOriginalIdentityPreserved = $archiveIdentityPreserved
            ArchiveRepository = if ($ArchiveRepository) { $ArchiveRepository.FullName } else { $Plan.ArchiveRepository }
            ReplacementWasCreated = [bool] $DestinationRepository
            ReplacementHasDistinctIdentity = $replacementDistinct
            AutomaticDeletionAttempted = $false
            AutomaticRollbackAttempted = $false
            RecommendedActions = @(
                'Do not delete the archived repository until the replacement migration is verified.'
                'Inspect the failure stage, immutable repository identities, and completed steps recorded in this report.'
                'If custom-domain handoff began, inspect CustomDomainHandoff before attempting any manual ownership change.'
                'If a replacement repository was created, inspect and verify it before deciding whether to retry.'
                'The previous destination remains preserved under the archive repository name after a successful verified rename.'
            )
        }
    }

    $recoveryResult |
        ConvertTo-Json -Depth 30 |
        Set-Content -Path $reportPath -Encoding utf8NoBOM

    return [System.IO.Path]::GetFullPath($reportPath)
}
