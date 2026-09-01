BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1') -Force
}

Describe 'Independent GitHub Pages verification' {
    It 'verifies Actions-based Pages and reports external readiness separately' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'
                Pages = [pscustomobject] @{
                    Configured = $true
                    BuildType = 'workflow'
                    Source = $null
                    CustomDomain = 'www.example.com'
                    HttpsEnforced = $true
                }
            }
            Mock Get-CgrGitHubApiOptional {
                [pscustomobject] @{
                    build_type = 'workflow'; source = $null; cname = 'www.example.com'; https_enforced = $true
                    protected_domain_state = 'verified'; https_certificate = [pscustomobject] @{ state = 'approved' }
                }
            }

            $result = Test-CgrGitHubPagesMigration -Plan $plan -DestinationRepository ([pscustomobject] @{ FullName = 'acme/destination' })

            $result.IsSuccessful | Should -BeTrue
            $result.Status | Should -Be 'Verified'
            $result.ExternalReadiness.DomainVerification | Should -Be 'verified'
            $result.ExternalReadiness.AffectsConfigurationVerification | Should -BeFalse
            $result.ExternalReadiness.Dns | Should -Be 'ExternalNotQueried'
            $result.DnsMigrated | Should -BeFalse
        }
    }

    It 'detects the wrong build type' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{ Mode = 'NewDestination'; Pages = [pscustomobject] @{ Configured = $true; BuildType = 'workflow'; CustomDomain = $null; HttpsEnforced = $null } }
            Mock Get-CgrGitHubApiOptional { [pscustomobject] @{ build_type = 'legacy'; source = [pscustomobject] @{ branch = 'main'; path = '/' }; cname = $null } }

            $result = Test-CgrGitHubPagesMigration -Plan $plan -DestinationRepository ([pscustomobject] @{ FullName = 'acme/destination' })

            $result.IsSuccessful | Should -BeFalse
            ($result.Checks | Where-Object Name -eq 'PagesBuildTypeMatches').Passed | Should -BeFalse
        }
    }

    It 'verifies the exact legacy branch and path and detects either mismatch' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'
                Pages = [pscustomobject] @{
                    Configured = $true; BuildType = 'legacy'; Source = [pscustomobject] @{ Branch = 'pages'; Path = '/docs' }
                    CustomDomain = $null; HttpsEnforced = $false
                }
            }
            $script:actualBranch = 'pages'
            $script:actualPath = '/docs'
            Mock Get-CgrGitHubApiOptional {
                [pscustomobject] @{ build_type = 'legacy'; source = [pscustomobject] @{ branch = $script:actualBranch; path = $script:actualPath }; cname = $null; https_enforced = $false }
            }
            $destination = [pscustomobject] @{ FullName = 'acme/destination' }

            (Test-CgrGitHubPagesMigration -Plan $plan -DestinationRepository $destination).IsSuccessful | Should -BeTrue

            $script:actualBranch = 'main'
            $branchResult = Test-CgrGitHubPagesMigration -Plan $plan -DestinationRepository $destination
            ($branchResult.Checks | Where-Object Name -eq 'PagesSourceBranchMatches').Passed | Should -BeFalse

            $script:actualBranch = 'pages'
            $script:actualPath = '/'
            $pathResult = Test-CgrGitHubPagesMigration -Plan $plan -DestinationRepository $destination
            ($pathResult.Checks | Where-Object Name -eq 'PagesSourcePathMatches').Passed | Should -BeFalse
        }
    }

    It 'detects expected Pages missing and explicit no-Pages state violations' {
        InModuleScope CopyGitHubRepo {
            $destination = [pscustomobject] @{ FullName = 'acme/destination' }
            Mock Get-CgrGitHubApiOptional { $null }
            $expectedPages = [pscustomobject] @{ Mode = 'NewDestination'; Pages = [pscustomobject] @{ Configured = $true; BuildType = 'workflow' } }

            (Test-CgrGitHubPagesMigration -Plan $expectedPages -DestinationRepository $destination).IsSuccessful | Should -BeFalse

            $noPages = [pscustomobject] @{ Mode = 'NewDestination'; Pages = [pscustomobject] @{ Configured = $false } }
            $noPagesResult = Test-CgrGitHubPagesMigration -Plan $noPages -DestinationRepository $destination
            $noPagesResult.IsSuccessful | Should -BeTrue
            $noPagesResult.Status | Should -Be 'VerifiedNotConfigured'

            Mock Get-CgrGitHubApiOptional { [pscustomobject] @{ build_type = 'workflow' } }
            (Test-CgrGitHubPagesMigration -Plan $noPages -DestinationRepository $destination).IsSuccessful | Should -BeFalse
        }
    }

    It 'detects missing or wrong custom domains and deterministic HTTPS mismatches' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'
                Pages = [pscustomobject] @{ Configured = $true; BuildType = 'workflow'; CustomDomain = 'www.example.com'; HttpsEnforced = $true }
            }
            $script:cname = $null
            $script:https = $true
            Mock Get-CgrGitHubApiOptional { [pscustomobject] @{ build_type = 'workflow'; cname = $script:cname; https_enforced = $script:https } }
            $destination = [pscustomobject] @{ FullName = 'acme/destination' }

            $missing = Test-CgrGitHubPagesMigration -Plan $plan -DestinationRepository $destination
            ($missing.Checks | Where-Object Name -eq 'PagesCustomDomainMatches').Passed | Should -BeFalse

            $script:cname = 'other.example.com'
            $wrong = Test-CgrGitHubPagesMigration -Plan $plan -DestinationRepository $destination
            ($wrong.Checks | Where-Object Name -eq 'PagesCustomDomainMatches').Passed | Should -BeFalse

            $script:cname = 'www.example.com'
            $script:https = $false
            $https = Test-CgrGitHubPagesMigration -Plan $plan -DestinationRepository $destination
            ($https.Checks | Where-Object Name -eq 'PagesHttpsEnforcementMatches').Passed | Should -BeFalse
        }
    }

    It 'verifies replacement owns the reviewed domain and archive no longer does' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                Mode = 'SameNameReplacement'; ArchiveRepository = 'acme/archive'
                Pages = [pscustomobject] @{ Configured = $true; BuildType = 'workflow'; CustomDomain = 'www.example.com'; HttpsEnforced = $true }
            }
            $script:archiveDomain = $null
            Mock Get-CgrGitHubApiOptional {
                if ($Path -eq 'repos/acme/destination/pages') { return [pscustomobject] @{ build_type = 'workflow'; cname = 'www.example.com'; https_enforced = $true } }
                if ($Path -eq 'repos/acme/archive/pages') { return [pscustomobject] @{ build_type = 'workflow'; cname = $script:archiveDomain } }
                throw "Unexpected Pages read: $Path"
            }
            $destination = [pscustomobject] @{ FullName = 'acme/destination' }

            $success = Test-CgrGitHubPagesMigration -Plan $plan -DestinationRepository $destination
            $success.IsSuccessful | Should -BeTrue
            ($success.Checks | Where-Object Name -eq 'PagesArchiveCustomDomainReleased').Passed | Should -BeTrue
            ($success.Checks | Where-Object Name -eq 'PagesReplacementCustomDomainOwned').Passed | Should -BeTrue

            $script:archiveDomain = 'www.example.com'
            $failure = Test-CgrGitHubPagesMigration -Plan $plan -DestinationRepository $destination
            $failure.IsSuccessful | Should -BeFalse
            ($failure.Checks | Where-Object Name -eq 'PagesArchiveCustomDomainReleased').Passed | Should -BeFalse
        }
    }

    It 'requires immutable reviewed Pages evidence and performs no mutation' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrGitHubApiMutation { throw 'verification must not mutate' }
            { Test-CgrGitHubPagesMigration -Plan ([pscustomobject] @{ Mode = 'NewDestination' }) -DestinationRepository ([pscustomobject] @{ FullName = 'acme/destination' }) } |
                Should -Throw -ErrorId 'ApprovedPagesEvidenceMissing'
            Should -Invoke Invoke-CgrGitHubApiMutation -Times 0
        }
    }
}
