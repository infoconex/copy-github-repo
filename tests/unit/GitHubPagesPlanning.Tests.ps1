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
