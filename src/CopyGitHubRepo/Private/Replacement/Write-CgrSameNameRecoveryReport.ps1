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

        [psobject] $ReleasePreservation,

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
    $lastCompletedStep = @($CompletedSteps | Sort-Object Order | Select-Object -Last 1)
    if ($lastCompletedStep.Count -eq 0) { $lastCompletedStep = $null } else { $lastCompletedStep = $lastCompletedStep[0] }
    $customDomainHandoff = if ($ErrorRecord.TargetObject -and -not [string]::IsNullOrWhiteSpace([string] (Get-CgrObjectProperty -InputObject $ErrorRecord.TargetObject -Name 'ReviewedCustomDomain'))) {
        $ErrorRecord.TargetObject
    }
    else {
        $handoffStep = @($CompletedSteps | Where-Object { $_.PSObject.Properties['CustomDomainHandoff'] } | Select-Object -Last 1)
        if ($handoffStep.Count -gt 0) { $handoffStep[0].CustomDomainHandoff } else { $null }
    }

    $reviewedPages = Get-CgrObjectProperty -InputObject $Plan -Name 'Pages'
    $createPagesStep = @($CompletedSteps | Where-Object { $_.Name -eq 'CreateReplacementGitHubPages' } | Select-Object -Last 1)
    $configurePagesStep = @($CompletedSteps | Where-Object { $_.Name -eq 'ConfigureReplacementGitHubPages' } | Select-Object -Last 1)
    $successfulPagesSteps = @($CompletedSteps | Where-Object {
            $_.Name -in @('VerifyReviewedNoPagesState', 'ValidatePagesCustomDomainHandoff', 'ReleaseArchivedPagesCustomDomain', 'CreateReplacementGitHubPages', 'ConfigureReplacementGitHubPages', 'ClaimReplacementPagesCustomDomain', 'RestoreGitHubPages') -and
            ((Get-CgrObjectProperty -InputObject $_ -Name 'Verified') -eq $true -or (Get-CgrObjectProperty -InputObject $_ -Name 'Succeeded') -eq $true)
        } | Sort-Object Order)
    $pagesApplied = [ordered] @{}
    if ($createPagesStep.Count -gt 0 -and [bool] (Get-CgrObjectProperty -InputObject $createPagesStep[0] -Name 'Succeeded')) {
        $applied = Get-CgrObjectProperty -InputObject $createPagesStep[0] -Name 'AppliedConfiguration'
        if ($applied) {
            $pagesApplied.BuildType = Get-CgrObjectProperty -InputObject $applied -Name 'BuildType'
            $source = Get-CgrObjectProperty -InputObject $applied -Name 'Source'
            if ($null -ne $source) { $pagesApplied.Source = $source }
        }
    }
    if ($configurePagesStep.Count -gt 0 -and [bool] (Get-CgrObjectProperty -InputObject $configurePagesStep[0] -Name 'Succeeded')) {
        $applied = Get-CgrObjectProperty -InputObject $configurePagesStep[0] -Name 'AppliedConfiguration'
        if ($applied) {
            $domain = Get-CgrObjectProperty -InputObject $applied -Name 'CustomDomain'
            $https = Get-CgrObjectProperty -InputObject $applied -Name 'HttpsEnforced'
            if (-not [string]::IsNullOrWhiteSpace([string] $domain)) { $pagesApplied.CustomDomain = $domain }
            if ($null -ne $https) { $pagesApplied.HttpsEnforced = [bool] $https }
        }
    }
    $archiveReleaseEvidence = if ($customDomainHandoff) {
        [pscustomobject] @{
            Repository = Get-CgrObjectProperty -InputObject $customDomainHandoff -Name 'ArchiveRepository'
            RepositoryId = Get-CgrObjectProperty -InputObject $customDomainHandoff -Name 'ArchiveRepositoryId'
            ReviewedCustomDomain = Get-CgrObjectProperty -InputObject $customDomainHandoff -Name 'ReviewedCustomDomain'
            Attempted = [bool] (Get-CgrObjectProperty -InputObject $customDomainHandoff -Name 'ArchiveReleaseAttempted')
            Succeeded = [bool] (Get-CgrObjectProperty -InputObject $customDomainHandoff -Name 'ArchiveReleaseSucceeded')
            KnownOwnsReviewedDomain = if ([bool] (Get-CgrObjectProperty -InputObject $customDomainHandoff -Name 'ArchiveReleaseSucceeded')) { $false } else { $null }
        }
    }
    else { $null }
    $replacementClaimEvidence = if ($customDomainHandoff) {
        [pscustomobject] @{
            Repository = Get-CgrObjectProperty -InputObject $customDomainHandoff -Name 'ReplacementRepository'
            RepositoryId = Get-CgrObjectProperty -InputObject $customDomainHandoff -Name 'ReplacementRepositoryId'
            ReviewedCustomDomain = Get-CgrObjectProperty -InputObject $customDomainHandoff -Name 'ReviewedCustomDomain'
            Attempted = [bool] (Get-CgrObjectProperty -InputObject $customDomainHandoff -Name 'ReplacementClaimAttempted')
            Succeeded = [bool] (Get-CgrObjectProperty -InputObject $customDomainHandoff -Name 'ReplacementClaimSucceeded')
            ReadBackSucceeded = [bool] (Get-CgrObjectProperty -InputObject $customDomainHandoff -Name 'ReplacementReadBackSucceeded')
            KnownOwnsReviewedDomain = if ([bool] (Get-CgrObjectProperty -InputObject $customDomainHandoff -Name 'ReplacementReadBackSucceeded')) { $true } else { $null }
        }
    }
    else { $null }
    $pagesRecovery = if ([bool] (Get-CgrObjectProperty -InputObject $Plan -Name 'RestorePages') -and $reviewedPages) {
        [pscustomobject] @{
            RestoreRequested = $true
            ReviewedConfiguration = [pscustomobject] @{
                Configured = [bool] (Get-CgrObjectProperty -InputObject $reviewedPages -Name 'Configured')
                BuildType = Get-CgrObjectProperty -InputObject $reviewedPages -Name 'BuildType'
                Source = Get-CgrObjectProperty -InputObject $reviewedPages -Name 'Source'
                CustomDomain = Get-CgrObjectProperty -InputObject $reviewedPages -Name 'CustomDomain'
                HttpsEnforced = Get-CgrObjectProperty -InputObject $reviewedPages -Name 'HttpsEnforced'
                Representability = Get-CgrObjectProperty -InputObject $reviewedPages -Name 'Representability'
            }
            DestinationMutationAttempted = [bool] ($createPagesStep.Count -gt 0 -or $configurePagesStep.Count -gt 0)
            DestinationCreationAttempted = [bool] ($createPagesStep.Count -gt 0)
            DestinationCreationSucceeded = [bool] ($createPagesStep.Count -gt 0 -and (Get-CgrObjectProperty -InputObject $createPagesStep[0] -Name 'Succeeded'))
            AppliedConfiguration = if ($pagesApplied.Count -gt 0) { [pscustomobject] $pagesApplied } else { $null }
            ArchiveCustomDomainRelease = $archiveReleaseEvidence
            ReplacementCustomDomainClaim = $replacementClaimEvidence
            LastSuccessfulStage = if ($successfulPagesSteps.Count -gt 0) { $successfulPagesSteps[-1].Name } else { $null }
            ExternalState = [pscustomobject] @{
                Ownership = 'ExternalNotMigrated'
                Readiness = Get-CgrObjectProperty -InputObject $reviewedPages -Name 'ExternalReadiness'
                Migrated = $false
            }
            DnsMutationAttempted = $false
            AutomaticRollbackAttempted = $false
        }
    }
    else { $null }

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
            ReleasePreservation = $ReleasePreservation
            Pages = $pagesRecovery
            CustomDomainHandoff = $customDomainHandoff
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
        Pages = $pagesRecovery
        CustomDomainHandoff = $customDomainHandoff
        FailureStage = $FailureStage
        LastCompletedStep = $lastCompletedStep
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
                'Inspect Pages recovery evidence before attempting any manual Pages change.'
                'If custom-domain handoff began, inspect CustomDomainHandoff before attempting any manual ownership change.'
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
