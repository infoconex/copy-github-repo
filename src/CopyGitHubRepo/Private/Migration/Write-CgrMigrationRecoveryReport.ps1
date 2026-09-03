function Write-CgrMigrationRecoveryReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Plan,

        [Parameter(Mandatory)]
        [psobject] $DestinationRepository,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $FailureStage,

        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord,

        [object[]] $CompletedSteps = @(),

        [psobject] $Provenance,

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
            ArchiveCustomDomainRelease = $null
            ReplacementCustomDomainClaim = $null
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

    $recoveryResult = [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.MigrationRecoveryResult'
        SchemaVersion = 1
        Status = 'FailedAfterDestinationCreation'
        RecordedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        SourceRepository = $Plan.SourceRepository
        DestinationRepository = $DestinationRepository.FullName
        DestinationHtmlUrl = $DestinationRepository.HtmlUrl
        SourceVisibility = $Plan.SourceVisibility
        DestinationVisibility = $Plan.DestinationVisibility
        ContentMode = $Plan.ContentMode
        BranchName = $Plan.SourceDefaultBranch
        FailureStage = $FailureStage
        LastCompletedStep = $lastCompletedStep
        ErrorId = $ErrorRecord.FullyQualifiedErrorId
        ErrorMessage = $ErrorRecord.Exception.Message
        CompletedSteps = @($CompletedSteps)
        Pages = $pagesRecovery
        CustomDomainHandoff = $customDomainHandoff
        Provenance = $Provenance
        Recovery = [pscustomobject] @{
            DestinationWasCreated = $true
            AutomaticDeletionAttempted = $false
            SourceRepositoryMutated = $false
            AutomaticRollbackAttempted = $false
            RecommendedActions = @(
                'Preserve the destination until the failure is understood.'
                'Inspect the destination repository and the completed steps recorded in this report.'
                'Inspect Pages recovery evidence before attempting any manual Pages change.'
                'If custom-domain handoff began, inspect CustomDomainHandoff before attempting any manual ownership change.'
                'Run Test-GitHubRepositoryMigration when a destination branch exists to determine whether the snapshot is already valid.'
                'Do not rerun the same migration against the existing destination; the tool intentionally rejects overwriting repositories.'
                'If retrying from scratch is appropriate, delete the destination manually only after confirming that deletion is intentional, then rerun the migration.'
            )
        }
    }

    $recoveryResult |
        ConvertTo-Json -Depth 30 |
        Set-Content -Path $reportPath -Encoding utf8NoBOM

    return [System.IO.Path]::GetFullPath($reportPath)
}
