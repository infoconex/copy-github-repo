function Test-CgrGitHubPagesDriftEvidenceMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $ReviewedEvidence,
        [Parameter(Mandatory)] [psobject] $CurrentEvidence
    )

    foreach ($name in @('Configured', 'BuildType', 'Branch', 'Path', 'CustomDomain', 'HttpsEnforced')) {
        if ((Get-CgrObjectProperty -InputObject $ReviewedEvidence -Name $name) -ne
            (Get-CgrObjectProperty -InputObject $CurrentEvidence -Name $name)) {
            return $false
        }
    }
    return $true
}

function Assert-CgrGitHubPagesPlanEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $Plan,
        [Parameter(Mandatory)] [psobject] $SourceRepository,
        [ValidateNotNullOrEmpty()] [string] $HostName = 'github.com'
    )

    $pages = Get-CgrObjectProperty -InputObject $Plan -Name 'Pages'
    if ($null -eq $pages) {
        $exception = [System.InvalidOperationException]::new('Pages restoration was requested, but the approved migration plan does not contain immutable Pages evidence.')
        throw [System.Management.Automation.ErrorRecord]::new($exception, 'ApprovedPagesEvidenceMissing', [System.Management.Automation.ErrorCategory]::InvalidData, $Plan)
    }

    $representability = Get-CgrObjectProperty -InputObject $pages -Name 'Representability'
    $isRepresentable = if ($representability) { Get-CgrObjectProperty -InputObject $representability -Name 'IsRepresentable' } else { $true }
    if ($null -eq $isRepresentable -and $representability) {
        $isRepresentable = Get-CgrObjectProperty -InputObject $representability -Name 'Representable'
    }
    if ($representability -and -not [bool] $isRepresentable) {
        $reason = Get-CgrObjectProperty -InputObject $representability -Name 'Reason'
        $exception = [System.InvalidOperationException]::new("The reviewed Pages configuration is not representable at the destination. $reason")
        throw [System.Management.Automation.ErrorRecord]::new($exception, 'ApprovedPagesConfigurationNotRepresentable', [System.Management.Automation.ErrorCategory]::InvalidData, $pages)
    }

    $current = Get-CgrGitHubPagesPlanEvidence -Repository $SourceRepository -ContentMode $Plan.ContentMode -SourceState $Plan.SourceState -HostName $HostName
    $reviewedDrift = Get-CgrObjectProperty -InputObject $pages -Name 'DriftEvidence'
    $currentDrift = Get-CgrObjectProperty -InputObject $current -Name 'DriftEvidence'
    if ($null -eq $reviewedDrift -or $null -eq $currentDrift -or
        -not (Test-CgrGitHubPagesDriftEvidenceMatch -ReviewedEvidence $reviewedDrift -CurrentEvidence $currentDrift)) {
        $exception = [System.InvalidOperationException]::new("GitHub Pages configuration for '$($SourceRepository.FullName)' changed after planning. No destination Pages mutation was performed.")
        throw [System.Management.Automation.ErrorRecord]::new($exception, 'PagesStateChangedSincePlanning', [System.Management.Automation.ErrorCategory]::InvalidData, $SourceRepository.FullName)
    }

    return $pages
}

function Assert-CgrDestinationPagesSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $DestinationRepository,
        [Parameter(Mandatory)] [psobject] $Pages,
        [ValidateNotNullOrEmpty()] [string] $HostName = 'github.com'
    )

    if ((Get-CgrObjectProperty -InputObject $Pages -Name 'BuildType') -ne 'legacy') { return }
    $source = Get-CgrObjectProperty -InputObject $Pages -Name 'Source'
    $branch = [string] (Get-CgrObjectProperty -InputObject $source -Name 'Branch')
    $path = [string] (Get-CgrObjectProperty -InputObject $source -Name 'Path')
    if ([string]::IsNullOrWhiteSpace($branch) -or $path -notin @('/', '/docs')) {
        $exception = [System.InvalidOperationException]::new('The reviewed branch/path Pages source is incomplete or unsupported.')
        throw [System.Management.Automation.ErrorRecord]::new($exception, 'ApprovedPagesSourceInvalid', [System.Management.Automation.ErrorCategory]::InvalidData, $source)
    }

    $encodedBranch = [Uri]::EscapeDataString($branch)
    if ($null -eq (Get-CgrGitHubApiOptional -Path "repos/$($DestinationRepository.FullName)/branches/$encodedBranch" -HostName $HostName)) {
        $exception = [System.InvalidOperationException]::new("The exact reviewed Pages publishing branch '$branch' does not exist at destination '$($DestinationRepository.FullName)'.")
        throw [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationPagesBranchMissing', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $branch)
    }
    if ($path -eq '/docs' -and
        $null -eq (Get-CgrGitHubApiOptional -Path "repos/$($DestinationRepository.FullName)/contents/docs?ref=$encodedBranch" -HostName $HostName)) {
        $exception = [System.InvalidOperationException]::new("The exact reviewed Pages publishing path '/docs' does not exist on destination branch '$branch'.")
        throw [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationPagesPathMissing', [System.Management.Automation.ErrorCategory]::ObjectNotFound, '/docs')
    }
}

function Assert-CgrDestinationPagesReadBack {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $DestinationRepository,
        [Parameter(Mandatory)] [psobject] $Pages,
        [switch] $VerifyCustomDomain,
        [ValidateNotNullOrEmpty()] [string] $HostName = 'github.com'
    )

    $actual = Get-CgrGitHubApiOptional -Path "repos/$($DestinationRepository.FullName)/pages" -HostName $HostName
    if ($null -eq $actual) {
        $exception = [System.InvalidOperationException]::new("GitHub Pages was not readable after restoration for '$($DestinationRepository.FullName)'.")
        throw [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationPagesVerificationFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $DestinationRepository.FullName)
    }

    $expectedBuildType = Get-CgrObjectProperty -InputObject $Pages -Name 'BuildType'
    if ((Get-CgrObjectProperty -InputObject $actual -Name 'build_type') -ne $expectedBuildType) {
        $exception = [System.InvalidOperationException]::new("Destination Pages build mode does not match the reviewed '$expectedBuildType' mode.")
        throw [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationPagesVerificationFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $actual)
    }
    if ($expectedBuildType -eq 'legacy') {
        $expectedSource = Get-CgrObjectProperty -InputObject $Pages -Name 'Source'
        $actualSource = Get-CgrObjectProperty -InputObject $actual -Name 'source'
        if ((Get-CgrObjectProperty -InputObject $actualSource -Name 'branch') -ne (Get-CgrObjectProperty -InputObject $expectedSource -Name 'Branch') -or
            (Get-CgrObjectProperty -InputObject $actualSource -Name 'path') -ne (Get-CgrObjectProperty -InputObject $expectedSource -Name 'Path')) {
            $exception = [System.InvalidOperationException]::new('Destination Pages branch/path does not match the exact reviewed source.')
            throw [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationPagesVerificationFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $actualSource)
        }
    }
    if ($VerifyCustomDomain -and
        (Get-CgrObjectProperty -InputObject $actual -Name 'cname') -ne (Get-CgrObjectProperty -InputObject $Pages -Name 'CustomDomain')) {
        $exception = [System.InvalidOperationException]::new('Destination Pages custom domain does not match the exact reviewed value.')
        throw [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationPagesVerificationFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $actual)
    }
    $expectedHttps = Get-CgrObjectProperty -InputObject $Pages -Name 'HttpsEnforced'
    if ($null -ne $expectedHttps -and
        [bool] (Get-CgrObjectProperty -InputObject $actual -Name 'https_enforced') -ne [bool] $expectedHttps) {
        $exception = [System.InvalidOperationException]::new('Destination Pages HTTPS-enforcement state does not match the reviewed intent.')
        throw [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationPagesVerificationFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $actual)
    }
    return $actual
}

function Enable-CgrPagesWorkflowActivationAfterRestore {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This releases the temporary Pages-specific guard after the public command mutation gate and successful Pages verification.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $DestinationRepository,
        [ValidateNotNullOrEmpty()] [string] $HostName = 'github.com'
    )

    Invoke-CgrGitHubApiMutation -Method PUT -Path "/repos/$($DestinationRepository.FullName)/actions/permissions" -Body @{ enabled = $true } -HostName $HostName | Out-Null
    $permissions = Get-CgrGitHubApi -Path "repos/$($DestinationRepository.FullName)/actions/permissions" -HostName $HostName
    if (-not [bool] (Get-CgrObjectProperty -InputObject $permissions -Name 'enabled')) {
        $exception = [System.InvalidOperationException]::new("The temporary Pages workflow activation guard could not be released for '$($DestinationRepository.FullName)'.")
        throw [System.Management.Automation.ErrorRecord]::new($exception, 'PagesWorkflowActivationGuardReleaseFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $DestinationRepository.FullName)
    }
}

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
