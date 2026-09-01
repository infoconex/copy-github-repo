BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1') -Force
}

Describe 'GitHub Pages restoration' {
    It 'restores Actions-based Pages from immutable evidence, verifies it, then releases the activation guard' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'
                ContentMode = 'Snapshot'
                SourceState = [pscustomobject] @{ CommitSha = 'abc' }
                Pages = [pscustomobject] @{
                    Configured = $true
                    BuildType = 'workflow'
                    Source = $null
                    CustomDomain = $null
                    HttpsEnforced = $true
                    Representability = [pscustomobject] @{ IsRepresentable = $true; Reason = 'Supported' }
                    DriftEvidence = [pscustomobject] @{ Configured = $true; BuildType = 'workflow'; Branch = $null; Path = $null; CustomDomain = $null; HttpsEnforced = $true }
                }
            }
            $source = [pscustomobject] @{ FullName = 'acme/source' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination' }
            $script:events = [System.Collections.Generic.List[string]]::new()

            Mock Get-CgrGitHubPagesPlanEvidence { [pscustomobject] @{ DriftEvidence = $plan.Pages.DriftEvidence } }
            Mock Get-CgrGitHubApiOptional {
                if ($Path -eq 'repos/acme/destination/pages') {
                    if ($script:events -contains 'CreatePages') {
                        return [pscustomobject] @{ build_type = 'workflow'; source = $null; cname = $null; https_enforced = $true }
                    }
                    return $null
                }
                throw "Unexpected optional read: $Path"
            }
            Mock Invoke-CgrGitHubApiMutation {
                if ($Path -eq '/repos/acme/destination/pages' -and $Method -eq 'POST') { $script:events.Add('CreatePages'); return }
                if ($Path -eq '/repos/acme/destination/pages' -and $Method -eq 'PUT') { $script:events.Add('UpdatePages'); return }
                if ($Path -eq '/repos/acme/destination/actions/permissions') { $script:events.Add('ReleaseGuard'); return }
                throw "Unexpected mutation: $Method $Path"
            }
            Mock Get-CgrGitHubApi {
                $script:events.Add('VerifyGuard')
                [pscustomobject] @{ enabled = $true }
            }

            $result = Restore-CgrGitHubPagesConfiguration -Plan $plan -SourceRepository $source -DestinationRepository $destination

            $result.Status | Should -Be 'Restored'
            $result.BuildType | Should -Be 'workflow'
            $result.GuardReleased | Should -BeTrue
            ($script:events -join ',') | Should -Be 'CreatePages,UpdatePages,ReleaseGuard,VerifyGuard'
            Should -Invoke Invoke-CgrGitHubApiMutation -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Path -eq '/repos/acme/destination/pages' -and $Body.build_type -eq 'workflow'
            }
        }
    }

    It 'uses exact reviewed branch/path and fails closed when the destination path is absent' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'
                ContentMode = 'FullHistory'
                SourceState = [pscustomobject] @{ Refs = @() }
                Pages = [pscustomobject] @{
                    Configured = $true
                    BuildType = 'legacy'
                    Source = [pscustomobject] @{ Branch = 'pages'; Path = '/docs' }
                    CustomDomain = $null
                    HttpsEnforced = $false
                    Representability = [pscustomobject] @{ IsRepresentable = $true; Reason = 'Supported' }
                    DriftEvidence = [pscustomobject] @{ Configured = $true; BuildType = 'legacy'; Branch = 'pages'; Path = '/docs'; CustomDomain = $null; HttpsEnforced = $false }
                }
            }
            $source = [pscustomobject] @{ FullName = 'acme/source' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination' }
            Mock Get-CgrGitHubPagesPlanEvidence { [pscustomobject] @{ DriftEvidence = $plan.Pages.DriftEvidence } }
            Mock Get-CgrGitHubApiOptional {
                if ($Path -eq 'repos/acme/destination/pages') { return $null }
                if ($Path -eq 'repos/acme/destination/branches/pages') { return [pscustomobject] @{ name = 'pages' } }
                if ($Path -eq 'repos/acme/destination/contents/docs?ref=pages') { return $null }
                throw "Unexpected read: $Path"
            }
            Mock Invoke-CgrGitHubApiMutation { throw 'must not mutate' }

            { Restore-CgrGitHubPagesConfiguration -Plan $plan -SourceRepository $source -DestinationRepository $destination } |
                Should -Throw -ErrorId 'DestinationPagesPathMissing,Assert-CgrDestinationPagesSource'
            Should -Invoke Invoke-CgrGitHubApiMutation -Times 0
        }
    }

    It 'blocks all destination mutation when live source Pages evidence drifted' {
        InModuleScope CopyGitHubRepo {
            $reviewed = [pscustomobject] @{ Configured = $true; BuildType = 'workflow'; Branch = $null; Path = $null; CustomDomain = $null; HttpsEnforced = $true }
            $live = [pscustomobject] @{ Configured = $true; BuildType = 'legacy'; Branch = 'main'; Path = '/'; CustomDomain = $null; HttpsEnforced = $true }
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'; ContentMode = 'Snapshot'; SourceState = [pscustomobject] @{}
                Pages = [pscustomobject] @{ Configured = $true; BuildType = 'workflow'; Representability = [pscustomobject] @{ IsRepresentable = $true }; DriftEvidence = $reviewed }
            }
            Mock Get-CgrGitHubPagesPlanEvidence { [pscustomobject] @{ DriftEvidence = $live } }
            Mock Invoke-CgrGitHubApiMutation { throw 'must not mutate' }
            Mock Get-CgrGitHubApiOptional { throw 'must not inspect destination before source drift passes' }

            { Restore-CgrGitHubPagesConfiguration -Plan $plan -SourceRepository ([pscustomobject] @{ FullName = 'acme/source' }) -DestinationRepository ([pscustomobject] @{ FullName = 'acme/destination' }) } |
                Should -Throw -ErrorId 'PagesStateChangedSincePlanning,Assert-CgrGitHubPagesPlanEvidence'
            Should -Invoke Invoke-CgrGitHubApiMutation -Times 0
        }
    }

    It 'treats reviewed no-Pages state as a verified no-op and still releases the temporary guard' {
        InModuleScope CopyGitHubRepo {
            $drift = [pscustomobject] @{ Configured = $false; BuildType = $null; Branch = $null; Path = $null; CustomDomain = $null; HttpsEnforced = $null }
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'; ContentMode = 'Snapshot'; SourceState = [pscustomobject] @{}
                Pages = [pscustomobject] @{ Configured = $false; BuildType = $null; Representability = [pscustomobject] @{ IsRepresentable = $true }; DriftEvidence = $drift }
            }
            Mock Get-CgrGitHubPagesPlanEvidence { [pscustomobject] @{ DriftEvidence = $drift } }
            Mock Get-CgrGitHubApiOptional { $null }
            Mock Invoke-CgrGitHubApiMutation {}
            Mock Get-CgrGitHubApi { [pscustomobject] @{ enabled = $true } }

            $result = Restore-CgrGitHubPagesConfiguration -Plan $plan -SourceRepository ([pscustomobject] @{ FullName = 'acme/source' }) -DestinationRepository ([pscustomobject] @{ FullName = 'acme/destination' })

            $result.Status | Should -Be 'ReviewedNotConfigured'
            $result.Restored | Should -BeFalse
            $result.Verified | Should -BeTrue
            Should -Invoke Invoke-CgrGitHubApiMutation -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PUT' -and $Path -eq '/repos/acme/destination/actions/permissions' -and $Body.enabled -eq $true
            }
        }
    }

    It 'keeps replacement custom-domain ownership handoff out of ordinary Pages restoration' {
        InModuleScope CopyGitHubRepo {
            $drift = [pscustomobject] @{ Configured = $true; BuildType = 'workflow'; Branch = $null; Path = $null; CustomDomain = 'www.example.com'; HttpsEnforced = $true }
            $plan = [pscustomobject] @{
                Mode = 'SameNameReplacement'; ContentMode = 'Snapshot'; SourceState = [pscustomobject] @{}
                Pages = [pscustomobject] @{ Configured = $true; BuildType = 'workflow'; Source = $null; CustomDomain = 'www.example.com'; HttpsEnforced = $true; Representability = [pscustomobject] @{ IsRepresentable = $true }; DriftEvidence = $drift }
            }
            Mock Get-CgrGitHubPagesPlanEvidence { [pscustomobject] @{ DriftEvidence = $drift } }
            Mock Get-CgrGitHubApiOptional { $null }
            Mock Invoke-CgrGitHubApiMutation { throw 'must not mutate' }

            { Restore-CgrGitHubPagesConfiguration -Plan $plan -SourceRepository ([pscustomobject] @{ FullName = 'acme/source-archive' }) -DestinationRepository ([pscustomobject] @{ FullName = 'acme/source' }) } |
                Should -Throw -ErrorId 'PagesCustomDomainHandoffRequired,Restore-CgrGitHubPagesConfiguration'
            Should -Invoke Invoke-CgrGitHubApiMutation -Times 0
        }
    }

    It 'orders Pages after successful settings and before protection for Snapshot and FullHistory, and never runs it after failed content verification' {
        InModuleScope CopyGitHubRepo {
            foreach ($contentMode in @('Snapshot', 'FullHistory')) {
                $plan = [pscustomobject] @{
                    Mode = 'NewDestination'
                    ContentMode = $contentMode
                    IncludeReleases = $false
                    RestorePages = $true
                    SkipSettings = $false
                    Protection = [pscustomobject] @{ Status = 'Captured'; Configuration = [pscustomobject] @{} }
                }
                $source = [pscustomobject] @{ FullName = 'acme/source' }
                $destination = [pscustomobject] @{ FullName = 'acme/destination' }
                $steps = [System.Collections.Generic.List[object]]::new()
                $failureStage = 'VerifyDestinationContent'
                Mock Set-CgrGitHubRepositorySetting { [pscustomobject] @{ IsSuccessful = $true; Restored = @(); Skipped = @(); Unsupported = @() } }
                Mock Restore-CgrGitHubPagesConfiguration { [pscustomobject] @{ Status = 'Restored'; Restored = $true; Verified = $true; GuardReleased = $true; IsSuccessful = $true; IsComplete = $true } }
                Mock Set-CgrRepositoryProtectionConfiguration { [pscustomobject] @{ Status = 'Restored'; Restored = @(); Skipped = @(); IsSuccessful = $true; IsComplete = $true } }

                $verification = [pscustomobject] @{ IsSuccessful = $true }
                $result = Invoke-CgrPostVerificationConfigurationRestore -Plan $plan -SourceRepository $source -DestinationRepository $destination -Verification $verification -VerificationFailureReason 'ContentVerificationFailed' -CompletedSteps $steps -FailureStage ([ref] $failureStage)

                @($steps.Name) | Should -Be @('RestoreSupportedSettings', 'RestoreGitHubPages', 'RestoreRepositoryProtection')
                $result.PagesRestored | Should -BeTrue
                $verification.Pages.Status | Should -Be 'Restored'

                $failedSteps = [System.Collections.Generic.List[object]]::new()
                $failedStage = 'VerifyDestinationContent'
                $failedVerification = [pscustomobject] @{ IsSuccessful = $false }
                $failedResult = Invoke-CgrPostVerificationConfigurationRestore -Plan $plan -SourceRepository $source -DestinationRepository $destination -Verification $failedVerification -VerificationFailureReason 'ContentVerificationFailed' -CompletedSteps $failedSteps -FailureStage ([ref] $failedStage)
                $failedResult.Pages.Status | Should -Be 'ContentVerificationFailed'
            }
        }
    }
}
