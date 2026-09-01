function Restore-CgrGitHubPagesConfiguration {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Called only from the approved post-verification orchestration after the public command mutation gate.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $Plan,
        [Parameter(Mandatory)] [psobject] $SourceRepository,
        [Parameter(Mandatory)] [psobject] $DestinationRepository,
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
    if ((Get-CgrObjectProperty -InputObject $Plan -Name 'Mode') -in @('SameNameReplacement', 'ExistingDestinationReplacement') -and
        -not [string]::IsNullOrWhiteSpace([string] $customDomain)) {
        $exception = [System.InvalidOperationException]::new('The reviewed Pages configuration uses a custom domain whose archive/replacement ownership handoff is owned by issue #96. No destination Pages mutation was performed.')
        throw [System.Management.Automation.ErrorRecord]::new($exception, 'PagesCustomDomainHandoffRequired', [System.Management.Automation.ErrorCategory]::NotImplemented, $customDomain)
    }

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
    Invoke-CgrGitHubApiMutation -Method POST -Path "/repos/$($DestinationRepository.FullName)/pages" -Body $createBody -HostName $HostName | Out-Null

    $updateBody = @{}
    if (-not [string]::IsNullOrWhiteSpace([string] $customDomain)) { $updateBody.cname = $customDomain }
    $httpsEnforced = Get-CgrObjectProperty -InputObject $pages -Name 'HttpsEnforced'
    if ($null -ne $httpsEnforced) { $updateBody.https_enforced = [bool] $httpsEnforced }
    if ($updateBody.Count -gt 0) {
        Invoke-CgrGitHubApiMutation -Method PUT -Path "/repos/$($DestinationRepository.FullName)/pages" -Body $updateBody -HostName $HostName | Out-Null
    }

    $verifyDomain = -not [string]::IsNullOrWhiteSpace([string] $customDomain)
    $readBack = Assert-CgrDestinationPagesReadBack -DestinationRepository $DestinationRepository -Pages $pages -VerifyCustomDomain:$verifyDomain -HostName $HostName
    Enable-CgrPagesWorkflowActivationAfterRestore -DestinationRepository $DestinationRepository -HostName $HostName
    return [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.PagesRestoreResult'; Repository = $DestinationRepository.FullName
        Status = 'Restored'; Configured = $true; BuildType = $buildType; Source = Get-CgrObjectProperty -InputObject $pages -Name 'Source'
        CustomDomain = $customDomain; HttpsEnforced = $httpsEnforced; Restored = $true; Verified = $true; GuardReleased = $true
        CustomDomainStatus = if ($verifyDomain) { 'Restored' } else { 'NotConfigured' }; ReadBack = $readBack; IsSuccessful = $true; IsComplete = $true
    }
}
