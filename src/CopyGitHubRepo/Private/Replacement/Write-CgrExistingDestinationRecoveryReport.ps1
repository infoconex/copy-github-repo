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

        [AllowNull()]
        [psobject] $SnapshotResult,

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

    # Snapshot provenance is split between the immutable reviewed plan and
    # evidence returned by the child migration. A failed child call might have
    # partially mutated GitHub without returning any observed destination state.
    # Never infer a copied commit or a destination tree from the source plan.
    $sourceState = Get-CgrObjectProperty -InputObject $Plan -Name 'SourceState'
    $snapshotEvidence = if ($Plan.ContentMode -eq 'Snapshot') {
        Get-CgrObjectProperty -InputObject $SnapshotResult -Name 'Provenance'
    }
    else { $null }
    $snapshotVerification = if ($Plan.ContentMode -eq 'Snapshot') {
        Get-CgrObjectProperty -InputObject $SnapshotResult -Name 'Verification'
    }
    else { $null }
    $verificationSuccessful = Get-CgrObjectProperty -InputObject $snapshotVerification -Name 'IsSuccessful'
    if ($null -eq $verificationSuccessful) {
        $verificationSuccessful = Get-CgrObjectProperty -InputObject $snapshotEvidence -Name 'VerificationSuccessful'
    }
    $destinationTree = Get-CgrObjectProperty -InputObject $snapshotVerification -Name 'DestinationTree'
    if ($null -eq $destinationTree) {
        $destinationTree = Get-CgrObjectProperty -InputObject $snapshotVerification -Name 'DestinationHeadTreeSha'
    }
    $sourceDefaultBranch = Get-CgrObjectProperty -InputObject $Plan -Name 'SourceDefaultBranch'
    if ([string]::IsNullOrWhiteSpace([string] $sourceDefaultBranch)) {
        $sourceDefaultBranch = Get-CgrObjectProperty -InputObject $sourceState -Name 'DefaultBranch'
    }
    $provenance = if ($Plan.ContentMode -eq 'Snapshot') {
        [pscustomobject] @{
            ContentMode = 'Snapshot'
            SourceRepository = $Plan.SourceRepository
            SourceRepositoryId = Get-CgrObjectProperty -InputObject $sourceState -Name 'RepositoryId'
            SourceRepositoryNodeId = Get-CgrObjectProperty -InputObject $sourceState -Name 'RepositoryNodeId'
            SourceDefaultBranch = $sourceDefaultBranch
            SourceCommitSha = Get-CgrObjectProperty -InputObject $sourceState -Name 'CommitSha'
            SourceTreeSha = Get-CgrObjectProperty -InputObject $sourceState -Name 'TreeSha'
            PlannedSourceState = $sourceState
            CopiedSourceCommitSha = Get-CgrObjectProperty -InputObject $snapshotEvidence -Name 'CopiedSourceCommitSha'
            CopiedSourceTreeSha = Get-CgrObjectProperty -InputObject $snapshotEvidence -Name 'CopiedSourceTreeSha'
            DestinationRepository = if ($DestinationRepository) { $DestinationRepository.FullName } else { $null }
            DestinationRepositoryId = $replacementRepositoryId
            DestinationRepositoryNodeId = $replacementRepositoryNodeId
            DestinationRootCommitSha = Get-CgrObjectProperty -InputObject $snapshotEvidence -Name 'DestinationRootCommitSha'
            DestinationTreeSha = $destinationTree
            VerificationSuccessful = $verificationSuccessful
            ActualEvidenceAvailable = $null -ne $snapshotEvidence -or $null -ne $snapshotVerification
            EvidenceLimitation = if ($null -eq $SnapshotResult) {
                'The child Snapshot migration did not return a result. Content may be partial; copied and verified destination state are unknown.'
            }
            elseif ($null -eq $snapshotEvidence) {
                'No child Snapshot provenance was returned. Do not infer copied commit or tree identities from the approved source.'
            }
            elseif ($null -eq $verificationSuccessful) {
                'The child did not report a Snapshot verification outcome. Copied identifiers alone do not prove destination equivalence.'
            }
            elseif ($verificationSuccessful -ne $true) {
                'Snapshot verification was not successful. Observed copied identities do not prove destination equivalence.'
            }
            elseif ([string]::IsNullOrWhiteSpace([string] $destinationTree)) {
                'No destination tree was returned by child verification; it is not inferred from the approved source tree.'
            }
            else { $null }
        }
    }
    else { $null }

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
        Provenance = $provenance
        FailureStage = $FailureStage
        LastCompletedStep = $lastCompletedStep
        ErrorId = $ErrorRecord.FullyQualifiedErrorId
        ErrorMessage = $ErrorRecord.Exception.Message
        CompletedSteps = @($CompletedSteps)
        Pages = $pagesRecovery
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
                'Inspect Pages recovery evidence before attempting any manual Pages change.'
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
