BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'GitHub Pages planning evidence' {
    BeforeEach {
        InModuleScope CopyGitHubRepo {
            $script:repository = [pscustomobject] @{ FullName = 'acme/source'; DefaultBranch = 'main' }
            $script:snapshotState = [pscustomobject] @{ DefaultBranch = 'main' }
        }
    }

    It 'represents a source without Pages explicitly as NotConfigured' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrGitHubApiReadRequest {
                [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = 'HTTP 404: Not Found' }
            }

            $result = Get-CgrGitHubPagesPlanEvidence -Repository $script:repository -ContentMode Snapshot -SourceState $script:snapshotState

            $result.Status | Should -Be 'NotConfigured'
            $result.Configured | Should -BeFalse
            $result.Representability.Status | Should -Be 'NotApplicable'
            $result.ExternalReadiness.Dns | Should -Be 'ExternalNotQueried'
            $result.DriftEvidence.Configured | Should -BeFalse
        }
    }

    It 'captures Actions-based Pages without inventing a branch/path source' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrGitHubApiReadRequest {
                $pages = [pscustomobject] @{ build_type = 'workflow'; cname = $null; https_enforced = $true }
                [pscustomobject] @{ ExitCode = 0; Output = @($pages | ConvertTo-Json -Depth 10 -Compress); ErrorText = '' }
            }

            $result = Get-CgrGitHubPagesPlanEvidence -Repository $script:repository -ContentMode Snapshot -SourceState $script:snapshotState

            $result.Status | Should -Be 'Configured'
            $result.BuildType | Should -Be 'workflow'
            $result.Source | Should -BeNullOrEmpty
            $result.HttpsEnforced | Should -BeTrue
            $result.Representability.IsRepresentable | Should -BeTrue
            $result.DriftEvidence.BuildType | Should -Be 'workflow'
        }
    }

    It 'captures exact branch/path Pages configuration when Snapshot can represent it' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrGitHubApiReadRequest {
                $pages = [pscustomobject] @{
                    build_type = 'legacy'
                    source = [pscustomobject] @{ branch = 'main'; path = '/docs' }
                    cname = $null
                    https_enforced = $false
                }
                [pscustomobject] @{ ExitCode = 0; Output = @($pages | ConvertTo-Json -Depth 10 -Compress); ErrorText = '' }
            }

            $result = Get-CgrGitHubPagesPlanEvidence -Repository $script:repository -ContentMode Snapshot -SourceState $script:snapshotState

            $result.Status | Should -Be 'Configured'
            $result.Source.Branch | Should -Be 'main'
            $result.Source.Path | Should -Be '/docs'
            $result.Representability.IsRepresentable | Should -BeTrue
            $result.DriftEvidence.Branch | Should -Be 'main'
            $result.DriftEvidence.Path | Should -Be '/docs'
        }
    }

    It 'surfaces a branch/path configuration that Snapshot cannot represent' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrGitHubApiReadRequest {
                $pages = [pscustomobject] @{
                    build_type = 'legacy'
                    source = [pscustomobject] @{ branch = 'gh-pages'; path = '/' }
                }
                [pscustomobject] @{ ExitCode = 0; Output = @($pages | ConvertTo-Json -Depth 10 -Compress); ErrorText = '' }
            }

            $result = Get-CgrGitHubPagesPlanEvidence -Repository $script:repository -ContentMode Snapshot -SourceState $script:snapshotState

            $result.Status | Should -Be 'Unrepresentable'
            $result.Representability.IsRepresentable | Should -BeFalse
            $result.Representability.Reason | Should -Match 'gh-pages'
            $result.Representability.Reason | Should -Match 'Snapshot'
        }
    }

    It 'accepts exact branch/path Pages configuration when FullHistory preserves the branch' {
        InModuleScope CopyGitHubRepo {
            $fullHistoryState = [pscustomobject] @{
                Refs = @('refs/heads/main aaaaa', 'refs/heads/gh-pages bbbbb', 'refs/tags/v1 ccccc')
            }
            Mock Invoke-CgrGitHubApiReadRequest {
                $pages = [pscustomobject] @{
                    build_type = 'legacy'
                    source = [pscustomobject] @{ branch = 'gh-pages'; path = '/' }
                }
                [pscustomobject] @{ ExitCode = 0; Output = @($pages | ConvertTo-Json -Depth 10 -Compress); ErrorText = '' }
            }

            $result = Get-CgrGitHubPagesPlanEvidence -Repository $script:repository -ContentMode FullHistory -SourceState $fullHistoryState

            $result.Status | Should -Be 'Configured'
            $result.Representability.IsRepresentable | Should -BeTrue
        }
    }

    It 'separates custom-domain and HTTPS intent from external readiness evidence' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrGitHubApiReadRequest {
                $pages = [pscustomobject] @{
                    build_type = 'workflow'
                    cname = 'docs.example.com'
                    https_enforced = $true
                    protected_domain_state = 'verified'
                    pending_domain_unverified_at = $null
                    https_certificate = [pscustomobject] @{ state = 'approved'; description = 'Certificate approved' }
                }
                [pscustomobject] @{ ExitCode = 0; Output = @($pages | ConvertTo-Json -Depth 10 -Compress); ErrorText = '' }
            }

            $result = Get-CgrGitHubPagesPlanEvidence -Repository $script:repository -ContentMode Snapshot -SourceState $script:snapshotState

            $result.CustomDomain | Should -Be 'docs.example.com'
            $result.HttpsEnforced | Should -BeTrue
            $result.ExternalReadiness.DomainVerification | Should -Be 'verified'
            $result.ExternalReadiness.Certificate.state | Should -Be 'approved'
            $result.ExternalReadiness.Dns | Should -Be 'ExternalNotQueried'
            $result.DriftEvidence.CustomDomain | Should -Be 'docs.example.com'
            $result.DriftEvidence.HttpsEnforced | Should -BeTrue
        }
    }

    It 'surfaces unsupported build types instead of substituting another mode' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrGitHubApiReadRequest {
                $pages = [pscustomobject] @{ build_type = 'future-mode' }
                [pscustomobject] @{ ExitCode = 0; Output = @($pages | ConvertTo-Json -Depth 10 -Compress); ErrorText = '' }
            }

            $result = Get-CgrGitHubPagesPlanEvidence -Repository $script:repository -ContentMode Snapshot -SourceState $script:snapshotState

            $result.Status | Should -Be 'Unsupported'
            $result.Representability.IsRepresentable | Should -BeFalse
            $result.Representability.Reason | Should -Match 'future-mode'
        }
    }
}

Describe 'GitHub Pages migration-plan integration' {
    BeforeEach {
        InModuleScope CopyGitHubRepo {
            $script:sourceRepository = [pscustomobject] @{
                FullName = 'acme/source'
                Owner = 'acme'
                DefaultBranch = 'main'
                Visibility = 'private'
                Id = $null
            }
            $script:sourceState = [pscustomobject] @{
                ContentMode = 'Snapshot'
                Repository = 'acme/source'
                DefaultBranch = 'main'
                CommitSha = 'head'
                TreeSha = 'tree-head'
                GitLfsPointerFiles = @()
                GitLfsObjectsAvailable = $true
                HistoricalRecords = $null
            }
            Mock Test-CgrGitHubRepositoryExistence { $false }
            Mock Get-CgrApprovedSourceState { $script:sourceState }
        }
    }

    It 'binds the exact reviewed Pages evidence into Plan.Pages when RestorePages is requested' {
        InModuleScope CopyGitHubRepo {
            $pagesEvidence = [pscustomobject] @{
                Status = 'Configured'
                Configured = $true
                BuildType = 'workflow'
                Source = $null
                CustomDomain = 'docs.example.com'
                HttpsEnforced = $true
                Representability = [pscustomobject] @{ Status = 'Supported'; IsRepresentable = $true; Reason = 'representable' }
                ExternalReadiness = [pscustomobject] @{ DomainVerification = 'verified'; Certificate = 'NotReportedByGitHub'; Dns = 'ExternalNotQueried' }
                DriftEvidence = [pscustomobject] @{ Configured = $true; BuildType = 'workflow'; Branch = $null; Path = $null; CustomDomain = 'docs.example.com'; HttpsEnforced = $true }
            }
            Mock Get-CgrGitHubPagesPlanEvidence { $pagesEvidence }

            $plan = New-CgrMigrationPlan -SourceRepository $script:sourceRepository -DestinationRepository acme/destination -ContentMode Snapshot -DestinationVisibility private -CommitMessage 'Initial repository commit' -RestorePages -SkipSettings -PlanOnly

            $plan.Pages | Should -BeSame $pagesEvidence
            Should -Invoke Get-CgrGitHubPagesPlanEvidence -Times 1 -Exactly -ParameterFilter {
                $Repository -eq $script:sourceRepository -and
                $ContentMode -eq 'Snapshot' -and
                $SourceState -eq $script:sourceState
            }
        }
    }

    It 'does not read or add Pages evidence when RestorePages is omitted' {
        InModuleScope CopyGitHubRepo {
            Mock Get-CgrGitHubPagesPlanEvidence { throw 'Pages discovery must not run' }

            $plan = New-CgrMigrationPlan -SourceRepository $script:sourceRepository -DestinationRepository acme/destination -ContentMode Snapshot -DestinationVisibility private -CommitMessage 'Initial repository commit' -SkipSettings -PlanOnly

            @($plan.PSObject.Properties.Name) | Should -Not -Contain 'Pages'
            Should -Invoke Get-CgrGitHubPagesPlanEvidence -Times 0 -Exactly
        }
    }
}

Describe 'GitHub Pages plan rendering' {
    It 'shows the reviewed configuration, representability, external readiness, and drift-driving evidence' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'
                DestinationRepository = 'acme/destination'
                ArchiveRepository = $null
                Mode = 'NewDestination'
                ContentMode = 'Snapshot'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                IncludeReleases = $false
                RestorePages = $true
                EnableActionsAfterMigration = $false
                SkipSettings = $true
                PlanOnly = $true
                SourceState = $null
                ReleaseSelection = $null
                ReleaseCheckpointPlan = $null
                Pages = [pscustomobject] @{
                    Status = 'Configured'
                    Configured = $true
                    BuildType = 'legacy'
                    Source = [pscustomobject] @{ Branch = 'main'; Path = '/docs' }
                    CustomDomain = 'docs.example.com'
                    HttpsEnforced = $true
                    Representability = [pscustomobject] @{ Status = 'Supported'; IsRepresentable = $true; Reason = 'Exact branch and path are representable.' }
                    ExternalReadiness = [pscustomobject] @{ DomainVerification = 'verified'; Certificate = [pscustomobject] @{ state = 'approved' }; Dns = 'ExternalNotQueried' }
                    DriftEvidence = [pscustomobject] @{ Configured = $true; BuildType = 'legacy'; Branch = 'main'; Path = '/docs'; CustomDomain = 'docs.example.com'; HttpsEnforced = $true }
                }
                Steps = @()
            }

            $markdown = Format-CgrMigrationPlan -Plan $plan -Format Markdown

            $markdown | Should -Match '## Approved GitHub Pages Configuration'
            $markdown | Should -Match '\| Build type \| legacy \|'
            $markdown | Should -Match '\| Publishing branch \| main \|'
            $markdown | Should -Match '\| Publishing path \| /docs \|'
            $markdown | Should -Match '\| Custom domain \| docs.example.com \|'
            $markdown | Should -Match '\| HTTPS enforcement intent \| True \|'
            $markdown | Should -Match '\| Domain verification readiness \| verified \|'
            $markdown | Should -Match '\| Certificate readiness \| approved \|'
            $markdown | Should -Match '\| DNS evidence \| ExternalNotQueried \|'
            $markdown | Should -Match '### Pages drift-driving evidence'
        }
    }

    It 'does not add a Pages section when RestorePages is omitted' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'
                DestinationRepository = 'acme/destination'
                ArchiveRepository = $null
                Mode = 'NewDestination'
                ContentMode = 'Snapshot'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                IncludeReleases = $false
                RestorePages = $false
                EnableActionsAfterMigration = $false
                SkipSettings = $true
                PlanOnly = $true
                SourceState = $null
                ReleaseSelection = $null
                ReleaseCheckpointPlan = $null
                Steps = @()
            }

            (Format-CgrMigrationPlan -Plan $plan -Format Markdown) | Should -Not -Match 'Approved GitHub Pages Configuration'
        }
    }
}
