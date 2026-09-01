function Restore-CgrGitHubPagesConfiguration {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Called only from the approved post-verification orchestration after the public command mutation gate.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $Plan,
        [Parameter(Mandatory)] [psobject] $SourceRepository,
        [Parameter(Mandatory)] [psobject] $DestinationRepository,
        [System.Collections.IList] $CompletedSteps,
        [ref] $FailureStage,
        [ValidateNotNullOrEmpty()] [string] $HostName = 'github.com'
    )

    $pages = Assert-CgrGitHubPagesPlanEvidence -Plan $Plan -SourceRepository $SourceRepository -HostName $HostName
    $configured = [bool] (Get-CgrObjectProperty -InputObject $pages -Name 'Configured')
    $existing = Get-CgrGitHubApiOptional -Path "repos/$($DestinationRepository.FullName)/pages" -HostName $HostName
    if (-not $configured) {
        if ($null -ne $existing) {
            $exception = [System.InvalidOperationException]::new("Destination '$($DestinationRepository.FullName)' unexpectedly has GitHub Pages configured even though the reviewed source did not. The destination was left unchanged.")
            throw [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationPagesUnexpectedlyConfigured', [System.Management.Automation.ErrorCategory]::InvalidResult, $DestinationRepository.FullName)
        }
        if ($FailureStage) { $FailureStage.Value = 'ReleasePagesActivationGuard' }
        Enable-CgrPagesWorkflowActivationAfterRestore -DestinationRepository $DestinationRepository -HostName $HostName
        return [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.PagesRestoreResult'; Repository = $DestinationRepository.FullName
            Status = 'ReviewedNotConfigured'; Configured = $false; Restored = $false; Verified = $true
            GuardReleased = $true; CustomDomainStatus = 'NotApplicable'; IsSuccessful = $true; IsComplete = $true
        }
    }
    if ($null -ne $existing) {
        $exception = [System.InvalidOperationException]::new("Destination '$($DestinationRepository.FullName)' already has GitHub Pages configured before the reviewed restoration stage. Refusing to overwrite unreviewed Pages state.")
        throw [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationPagesAlreadyConfigured', [System.Management.Automation.ErrorCategory]::ResourceExists, $DestinationRepository.FullName)
    }

    Assert-CgrDestinationPagesSource -DestinationRepository $DestinationRepository -Pages $pages -HostName $HostName
    $customDomain = Get-CgrObjectProperty -InputObject $pages -Name 'CustomDomain'
    $buildType = Get-CgrObjectProperty -InputObject $pages -Name 'BuildType'
    $createBody = @{ build_type = $buildType }
    if ($buildType -eq 'legacy') {
        $source = Get-CgrObjectProperty -InputObject $pages -Name 'Source'
        $createBody.source = @{ branch = Get-CgrObjectProperty -InputObject $source -Name 'Branch'; path = Get-CgrObjectProperty -InputObject $source -Name 'Path' }
    }
    elseif ($buildType -ne 'workflow') {
        $exception = [System.InvalidOperationException]::new("Reviewed Pages build type '$buildType' is unsupported for restoration.")
        throw [System.Management.Automation.ErrorRecord]::new($exception, 'ApprovedPagesBuildTypeUnsupported', [System.Management.Automation.ErrorCategory]::NotImplemented, $buildType)
    }

    $mode = [string] (Get-CgrObjectProperty -InputObject $Plan -Name 'Mode')
    $replacementMode = $mode -in @('SameNameReplacement', 'ExistingDestinationReplacement')
    $handoffRequired = $replacementMode -and -not [string]::IsNullOrWhiteSpace([string] $customDomain)
    $handoff = $null
    trap {
        if ($null -ne $handoff) {
            $errorId = if ([string]::IsNullOrWhiteSpace([string] $_.FullyQualifiedErrorId)) { 'PagesCustomDomainHandoffFailed' } else { ([string] $_.FullyQualifiedErrorId -split ',')[0] }
            $category = if ($null -ne $_.CategoryInfo) { $_.CategoryInfo.Category } else { [System.Management.Automation.ErrorCategory]::OperationStopped }
            throw [System.Management.Automation.ErrorRecord]::new($_.Exception, $errorId, $category, $handoff)
        }
        throw
    }

    if ($handoffRequired) {
        if ($FailureStage) { $FailureStage.Value = 'ValidatePagesCustomDomainHandoff' }
        $archiveName = [string] (Get-CgrObjectProperty -InputObject $Plan -Name 'ArchiveRepository')
        if ([string]::IsNullOrWhiteSpace($archiveName)) {
            $exception = [System.InvalidOperationException]::new('Replacement custom-domain handoff requires the reviewed archive repository identity.')
            throw [System.Management.Automation.ErrorRecord]::new($exception, 'PagesCustomDomainArchiveIdentityMissing', [System.Management.Automation.ErrorCategory]::InvalidData, $customDomain)
        }

        $archive = Get-CgrRepository -Repository $archiveName -HostName $HostName
        $replacement = Get-CgrRepository -Repository $DestinationRepository.FullName -HostName $HostName
        $archiveId = Get-CgrObjectProperty -InputObject $archive -Name 'Id'
        $replacementId = Get-CgrObjectProperty -InputObject $replacement -Name 'Id'
        if ($null -eq $archiveId -or $null -eq $replacementId -or [long] $archiveId -eq [long] $replacementId) {
            $exception = [System.InvalidOperationException]::new('Archive/replacement immutable repository identity could not be proven before custom-domain handoff.')
            throw [System.Management.Automation.ErrorRecord]::new($exception, 'PagesCustomDomainRepositoryIdentityInvalid', [System.Management.Automation.ErrorCategory]::InvalidResult, $archiveName)
        }

        if ($mode -eq 'SameNameReplacement') {
            $sourceState = Get-CgrObjectProperty -InputObject $Plan -Name 'SourceState'
            $reviewedSourceId = Get-CgrObjectProperty -InputObject $sourceState -Name 'RepositoryId'
            if ($null -ne $reviewedSourceId -and [long] $archiveId -ne [long] $reviewedSourceId) {
                $exception = [System.InvalidOperationException]::new("Archive repository '$archiveName' no longer has the reviewed source repository identity. The custom domain was not released.")
                throw [System.Management.Automation.ErrorRecord]::new($exception, 'PagesCustomDomainArchiveIdentityMismatch', [System.Management.Automation.ErrorCategory]::InvalidResult, $archiveName)
            }
        }

        $archivePages = Get-CgrGitHubApiOptional -Path "repos/$($archive.FullName)/pages" -HostName $HostName
        $archiveDomain = if ($archivePages) { Get-CgrObjectProperty -InputObject $archivePages -Name 'cname' } else { $null }
        $archiveReleaseRequired = [string] $archiveDomain -ceq [string] $customDomain
        if ($mode -eq 'SameNameReplacement' -and -not $archiveReleaseRequired) {
            $exception = [System.InvalidOperationException]::new("The preserved archive does not currently own the exact reviewed custom domain '$customDomain'. Ownership state is ambiguous, so no domain was released or claimed.")
            throw [System.Management.Automation.ErrorRecord]::new($exception, 'PagesCustomDomainArchiveBindingMismatch', [System.Management.Automation.ErrorCategory]::InvalidResult, $customDomain)
        }

        $handoff = [pscustomobject] @{
            ReviewedCustomDomain = [string] $customDomain
            ArchiveRepository = $archive.FullName
            ArchiveRepositoryId = [long] $archiveId
            ReplacementRepository = $replacement.FullName
            ReplacementRepositoryId = [long] $replacementId
            ArchiveObservedCustomDomain = $archiveDomain
            ArchiveReleaseRequired = $archiveReleaseRequired
            ArchiveReleaseAttempted = $false
            ArchiveReleaseSucceeded = -not $archiveReleaseRequired
            ReplacementClaimAttempted = $false
            ReplacementClaimSucceeded = $false
            ReplacementReadBackSucceeded = $false
            HttpsIntent = Get-CgrObjectProperty -InputObject $pages -Name 'HttpsEnforced'
            ExternalReadiness = Get-CgrObjectProperty -InputObject $pages -Name 'ExternalReadiness'
            DnsMutationAttempted = $false
            AutomaticRollbackAttempted = $false
        }
        if ($CompletedSteps) {
            $CompletedSteps.Add([pscustomobject] @{
                    Order = $CompletedSteps.Count + 1
                    Name = 'ValidatePagesCustomDomainHandoff'
                    MutatedGitHub = $false
                    Verified = $true
                    CustomDomainHandoff = $handoff
                })
        }

        if ($archiveReleaseRequired) {
            if ($FailureStage) { $FailureStage.Value = 'ReleaseArchivedPagesCustomDomain' }
            $releaseStep = [pscustomobject] @{
                Order = if ($CompletedSteps) { $CompletedSteps.Count + 1 } else { 0 }
                Name = 'ReleaseArchivedPagesCustomDomain'
                MutatedGitHub = $true
                Verified = $false
                ReviewedCustomDomain = [string] $customDomain
                ArchiveRepository = $archive.FullName
                ArchiveRepositoryId = [long] $archiveId
                Attempted = $true
                Succeeded = $false
            }
            if ($CompletedSteps) { $CompletedSteps.Add($releaseStep) }
            $handoff.ArchiveReleaseAttempted = $true
            Invoke-CgrGitHubApiMutation -Method PUT -Path "/repos/$($archive.FullName)/pages" -Body @{ cname = $null } -HostName $HostName | Out-Null
            $archiveReadBack = Get-CgrGitHubApiOptional -Path "repos/$($archive.FullName)/pages" -HostName $HostName
            $archiveReadBackDomain = if ($archiveReadBack) { Get-CgrObjectProperty -InputObject $archiveReadBack -Name 'cname' } else { $null }
            if (-not [string]::IsNullOrWhiteSpace([string] $archiveReadBackDomain)) {
                $exception = [System.InvalidOperationException]::new("Archive '$($archive.FullName)' still reports custom domain '$archiveReadBackDomain' after the reviewed release operation. Replacement claim was not attempted.")
                throw [System.Management.Automation.ErrorRecord]::new($exception, 'PagesCustomDomainArchiveReleaseVerificationFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $handoff)
            }
            $handoff.ArchiveReleaseSucceeded = $true
            $releaseStep.Succeeded = $true
            $releaseStep.Verified = $true
        }
    }

    if ($FailureStage) { $FailureStage.Value = 'CreateReplacementGitHubPages' }
    Invoke-CgrGitHubApiMutation -Method POST -Path "/repos/$($DestinationRepository.FullName)/pages" -Body $createBody -HostName $HostName | Out-Null

    $updateBody = @{}
    if (-not [string]::IsNullOrWhiteSpace([string] $customDomain)) { $updateBody.cname = [string] $customDomain }
    $httpsEnforced = Get-CgrObjectProperty -InputObject $pages -Name 'HttpsEnforced'
    if ($null -ne $httpsEnforced) { $updateBody.https_enforced = [bool] $httpsEnforced }
    if ($updateBody.Count -gt 0) {
        $claimStep = $null
        if ($handoffRequired) {
            if ($FailureStage) { $FailureStage.Value = 'ClaimReplacementPagesCustomDomain' }
            $handoff.ReplacementClaimAttempted = $true
            $claimStep = [pscustomobject] @{
                Order = if ($CompletedSteps) { $CompletedSteps.Count + 1 } else { 0 }
                Name = 'ClaimReplacementPagesCustomDomain'
                MutatedGitHub = $true
                Verified = $false
                ReviewedCustomDomain = [string] $customDomain
                ReplacementRepository = $DestinationRepository.FullName
                Attempted = $true
                Succeeded = $false
                AutomaticRollbackAttempted = $false
            }
            if ($CompletedSteps) { $CompletedSteps.Add($claimStep) }
        }
        Invoke-CgrGitHubApiMutation -Method PUT -Path "/repos/$($DestinationRepository.FullName)/pages" -Body $updateBody -HostName $HostName | Out-Null
        if ($handoffRequired) {
            $handoff.ReplacementClaimSucceeded = $true
            $claimStep.Succeeded = $true
        }
    }

    if ($FailureStage) { $FailureStage.Value = if ($handoffRequired) { 'VerifyReplacementPagesCustomDomain' } else { 'VerifyReplacementGitHubPages' } }
    $verifyDomain = -not [string]::IsNullOrWhiteSpace([string] $customDomain)
    $readBack = Assert-CgrDestinationPagesReadBack -DestinationRepository $DestinationRepository -Pages $pages -VerifyCustomDomain:$verifyDomain -HostName $HostName
    if ($handoffRequired) {
        $handoff.ReplacementReadBackSucceeded = $true
        if ($claimStep) { $claimStep.Verified = $true }
        $archiveFinal = Get-CgrGitHubApiOptional -Path "repos/$archiveName/pages" -HostName $HostName
        $archiveFinalDomain = if ($archiveFinal) { Get-CgrObjectProperty -InputObject $archiveFinal -Name 'cname' } else { $null }
        if ([string] $archiveFinalDomain -ceq [string] $customDomain) {
            $exception = [System.InvalidOperationException]::new("Archive '$archiveName' still owns the reviewed production custom domain after replacement verification.")
            throw [System.Management.Automation.ErrorRecord]::new($exception, 'PagesCustomDomainHandoffVerificationFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $handoff)
        }
    }

    if ($FailureStage) { $FailureStage.Value = 'ReleasePagesActivationGuard' }
    Enable-CgrPagesWorkflowActivationAfterRestore -DestinationRepository $DestinationRepository -HostName $HostName
    return [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.PagesRestoreResult'; Repository = $DestinationRepository.FullName
        Status = 'Restored'; Configured = $true; BuildType = $buildType; Source = Get-CgrObjectProperty -InputObject $pages -Name 'Source'
        CustomDomain = $customDomain; HttpsEnforced = $httpsEnforced; Restored = $true; Verified = $true; GuardReleased = $true
        CustomDomainStatus = if ($verifyDomain) { if ($handoffRequired) { 'HandedOff' } else { 'Restored' } } else { 'NotConfigured' }
        CustomDomainHandoff = $handoff
        ExternalReadiness = Get-CgrObjectProperty -InputObject $pages -Name 'ExternalReadiness'
        DnsMigrated = $false
        ReadBack = $readBack; IsSuccessful = $true; IsComplete = $true
    }
}
