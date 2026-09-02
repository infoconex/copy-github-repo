BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1') -Force
}

Describe 'GitHub Pages HTTPS certificate readiness' {
    It 'preserves HTTPS intent without failing when a newly created Pages certificate is pending' {
        InModuleScope CopyGitHubRepo {
            foreach ($buildType in @('workflow', 'legacy')) {
                $source = if ($buildType -eq 'legacy') { [pscustomobject] @{ Branch = 'main'; Path = '/docs' } } else { $null }
                $pages = [pscustomobject] @{
                    Configured = $true
                    BuildType = $buildType
                    Source = $source
                    CustomDomain = $null
                    HttpsEnforced = $true
                    Representability = [pscustomobject] @{ IsRepresentable = $true }
                    ExternalReadiness = [pscustomobject] @{ Certificate = 'NotReportedByGitHub'; Dns = 'ExternalNotQueried' }
                }
                $plan = [pscustomobject] @{ Mode = 'NewDestination'; ContentMode = 'Snapshot'; Pages = $pages }
                $script:created = $false
                $script:guardReleased = $false

                Mock Assert-CgrGitHubPagesPlanEvidence { $pages }
                Mock Assert-CgrDestinationPagesSource {}
                Mock Get-CgrGitHubApiOptional {
                    if ($Path -eq 'repos/acme/destination/pages') {
                        if (-not $script:created) { return $null }
                        return [pscustomobject] @{
                            build_type = $buildType
                            source = if ($buildType -eq 'legacy') { [pscustomobject] @{ branch = 'main'; path = '/docs' } } else { $null }
                            cname = $null
                            https_enforced = $false
                            https_certificate = $null
                        }
                    }
                    throw "Unexpected optional read: $Path"
                }
                Mock Invoke-CgrGitHubApiMutation {
                    if ($Path -eq '/repos/acme/destination/pages' -and $Method -eq 'POST') {
                        $script:created = $true
                        return
                    }
                    if ($Path -eq '/repos/acme/destination/pages' -and $Method -eq 'PUT') {
                        throw 'GitHub CLI API PUT request failed. The certificate does not exist yet (HTTP 404)'
                    }
                    if ($Path -eq '/repos/acme/destination/actions/permissions') {
                        $script:guardReleased = $true
                        return
                    }
                    throw "Unexpected mutation: $Method $Path"
                }
                Mock Get-CgrGitHubApi { [pscustomobject] @{ enabled = $true } }

                $result = Restore-CgrGitHubPagesConfiguration `
                    -Plan $plan `
                    -SourceRepository ([pscustomobject] @{ FullName = 'acme/source' }) `
                    -DestinationRepository ([pscustomobject] @{ FullName = 'acme/destination' })

                $result.IsSuccessful | Should -BeTrue
                $result.Verified | Should -BeTrue
                $result.HttpsEnforced | Should -BeTrue
                $result.HttpsEnforcementStatus | Should -BeExactly 'PendingCertificate'
                $result.AppliedConfiguration.HttpsEnforced | Should -BeNullOrEmpty
                $script:guardReleased | Should -BeTrue
            }
        }
    }

    It 'treats pending certificate readiness as external evidence during independent verification' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'
                Pages = [pscustomobject] @{
                    Configured = $true
                    BuildType = 'workflow'
                    Source = $null
                    CustomDomain = $null
                    HttpsEnforced = $true
                }
            }
            Mock Get-CgrGitHubApiOptional {
                [pscustomobject] @{
                    build_type = 'workflow'
                    source = $null
                    cname = $null
                    https_enforced = $false
                    https_certificate = $null
                    protected_domain_state = $null
                    pending_domain_unverified_at = $null
                }
            }

            $result = Test-CgrGitHubPagesMigration `
                -Plan $plan `
                -DestinationRepository ([pscustomobject] @{ FullName = 'acme/destination' })

            $result.IsSuccessful | Should -BeTrue
            $result.HttpsEnforcementStatus | Should -BeExactly 'PendingCertificate'
            ($result.Checks | Where-Object Name -eq 'PagesHttpsEnforcementMatches').Passed | Should -BeTrue
        }
    }

    It 'still fails independent verification for a deterministic HTTPS mismatch' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'
                Pages = [pscustomobject] @{
                    Configured = $true
                    BuildType = 'workflow'
                    Source = $null
                    CustomDomain = $null
                    HttpsEnforced = $true
                }
            }
            Mock Get-CgrGitHubApiOptional {
                [pscustomobject] @{
                    build_type = 'workflow'
                    source = $null
                    cname = $null
                    https_enforced = $false
                    https_certificate = [pscustomobject] @{ state = 'approved' }
                    protected_domain_state = $null
                    pending_domain_unverified_at = $null
                }
            }

            $result = Test-CgrGitHubPagesMigration `
                -Plan $plan `
                -DestinationRepository ([pscustomobject] @{ FullName = 'acme/destination' })

            $result.IsSuccessful | Should -BeFalse
            $result.HttpsEnforcementStatus | Should -BeExactly 'Mismatch'
            ($result.Checks | Where-Object Name -eq 'PagesHttpsEnforcementMatches').Passed | Should -BeFalse
        }
    }
}
