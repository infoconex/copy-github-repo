function Get-CgrGitHubPagesRecoveryEvidence {
    <#
    .SYNOPSIS
    Builds durable GitHub Pages recovery/provenance evidence from reviewed execution state.

    .DESCRIPTION
    Projects immutable Plan.Pages evidence and already-recorded execution steps into a
    recovery-safe Pages result. This function performs no GitHub discovery or mutation.
    GitHub-controlled transferable configuration is kept separate from external DNS,
    domain-verification, and certificate readiness evidence.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $Plan,
        [object[]] $CompletedSteps = @(),
        [psobject] $PagesResult,
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    $restoreRequested = [bool] (Get-CgrObjectProperty -InputObject $Plan -Name 'RestorePages')
    $reviewedPages = Get-CgrObjectProperty -InputObject $Plan -Name 'Pages'
    if (-not $restoreRequested -or $null -eq $reviewedPages) {
        return [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.GitHubPagesRecoveryEvidence'
            SchemaVersion = 1
            RestoreRequested = $restoreRequested
            ReviewedConfiguration = $null
            DestinationMutationAttempted = $false
            DestinationCreationAttempted = $false
            DestinationCreationSucceeded = $false
            AppliedConfiguration = $null
            ArchiveCustomDomainRelease = $null
            ReplacementCustomDomainClaim = $null
            LastSuccessfulStage = $null
            ExternalState = $null
            DnsMutationAttempted = $false
            AutomaticRollbackAttempted = $false
        }
    }

    $transferable = [pscustomobject] @{
        Configured = [bool] (Get-CgrObjectProperty -InputObject $reviewedPages -Name 'Configured')
        BuildType = Get-CgrObjectProperty -InputObject $reviewedPages -Name 'BuildType'
        Source = Get-CgrObjectProperty -InputObject $reviewedPages -Name 'Source'
        CustomDomain = Get-CgrObjectProperty -InputObject $reviewedPages -Name 'CustomDomain'
        HttpsEnforced = Get-CgrObjectProperty -InputObject $reviewedPages -Name 'HttpsEnforced'
        Representability = Get-CgrObjectProperty -InputObject $reviewedPages -Name 'Representability'
    }
    $external = Get-CgrObjectProperty -InputObject $reviewedPages -Name 'ExternalReadiness'

    $creationStep = @($CompletedSteps | Where-Object { $_.Name -eq 'CreateReplacementGitHubPages' } | Select-Object -Last 1)
    $configurationStep = @($CompletedSteps | Where-Object { $_.Name -eq 'ConfigureReplacementGitHubPages' } | Select-Object -Last 1)
    $handoffStep = @($CompletedSteps | Where-Object { $_.PSObject.Properties['CustomDomainHandoff'] } | Select-Object -Last 1)
    $handoff = if ($handoffStep.Count -gt 0) { $handoffStep[0].CustomDomainHandoff } else { $null }
    if ($null -eq $handoff -and $ErrorRecord -and $ErrorRecord.TargetObject -and
        -not [string]::IsNullOrWhiteSpace([string] (Get-CgrObjectProperty -InputObject $ErrorRecord.TargetObject -Name 'ReviewedCustomDomain'))) {
        $handoff = $ErrorRecord.TargetObject
    }
    if ($null -eq $handoff -and $PagesResult) {
        $handoff = Get-CgrObjectProperty -InputObject $PagesResult -Name 'CustomDomainHandoff'
    }

    $applied = [ordered] @{}
    if ($creationStep.Count -gt 0 -and [bool] (Get-CgrObjectProperty -InputObject $creationStep[0] -Name 'Succeeded')) {
        $applied.BuildType = $transferable.BuildType
        if ($null -ne $transferable.Source) { $applied.Source = $transferable.Source }
    }
    if ($configurationStep.Count -gt 0 -and [bool] (Get-CgrObjectProperty -InputObject $configurationStep[0] -Name 'Succeeded')) {
        if (-not [string]::IsNullOrWhiteSpace([string] $transferable.CustomDomain)) { $applied.CustomDomain = $transferable.CustomDomain }
        if ($null -ne $transferable.HttpsEnforced) { $applied.HttpsEnforced = [bool] $transferable.HttpsEnforced }
    }
    if ($PagesResult -and [bool] (Get-CgrObjectProperty -InputObject $PagesResult -Name 'Restored')) {
        $applied.BuildType = $transferable.BuildType
        if ($null -ne $transferable.Source) { $applied.Source = $transferable.Source }
        if (-not [string]::IsNullOrWhiteSpace([string] $transferable.CustomDomain)) { $applied.CustomDomain = $transferable.CustomDomain }
        if ($null -ne $transferable.HttpsEnforced) { $applied.HttpsEnforced = [bool] $transferable.HttpsEnforced }
    }

    $successfulStages = @($CompletedSteps | Where-Object {
            $_.Name -in @('ValidatePagesCustomDomainHandoff', 'ReleaseArchivedPagesCustomDomain', 'CreateReplacementGitHubPages', 'ConfigureReplacementGitHubPages', 'ClaimReplacementPagesCustomDomain', 'RestoreGitHubPages') -and
            ((Get-CgrObjectProperty -InputObject $_ -Name 'Verified') -eq $true -or (Get-CgrObjectProperty -InputObject $_ -Name 'Succeeded') -eq $true)
        } | Sort-Object Order)
    $lastSuccessfulStage = if ($successfulStages.Count -gt 0) { $successfulStages[-1].Name } else { $null }

    $archiveRelease = if ($handoff) {
        [pscustomobject] @{
            Repository = Get-CgrObjectProperty -InputObject $handoff -Name 'ArchiveRepository'
            RepositoryId = Get-CgrObjectProperty -InputObject $handoff -Name 'ArchiveRepositoryId'
            ReviewedCustomDomain = Get-CgrObjectProperty -InputObject $handoff -Name 'ReviewedCustomDomain'
            Attempted = [bool] (Get-CgrObjectProperty -InputObject $handoff -Name 'ArchiveReleaseAttempted')
            Succeeded = [bool] (Get-CgrObjectProperty -InputObject $handoff -Name 'ArchiveReleaseSucceeded')
            KnownOwnsReviewedDomain = if ([bool] (Get-CgrObjectProperty -InputObject $handoff -Name 'ArchiveReleaseSucceeded')) { $false } else { $null }
        }
    }
    else { $null }

    $replacementClaim = if ($handoff) {
        [pscustomobject] @{
            Repository = Get-CgrObjectProperty -InputObject $handoff -Name 'ReplacementRepository'
            RepositoryId = Get-CgrObjectProperty -InputObject $handoff -Name 'ReplacementRepositoryId'
            ReviewedCustomDomain = Get-CgrObjectProperty -InputObject $handoff -Name 'ReviewedCustomDomain'
            Attempted = [bool] (Get-CgrObjectProperty -InputObject $handoff -Name 'ReplacementClaimAttempted')
            Succeeded = [bool] (Get-CgrObjectProperty -InputObject $handoff -Name 'ReplacementClaimSucceeded')
            ReadBackSucceeded = [bool] (Get-CgrObjectProperty -InputObject $handoff -Name 'ReplacementReadBackSucceeded')
            KnownOwnsReviewedDomain = if ([bool] (Get-CgrObjectProperty -InputObject $handoff -Name 'ReplacementReadBackSucceeded')) { $true } else { $null }
        }
    }
    else { $null }

    [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.GitHubPagesRecoveryEvidence'
        SchemaVersion = 1
        RestoreRequested = $true
        ReviewedConfiguration = $transferable
        DestinationMutationAttempted = [bool] ($creationStep.Count -gt 0 -or $configurationStep.Count -gt 0 -or ($PagesResult -and (Get-CgrObjectProperty -InputObject $PagesResult -Name 'Restored')))
        DestinationCreationAttempted = [bool] ($creationStep.Count -gt 0)
        DestinationCreationSucceeded = [bool] ($creationStep.Count -gt 0 -and (Get-CgrObjectProperty -InputObject $creationStep[0] -Name 'Succeeded'))
        AppliedConfiguration = if ($applied.Count -gt 0) { [pscustomobject] $applied } else { $null }
        ArchiveCustomDomainRelease = $archiveRelease
        ReplacementCustomDomainClaim = $replacementClaim
        LastSuccessfulStage = $lastSuccessfulStage
        ExternalState = [pscustomobject] @{
            Ownership = 'ExternalNotMigrated'
            Dns = Get-CgrObjectProperty -InputObject $external -Name 'Dns'
            DomainVerification = Get-CgrObjectProperty -InputObject $external -Name 'DomainVerification'
            Certificate = Get-CgrObjectProperty -InputObject $external -Name 'Certificate'
            Migrated = $false
        }
        DnsMutationAttempted = $false
        AutomaticRollbackAttempted = $false
    }
}
