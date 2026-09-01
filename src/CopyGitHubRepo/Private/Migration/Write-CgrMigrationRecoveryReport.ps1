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
        $null
    }

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
