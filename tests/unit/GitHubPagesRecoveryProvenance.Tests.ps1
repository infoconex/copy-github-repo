BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1') -Force
}

Describe 'GitHub Pages recovery provenance' {
    BeforeEach {
        InModuleScope CopyGitHubRepo {
            $script:pagesPlan = [pscustomobject] @{
                Configured = $true
                BuildType = 'workflow'
                Source = $null
                CustomDomain = 'docs.example.test'
                HttpsEnforced = $true
                Representability = [pscustomobject] @{ Status = 'Supported'; IsRepresentable = $true }
                ExternalReadiness = [pscustomobject] @{
                    DomainVerification = 'approved'
                    Certificate = 'NotReportedByGitHub'
                    Dns = 'ExternalNotQueried'
                }
            }
            $script:plan = [pscustomobject] @{
                Mode = 'NewDestination'
                SourceRepository = 'acme/source'
                DestinationRepository = 'acme/destination'
                ArchiveRepository = $null
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                ContentMode = 'Snapshot'
                SourceDefaultBranch = 'main'
                RestorePages = $true
                Pages = $script:pagesPlan
            }
            $script:destination = [pscustomobject] @{
                FullName = 'acme/destination'
                HtmlUrl = 'https://github.com/acme/destination'
            }
            $script:errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new('simulated failure'),
                'SimulatedFailure',
                [System.Management.Automation.ErrorCategory]::OperationStopped,
                'acme/destination'
            )
        }
    }

    It 'proves no Pages mutation occurred when failure precedes the Pages mutation boundary' {
        InModuleScope CopyGitHubRepo {
            Mock Get-CgrGitHubApiOptional { throw 'Recovery reconstruction must not query GitHub.' }
            Mock Invoke-CgrGitHubApiMutation { throw 'Recovery reconstruction must not mutate GitHub.' }
            $path = Join-Path $TestDrive 'before-pages.json'

            $reportPath = Write-CgrMigrationRecoveryReport -Plan $script:plan -DestinationRepository $script:destination -FailureStage 'RestoreGitHubPages' -ErrorRecord $script:errorRecord -CompletedSteps @() -PreferredReportPath $path
            $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json

            $report.Pages.RestoreRequested | Should -BeTrue
            $report.Pages.ReviewedConfiguration.CustomDomain | Should -Be 'docs.example.test'
            $report.Pages.DestinationMutationAttempted | Should -BeFalse
            $report.Pages.DestinationCreationAttempted | Should -BeFalse
            $report.Pages.AppliedConfiguration | Should -BeNullOrEmpty
            $report.Pages.LastSuccessfulStage | Should -BeNullOrEmpty
            $report.Pages.ExternalState.Ownership | Should -Be 'ExternalNotMigrated'
            $report.Pages.ExternalState.Readiness.Dns | Should -Be 'ExternalNotQueried'
            $report.Pages.ExternalState.Migrated | Should -BeFalse
            $report.Pages.DnsMutationAttempted | Should -BeFalse
            $report.Pages.AutomaticRollbackAttempted | Should -BeFalse
            Should -Invoke Get-CgrGitHubApiOptional -Times 0 -Exactly
            Should -Invoke Invoke-CgrGitHubApiMutation -Times 0 -Exactly
        }
    }

    It 'records the exact known applied state after destination Pages creation' {
        InModuleScope CopyGitHubRepo {
            $steps = @(
                [pscustomobject] @{
                    Order = 1; Name = 'CreateReplacementGitHubPages'; MutatedGitHub = $true; Verified = $false
                    Attempted = $true; Succeeded = $true
                    AppliedConfiguration = [pscustomobject] @{ BuildType = 'workflow'; Source = $null }
                }
            )
            $path = Join-Path $TestDrive 'created-pages.json'

            $reportPath = Write-CgrMigrationRecoveryReport -Plan $script:plan -DestinationRepository $script:destination -FailureStage 'ConfigureReplacementGitHubPages' -ErrorRecord $script:errorRecord -CompletedSteps $steps -PreferredReportPath $path
            $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json

            $report.Pages.DestinationMutationAttempted | Should -BeTrue
            $report.Pages.DestinationCreationAttempted | Should -BeTrue
            $report.Pages.DestinationCreationSucceeded | Should -BeTrue
            $report.Pages.AppliedConfiguration.BuildType | Should -Be 'workflow'
            $report.Pages.AppliedConfiguration.PSObject.Properties.Name | Should -Not -Contain 'CustomDomain'
            $report.Pages.LastSuccessfulStage | Should -Be 'CreateReplacementGitHubPages'
        }
    }

    It 'distinguishes archive release from an unattempted replacement claim' {
        InModuleScope CopyGitHubRepo {
            $replacementPlan = $script:plan.PSObject.Copy()
            $replacementPlan.Mode = 'SameNameReplacement'
            $replacementPlan.ArchiveRepository = 'acme/source-archive'
            $handoff = [pscustomobject] @{
                ReviewedCustomDomain = 'docs.example.test'
                ArchiveRepository = 'acme/source-archive'; ArchiveRepositoryId = 101L
                ReplacementRepository = 'acme/destination'; ReplacementRepositoryId = 202L
                ArchiveReleaseAttempted = $true; ArchiveReleaseSucceeded = $true
                ReplacementClaimAttempted = $false; ReplacementClaimSucceeded = $false; ReplacementReadBackSucceeded = $false
                DnsMutationAttempted = $false; AutomaticRollbackAttempted = $false
            }
            $steps = @(
                [pscustomobject] @{ Order = 1; Name = 'ReleaseArchivedPagesCustomDomain'; MutatedGitHub = $true; Verified = $true; Succeeded = $true; CustomDomainHandoff = $handoff }
            )
            $archive = [pscustomobject] @{ FullName = 'acme/source-archive'; Id = 101L; HtmlUrl = 'https://github.com/acme/source-archive' }
            $replacement = [pscustomobject] @{ FullName = 'acme/destination'; Id = 202L; HtmlUrl = 'https://github.com/acme/destination' }
            $path = Join-Path $TestDrive 'released-not-claimed.json'

            $reportPath = Write-CgrSameNameRecoveryReport -Plan $replacementPlan -SourceRepositoryId 101L -ArchiveRepository $archive -DestinationRepository $replacement -FailureStage 'CreateReplacementGitHubPages' -ErrorRecord $script:errorRecord -CompletedSteps $steps -PreferredReportPath $path
            $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json

            $report.Pages.ArchiveCustomDomainRelease.Attempted | Should -BeTrue
            $report.Pages.ArchiveCustomDomainRelease.Succeeded | Should -BeTrue
            $report.Pages.ArchiveCustomDomainRelease.KnownOwnsReviewedDomain | Should -BeFalse
            $report.Pages.ReplacementCustomDomainClaim.Attempted | Should -BeFalse
            $report.Pages.ReplacementCustomDomainClaim.KnownOwnsReviewedDomain | Should -BeNullOrEmpty
            $report.Pages.LastSuccessfulStage | Should -Be 'ReleaseArchivedPagesCustomDomain'
        }
    }

    It 'records replacement ownership only after successful claim readback' {
        InModuleScope CopyGitHubRepo {
            $replacementPlan = $script:plan.PSObject.Copy()
            $replacementPlan.Mode = 'SameNameReplacement'
            $replacementPlan.ArchiveRepository = 'acme/source-archive'
            $handoff = [pscustomobject] @{
                ReviewedCustomDomain = 'docs.example.test'
                ArchiveRepository = 'acme/source-archive'; ArchiveRepositoryId = 101L
                ReplacementRepository = 'acme/destination'; ReplacementRepositoryId = 202L
                ArchiveReleaseAttempted = $true; ArchiveReleaseSucceeded = $true
                ReplacementClaimAttempted = $true; ReplacementClaimSucceeded = $true; ReplacementReadBackSucceeded = $true
                DnsMutationAttempted = $false; AutomaticRollbackAttempted = $false
            }
            $steps = @(
                [pscustomobject] @{ Order = 1; Name = 'ReleaseArchivedPagesCustomDomain'; MutatedGitHub = $true; Verified = $true; Succeeded = $true; CustomDomainHandoff = $handoff },
                [pscustomobject] @{ Order = 2; Name = 'CreateReplacementGitHubPages'; MutatedGitHub = $true; Verified = $true; Attempted = $true; Succeeded = $true; AppliedConfiguration = [pscustomobject] @{ BuildType = 'workflow'; Source = $null } },
                [pscustomobject] @{ Order = 3; Name = 'ConfigureReplacementGitHubPages'; MutatedGitHub = $true; Verified = $true; Attempted = $true; Succeeded = $true; AppliedConfiguration = [pscustomobject] @{ CustomDomain = 'docs.example.test'; HttpsEnforced = $true } },
                [pscustomobject] @{ Order = 4; Name = 'ClaimReplacementPagesCustomDomain'; MutatedGitHub = $true; Verified = $true; Attempted = $true; Succeeded = $true; CustomDomainHandoff = $handoff }
            )
            $archive = [pscustomobject] @{ FullName = 'acme/source-archive'; Id = 101L; HtmlUrl = 'https://github.com/acme/source-archive' }
            $replacement = [pscustomobject] @{ FullName = 'acme/destination'; Id = 202L; HtmlUrl = 'https://github.com/acme/destination' }
            $path = Join-Path $TestDrive 'claimed.json'

            $reportPath = Write-CgrSameNameRecoveryReport -Plan $replacementPlan -SourceRepositoryId 101L -ArchiveRepository $archive -DestinationRepository $replacement -FailureStage 'ReleasePagesActivationGuard' -ErrorRecord $script:errorRecord -CompletedSteps $steps -PreferredReportPath $path
            $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json

            $report.Pages.ReplacementCustomDomainClaim.Attempted | Should -BeTrue
            $report.Pages.ReplacementCustomDomainClaim.Succeeded | Should -BeTrue
            $report.Pages.ReplacementCustomDomainClaim.ReadBackSucceeded | Should -BeTrue
            $report.Pages.ReplacementCustomDomainClaim.KnownOwnsReviewedDomain | Should -BeTrue
            $report.Pages.AppliedConfiguration.CustomDomain | Should -Be 'docs.example.test'
            $report.Pages.AppliedConfiguration.HttpsEnforced | Should -BeTrue
            $report.Pages.LastSuccessfulStage | Should -Be 'ClaimReplacementPagesCustomDomain'
        }
    }

    It 'exposes reviewed and applied Pages provenance on a successful restore result without external migration claims' {
        InModuleScope CopyGitHubRepo {
            $drift = [pscustomobject] @{ Configured = $true; BuildType = 'workflow'; Branch = $null; Path = $null; CustomDomain = 'docs.example.test'; HttpsEnforced = $true }
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'; ContentMode = 'Snapshot'; SourceState = [pscustomobject] @{}
                Pages = [pscustomobject] @{
                    Configured = $true; BuildType = 'workflow'; Source = $null; CustomDomain = 'docs.example.test'; HttpsEnforced = $true
                    Representability = [pscustomobject] @{ IsRepresentable = $true }; DriftEvidence = $drift
                    ExternalReadiness = [pscustomobject] @{ DomainVerification = 'approved'; Certificate = 'NotReportedByGitHub'; Dns = 'ExternalNotQueried' }
                }
            }
            $steps = [System.Collections.Generic.List[object]]::new()
            $script:created = $false
            Mock Get-CgrGitHubPagesPlanEvidence { [pscustomobject] @{ DriftEvidence = $drift } }
            Mock Get-CgrGitHubApiOptional {
                if (-not $script:created) { return $null }
                [pscustomobject] @{ build_type = 'workflow'; cname = 'docs.example.test'; https_enforced = $true }
            }
            Mock Invoke-CgrGitHubApiMutation { $script:created = $true }
            Mock Get-CgrGitHubApi { [pscustomobject] @{ enabled = $true } }

            $result = Restore-CgrGitHubPagesConfiguration -Plan $plan -SourceRepository ([pscustomobject] @{ FullName = 'acme/source' }) -DestinationRepository ([pscustomobject] @{ FullName = 'acme/destination' }) -CompletedSteps $steps

            $result.ReviewedConfiguration.CustomDomain | Should -Be 'docs.example.test'
            $result.DestinationCreationSucceeded | Should -BeTrue
            $result.AppliedConfiguration.CustomDomain | Should -Be 'docs.example.test'
            $result.LastSuccessfulPagesStage | Should -Be 'ReleasePagesActivationGuard'
            $result.ExternalState.Ownership | Should -Be 'ExternalNotMigrated'
            $result.ExternalState.Migrated | Should -BeFalse
            $result.DnsMutationAttempted | Should -BeFalse
            $result.AutomaticRollbackAttempted | Should -BeFalse
            @($steps | Where-Object Name -eq 'CreateReplacementGitHubPages').Count | Should -Be 1
            @($steps | Where-Object Name -eq 'ConfigureReplacementGitHubPages').Count | Should -Be 1
        }
    }
}
