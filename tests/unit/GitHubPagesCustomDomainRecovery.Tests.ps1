BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1') -Force
}

Describe 'GitHub Pages custom-domain recovery evidence' {
    It 'serializes partial handoff evidence for same-name replacement without claiming rollback' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'
                DestinationRepository = 'acme/source'
                ArchiveRepository = 'acme/source-archive'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                ContentMode = 'Snapshot'
                SourceDefaultBranch = 'main'
            }
            $handoff = [pscustomobject] @{
                ReviewedCustomDomain = 'www.example.com'
                ArchiveRepository = 'acme/source-archive'
                ArchiveRepositoryId = 10
                ReplacementRepository = 'acme/source'
                ReplacementRepositoryId = 20
                ArchiveReleaseAttempted = $true
                ArchiveReleaseSucceeded = $true
                ReplacementClaimAttempted = $true
                ReplacementClaimSucceeded = $false
                ReplacementReadBackSucceeded = $false
                HttpsIntent = $true
                ExternalReadiness = [pscustomobject] @{ Dns = 'ExternalNotQueried'; Certificate = 'Pending' }
                DnsMutationAttempted = $false
                AutomaticRollbackAttempted = $false
            }
            $steps = @(
                [pscustomobject] @{ Order = 1; Name = 'ValidatePagesCustomDomainHandoff'; MutatedGitHub = $false; Verified = $true; CustomDomainHandoff = $handoff },
                [pscustomobject] @{ Order = 2; Name = 'ReleaseArchivedPagesCustomDomain'; MutatedGitHub = $true; Verified = $true; Succeeded = $true },
                [pscustomobject] @{ Order = 3; Name = 'ClaimReplacementPagesCustomDomain'; MutatedGitHub = $true; Verified = $false; Succeeded = $false }
            )
            $exception = [System.InvalidOperationException]::new('replacement claim failed')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'PagesCustomDomainClaimFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $handoff)
            $archive = [pscustomobject] @{ FullName = 'acme/source-archive'; Id = 10; HtmlUrl = 'https://example.test/acme/source-archive' }
            $destination = [pscustomobject] @{ FullName = 'acme/source'; Id = 20; HtmlUrl = 'https://example.test/acme/source' }
            $reportBase = Join-Path $TestDrive 'same-name-pages.json'

            $path = Write-CgrSameNameRecoveryReport -Plan $plan -SourceRepositoryId 10 -ArchiveRepository $archive -DestinationRepository $destination -FailureStage 'ClaimReplacementPagesCustomDomain' -ErrorRecord $errorRecord -CompletedSteps $steps -PreferredReportPath $reportBase
            $report = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 30

            $report.FailureStage | Should -Be 'ClaimReplacementPagesCustomDomain'
            $report.ArchiveRepositoryId | Should -Be 10
            $report.DestinationRepositoryId | Should -Be 20
            $report.CustomDomainHandoff.ReviewedCustomDomain | Should -BeExactly 'www.example.com'
            $report.CustomDomainHandoff.ArchiveReleaseSucceeded | Should -BeTrue
            $report.CustomDomainHandoff.ReplacementClaimAttempted | Should -BeTrue
            $report.CustomDomainHandoff.ReplacementClaimSucceeded | Should -BeFalse
            $report.CustomDomainHandoff.ReplacementReadBackSucceeded | Should -BeFalse
            $report.CustomDomainHandoff.ExternalReadiness.Dns | Should -Be 'ExternalNotQueried'
            $report.CustomDomainHandoff.DnsMutationAttempted | Should -BeFalse
            $report.CustomDomainHandoff.AutomaticRollbackAttempted | Should -BeFalse
            $report.Recovery.AutomaticRollbackAttempted | Should -BeFalse
        }
    }

    It 'serializes archive and replacement identities with handoff evidence for delegated replacement' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'
                DestinationRepository = 'acme/destination'
                ArchiveRepository = 'acme/destination-archive'
                ContentMode = 'FullHistory'
            }
            $handoff = [pscustomobject] @{
                ReviewedCustomDomain = 'source.example.com'
                ArchiveRepository = 'acme/destination-archive'
                ArchiveRepositoryId = 30
                ReplacementRepository = 'acme/destination'
                ReplacementRepositoryId = 40
                ArchiveObservedCustomDomain = 'source.example.com'
                ArchiveReleaseAttempted = $true
                ArchiveReleaseSucceeded = $true
                ReplacementClaimAttempted = $true
                ReplacementClaimSucceeded = $true
                ReplacementReadBackSucceeded = $false
                HttpsIntent = $false
                ExternalReadiness = [pscustomobject] @{ Dns = 'ExternalNotQueried' }
                DnsMutationAttempted = $false
                AutomaticRollbackAttempted = $false
            }
            $steps = @([pscustomobject] @{ Order = 1; Name = 'ValidatePagesCustomDomainHandoff'; MutatedGitHub = $false; Verified = $true; CustomDomainHandoff = $handoff })
            $exception = [System.InvalidOperationException]::new('replacement readback failed')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'PagesCustomDomainReadBackFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $handoff)
            $archive = [pscustomobject] @{ FullName = 'acme/destination-archive'; Id = 30; NodeId = 'R_archive' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination'; Id = 40; NodeId = 'R_replacement' }
            $reportBase = Join-Path $TestDrive 'delegated-pages.json'

            $path = Write-CgrExistingDestinationRecoveryReport -Plan $plan -OriginalDestinationRepositoryId 30 -OriginalDestinationRepositoryNodeId 'R_archive' -ArchiveRepository $archive -DestinationRepository $destination -FailureStage 'VerifyReplacementPagesCustomDomain' -ErrorRecord $errorRecord -CompletedSteps $steps -PreferredReportPath $reportBase
            $report = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 30

            $report.FailureStage | Should -Be 'VerifyReplacementPagesCustomDomain'
            $report.ArchiveRepositoryId | Should -Be 30
            $report.ReplacementRepositoryId | Should -Be 40
            $report.ArchivedOriginalIdentityPreserved | Should -BeTrue
            $report.ReplacementHasDistinctIdentity | Should -BeTrue
            $report.CustomDomainHandoff.ReviewedCustomDomain | Should -BeExactly 'source.example.com'
            $report.CustomDomainHandoff.ArchiveReleaseSucceeded | Should -BeTrue
            $report.CustomDomainHandoff.ReplacementClaimSucceeded | Should -BeTrue
            $report.CustomDomainHandoff.ReplacementReadBackSucceeded | Should -BeFalse
            $report.CustomDomainHandoff.DnsMutationAttempted | Should -BeFalse
            $report.Recovery.AutomaticRollbackAttempted | Should -BeFalse
        }
    }
}
