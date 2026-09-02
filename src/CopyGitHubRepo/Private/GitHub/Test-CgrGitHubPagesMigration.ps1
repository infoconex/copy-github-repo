function Test-CgrGitHubPagesMigration {
    <#
    .SYNOPSIS
    Independently verifies restored GitHub Pages configuration.

    .DESCRIPTION
    Reads destination GitHub-side Pages state and compares it with immutable reviewed
    migration-plan evidence. External DNS, domain-verification, and certificate readiness
    are reported separately and never used as migration-selection authority.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $Plan,
        [Parameter(Mandatory)] [psobject] $DestinationRepository,
        [ValidateNotNullOrEmpty()] [string] $HostName = 'github.com'
    )

    $pages = Get-CgrObjectProperty -InputObject $Plan -Name 'Pages'
    if ($null -eq $pages) {
        $exception = [System.InvalidOperationException]::new('Pages verification requires immutable reviewed Pages evidence in the approved migration plan.')
        throw [System.Management.Automation.ErrorRecord]::new($exception, 'ApprovedPagesEvidenceMissing', [System.Management.Automation.ErrorCategory]::InvalidData, $Plan)
    }

    $expectedConfigured = [bool] (Get-CgrObjectProperty -InputObject $pages -Name 'Configured')
    $actual = Get-CgrGitHubApiOptional -Path "repos/$($DestinationRepository.FullName)/pages" -HostName $HostName
    $actualConfigured = $null -ne $actual
    $checks = [System.Collections.Generic.List[object]]::new()
    $checks.Add([pscustomobject] @{
            Name = 'PagesConfiguredMatches'
            Passed = $actualConfigured -eq $expectedConfigured
            Expected = $expectedConfigured
            Actual = $actualConfigured
        })

    $externalReadiness = if ($actualConfigured) {
        $protectedDomainState = Get-CgrObjectProperty -InputObject $actual -Name 'protected_domain_state'
        $pendingDomainUnverifiedAt = Get-CgrObjectProperty -InputObject $actual -Name 'pending_domain_unverified_at'
        $httpsCertificate = Get-CgrObjectProperty -InputObject $actual -Name 'https_certificate'
        [pscustomobject] @{
            DomainVerification = if ($null -ne $protectedDomainState) { [string] $protectedDomainState } elseif ($null -ne $pendingDomainUnverifiedAt) { 'Pending' } else { 'NotReportedByGitHub' }
            PendingDomainUnverifiedAt = $pendingDomainUnverifiedAt
            Certificate = if ($null -ne $httpsCertificate) { $httpsCertificate } else { 'NotReportedByGitHub' }
            Dns = 'ExternalNotQueried'
            AffectsConfigurationVerification = $false
        }
    }
    else {
        [pscustomobject] @{
            DomainVerification = 'NotApplicable'
            PendingDomainUnverifiedAt = $null
            Certificate = 'NotApplicable'
            Dns = 'ExternalNotQueried'
            AffectsConfigurationVerification = $false
        }
    }

    $httpsEnforcementStatus = 'NotReviewed'
    if ($expectedConfigured -and $actualConfigured) {
        $expectedBuildType = [string] (Get-CgrObjectProperty -InputObject $pages -Name 'BuildType')
        $actualBuildType = [string] (Get-CgrObjectProperty -InputObject $actual -Name 'build_type')
        $checks.Add([pscustomobject] @{
                Name = 'PagesBuildTypeMatches'
                Passed = $actualBuildType -ceq $expectedBuildType
                Expected = $expectedBuildType
                Actual = $actualBuildType
            })

        if ($expectedBuildType -eq 'legacy') {
            $expectedSource = Get-CgrObjectProperty -InputObject $pages -Name 'Source'
            $actualSource = Get-CgrObjectProperty -InputObject $actual -Name 'source'
            $expectedBranch = [string] (Get-CgrObjectProperty -InputObject $expectedSource -Name 'Branch')
            $expectedPath = [string] (Get-CgrObjectProperty -InputObject $expectedSource -Name 'Path')
            $actualBranch = [string] (Get-CgrObjectProperty -InputObject $actualSource -Name 'branch')
            $actualPath = [string] (Get-CgrObjectProperty -InputObject $actualSource -Name 'path')
            $checks.Add([pscustomobject] @{
                    Name = 'PagesSourceBranchMatches'
                    Passed = $actualBranch -ceq $expectedBranch
                    Expected = $expectedBranch
                    Actual = $actualBranch
                })
            $checks.Add([pscustomobject] @{
                    Name = 'PagesSourcePathMatches'
                    Passed = $actualPath -ceq $expectedPath
                    Expected = $expectedPath
                    Actual = $actualPath
                })
        }

        $expectedDomain = Get-CgrObjectProperty -InputObject $pages -Name 'CustomDomain'
        $actualDomain = Get-CgrObjectProperty -InputObject $actual -Name 'cname'
        $normalizedExpectedDomain = if ([string]::IsNullOrWhiteSpace([string] $expectedDomain)) { $null } else { [string] $expectedDomain }
        $normalizedActualDomain = if ([string]::IsNullOrWhiteSpace([string] $actualDomain)) { $null } else { [string] $actualDomain }
        $checks.Add([pscustomobject] @{
                Name = 'PagesCustomDomainMatches'
                Passed = [string] $normalizedActualDomain -ceq [string] $normalizedExpectedDomain
                Expected = $normalizedExpectedDomain
                Actual = $normalizedActualDomain
            })

        $expectedHttps = Get-CgrObjectProperty -InputObject $pages -Name 'HttpsEnforced'
        if ($null -ne $expectedHttps) {
            $actualHttps = Get-CgrObjectProperty -InputObject $actual -Name 'https_enforced'
            $httpsCertificate = Get-CgrObjectProperty -InputObject $actual -Name 'https_certificate'
            $httpsNotYetEnforced = $null -eq $actualHttps -or -not [bool] $actualHttps
            $httpsPendingCertificate = [bool] $expectedHttps -and $httpsNotYetEnforced -and $null -eq $httpsCertificate
            $httpsMatches = $null -ne $actualHttps -and [bool] $actualHttps -eq [bool] $expectedHttps
            $httpsEnforcementStatus = if ($httpsMatches) { 'Verified' } elseif ($httpsPendingCertificate) { 'PendingCertificate' } else { 'Mismatch' }
            $checks.Add([pscustomobject] @{
                    Name = 'PagesHttpsEnforcementMatches'
                    Passed = $httpsMatches -or $httpsPendingCertificate
                    Expected = [bool] $expectedHttps
                    Actual = if ($null -eq $actualHttps) { $null } else { [bool] $actualHttps }
                    Status = $httpsEnforcementStatus
                })
        }

        $mode = [string] (Get-CgrObjectProperty -InputObject $Plan -Name 'Mode')
        $replacementMode = $mode -in @('SameNameReplacement', 'ExistingDestinationReplacement')
        if ($replacementMode -and -not [string]::IsNullOrWhiteSpace([string] $normalizedExpectedDomain)) {
            $archiveName = [string] (Get-CgrObjectProperty -InputObject $Plan -Name 'ArchiveRepository')
            if ([string]::IsNullOrWhiteSpace($archiveName)) {
                $checks.Add([pscustomobject] @{
                        Name = 'PagesArchiveCustomDomainReleased'
                        Passed = $false
                        Expected = 'Reviewed archive repository identity'
                        Actual = $null
                    })
            }
            else {
                $archivePages = Get-CgrGitHubApiOptional -Path "repos/$archiveName/pages" -HostName $HostName
                $archiveDomain = if ($archivePages) { Get-CgrObjectProperty -InputObject $archivePages -Name 'cname' } else { $null }
                $archiveStillOwnsDomain = [string] $archiveDomain -ceq [string] $normalizedExpectedDomain
                $checks.Add([pscustomobject] @{
                        Name = 'PagesArchiveCustomDomainReleased'
                        Passed = -not $archiveStillOwnsDomain
                        Expected = $null
                        Actual = if ([string]::IsNullOrWhiteSpace([string] $archiveDomain)) { $null } else { [string] $archiveDomain }
                    })
                $checks.Add([pscustomobject] @{
                        Name = 'PagesReplacementCustomDomainOwned'
                        Passed = [string] $normalizedActualDomain -ceq [string] $normalizedExpectedDomain
                        Expected = $normalizedExpectedDomain
                        Actual = $normalizedActualDomain
                    })
            }
        }
    }

    $failedChecks = @($checks | Where-Object { -not $_.Passed })
    [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.GitHubPagesVerificationResult'
        SchemaVersion = 1
        Repository = $DestinationRepository.FullName
        ExpectedConfigured = $expectedConfigured
        ActualConfigured = $actualConfigured
        Status = if ($failedChecks.Count -eq 0) { if ($expectedConfigured) { 'Verified' } else { 'VerifiedNotConfigured' } } else { 'Mismatch' }
        Checks = @($checks)
        HttpsEnforcementStatus = $httpsEnforcementStatus
        ExternalReadiness = $externalReadiness
        DnsMigrated = $false
        IsSuccessful = $failedChecks.Count -eq 0
    }
}