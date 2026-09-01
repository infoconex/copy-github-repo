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
                Should -Throw -ErrorId 'DestinationPagesPathMissing'
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
                Should -Throw -ErrorId 'PagesStateChangedSincePlanning'
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

    It 'safely hands off the exact reviewed domain for same-name Snapshot and FullHistory replacements' {
        InModuleScope CopyGitHubRepo {
            foreach ($contentMode in @('Snapshot', 'FullHistory')) {
                $drift = [pscustomobject] @{ Configured = $true; BuildType = 'workflow'; Branch = $null; Path = $null; CustomDomain = 'www.example.com'; HttpsEnforced = $true }
                $plan = [pscustomobject] @{
                    Mode = 'SameNameReplacement'; ContentMode = $contentMode; ArchiveRepository = 'acme/source-archive'
                    SourceState = [pscustomobject] @{ RepositoryId = 10 }
                    Pages = [pscustomobject] @{
                        Configured = $true; BuildType = 'workflow'; Source = $null; CustomDomain = 'www.example.com'; HttpsEnforced = $true
                        Representability = [pscustomobject] @{ IsRepresentable = $true }; DriftEvidence = $drift
                        ExternalReadiness = [pscustomobject] @{ DomainVerification = 'verified'; Certificate = 'approved'; Dns = 'ExternalNotQueried' }
                    }
                }
                $source = [pscustomobject] @{ FullName = 'acme/source-archive' }
                $destination = [pscustomobject] @{ FullName = 'acme/source'; Id = 20 }
                $steps = [System.Collections.Generic.List[object]]::new()
                $failureStage = 'RestoreGitHubPages'
                $script:released = $false
                $script:created = $false
                $script:claimed = $false
                $script:events = [System.Collections.Generic.List[string]]::new()

                Mock Get-CgrGitHubPagesPlanEvidence { [pscustomobject] @{ DriftEvidence = $drift } }
                Mock Get-CgrRepository {
                    if ($Repository -eq 'acme/source-archive') { return [pscustomobject] @{ FullName = 'acme/source-archive'; Id = 10 } }
                    if ($Repository -eq 'acme/source') { return [pscustomobject] @{ FullName = 'acme/source'; Id = 20 } }
                    throw "Unexpected repository: $Repository"
                }
                Mock Get-CgrGitHubApiOptional {
                    if ($Path -eq 'repos/acme/source/pages') {
                        if (-not $script:created) { return $null }
                        return [pscustomobject] @{ build_type = 'workflow'; source = $null; cname = $(if ($script:claimed) { 'www.example.com' } else { $null }); https_enforced = $true }
                    }
                    if ($Path -eq 'repos/acme/source-archive/pages') {
                        return [pscustomobject] @{ build_type = 'workflow'; cname = $(if ($script:released) { $null } else { 'www.example.com' }); https_enforced = $true }
                    }
                    throw "Unexpected optional read: $Path"
                }
                Mock Invoke-CgrGitHubApiMutation {
                    if ($Path -eq '/repos/acme/source-archive/pages' -and $Method -eq 'PUT') {
                        $Body.ContainsKey('cname') | Should -BeTrue
                        $Body.cname | Should -BeNullOrEmpty
                        $script:released = $true; $script:events.Add('ReleaseArchive'); return
                    }
                    if ($Path -eq '/repos/acme/source/pages' -and $Method -eq 'POST') { $script:created = $true; $script:events.Add('CreatePages'); return }
                    if ($Path -eq '/repos/acme/source/pages' -and $Method -eq 'PUT') {
                        $Body.cname | Should -BeExactly 'www.example.com'
                        $script:claimed = $true; $script:events.Add('ClaimReplacement'); return
                    }
                    if ($Path -eq '/repos/acme/source/actions/permissions') { $script:events.Add('ReleaseGuard'); return }
                    throw "Unexpected mutation: $Method $Path"
                }
                Mock Get-CgrGitHubApi { [pscustomobject] @{ enabled = $true } }

                $result = Restore-CgrGitHubPagesConfiguration -Plan $plan -SourceRepository $source -DestinationRepository $destination -CompletedSteps $steps -FailureStage ([ref] $failureStage)

                $result.CustomDomainStatus | Should -Be 'HandedOff'
                $result.CustomDomain | Should -BeExactly 'www.example.com'
                $result.CustomDomainHandoff.ArchiveReleaseSucceeded | Should -BeTrue
                $result.CustomDomainHandoff.ReplacementClaimSucceeded | Should -BeTrue
                $result.CustomDomainHandoff.ReplacementReadBackSucceeded | Should -BeTrue
                $result.CustomDomainHandoff.AutomaticRollbackAttempted | Should -BeFalse
                $result.DnsMigrated | Should -BeFalse
                $result.ExternalReadiness.Dns | Should -Be 'ExternalNotQueried'
                ($script:events -join ',') | Should -Be 'ReleaseArchive,CreatePages,ClaimReplacement,ReleaseGuard'
                @($steps.Name) | Should -Contain 'ReleaseArchivedPagesCustomDomain'
                @($steps.Name) | Should -Contain 'ClaimReplacementPagesCustomDomain'
            }
        }
    }

    It 'fails before archive release when same-name archive ownership no longer matches the reviewed domain' {
        InModuleScope CopyGitHubRepo {
            $drift = [pscustomobject] @{ Configured = $true; BuildType = 'workflow'; Branch = $null; Path = $null; CustomDomain = 'www.example.com'; HttpsEnforced = $true }
            $plan = [pscustomobject] @{
                Mode = 'SameNameReplacement'; ContentMode = 'Snapshot'; ArchiveRepository = 'acme/source-archive'
                SourceState = [pscustomobject] @{ RepositoryId = 10 }
                Pages = [pscustomobject] @{ Configured = $true; BuildType = 'workflow'; CustomDomain = 'www.example.com'; HttpsEnforced = $true; Representability = [pscustomobject] @{ IsRepresentable = $true }; DriftEvidence = $drift }
            }
            Mock Get-CgrGitHubPagesPlanEvidence { [pscustomobject] @{ DriftEvidence = $drift } }
            Mock Get-CgrRepository {
                if ($Repository -eq 'acme/source-archive') { [pscustomobject] @{ FullName = 'acme/source-archive'; Id = 10 } }
                else { [pscustomobject] @{ FullName = 'acme/source'; Id = 20 } }
            }
            Mock Get-CgrGitHubApiOptional {
                if ($Path -eq 'repos/acme/source/pages') { return $null }
                if ($Path -eq 'repos/acme/source-archive/pages') { return [pscustomobject] @{ cname = 'other.example.com' } }
            }
            Mock Invoke-CgrGitHubApiMutation { throw 'must not mutate' }

            { Restore-CgrGitHubPagesConfiguration -Plan $plan -SourceRepository ([pscustomobject] @{ FullName = 'acme/source-archive' }) -DestinationRepository ([pscustomobject] @{ FullName = 'acme/source'; Id = 20 }) } |
                Should -Throw -ErrorId 'PagesCustomDomainArchiveBindingMismatch'
            Should -Invoke Invoke-CgrGitHubApiMutation -Times 0
        }
    }

    It 'records a durable partial-handoff state and does not roll back when replacement claim fails after archive release' {
        InModuleScope CopyGitHubRepo {
            $drift = [pscustomobject] @{ Configured = $true; BuildType = 'workflow'; Branch = $null; Path = $null; CustomDomain = 'www.example.com'; HttpsEnforced = $true }
            $plan = [pscustomobject] @{
                Mode = 'SameNameReplacement'; ContentMode = 'Snapshot'; ArchiveRepository = 'acme/source-archive'
                SourceState = [pscustomobject] @{ RepositoryId = 10 }
                Pages = [pscustomobject] @{ Configured = $true; BuildType = 'workflow'; CustomDomain = 'www.example.com'; HttpsEnforced = $true; Representability = [pscustomobject] @{ IsRepresentable = $true }; DriftEvidence = $drift; ExternalReadiness = [pscustomobject] @{ Dns = 'ExternalNotQueried' } }
            }
            $steps = [System.Collections.Generic.List[object]]::new()
            $failureStage = 'RestoreGitHubPages'
            $script:released = $false
            Mock Get-CgrGitHubPagesPlanEvidence { [pscustomobject] @{ DriftEvidence = $drift } }
            Mock Get-CgrRepository {
                if ($Repository -eq 'acme/source-archive') { [pscustomobject] @{ FullName = 'acme/source-archive'; Id = 10 } }
                else { [pscustomobject] @{ FullName = 'acme/source'; Id = 20 } }
            }
            Mock Get-CgrGitHubApiOptional {
                if ($Path -eq 'repos/acme/source/pages') { return $null }
                if ($Path -eq 'repos/acme/source-archive/pages') { return [pscustomobject] @{ cname = $(if ($script:released) { $null } else { 'www.example.com' }) } }
            }
            Mock Invoke-CgrGitHubApiMutation {
                if ($Path -eq '/repos/acme/source-archive/pages') { $script:released = $true; return }
                if ($Path -eq '/repos/acme/source/pages' -and $Method -eq 'POST') { return }
                if ($Path -eq '/repos/acme/source/pages' -and $Method -eq 'PUT') { throw 'simulated ownership conflict after release' }
                throw "Unexpected mutation: $Method $Path"
            }
            Mock Get-CgrGitHubApi { throw 'guard must remain active' }

            { Restore-CgrGitHubPagesConfiguration -Plan $plan -SourceRepository ([pscustomobject] @{ FullName = 'acme/source-archive' }) -DestinationRepository ([pscustomobject] @{ FullName = 'acme/source'; Id = 20 }) -CompletedSteps $steps -FailureStage ([ref] $failureStage) } |
                Should -Throw '*simulated ownership conflict after release*'

            $failureStage | Should -Be 'ClaimReplacementPagesCustomDomain'
            $releaseStep = @($steps | Where-Object Name -eq 'ReleaseArchivedPagesCustomDomain')[-1]
            $claimStep = @($steps | Where-Object Name -eq 'ClaimReplacementPagesCustomDomain')[-1]
            $releaseStep.Succeeded | Should -BeTrue
            $releaseStep.Verified | Should -BeTrue
            $claimStep.Attempted | Should -BeTrue
            $claimStep.Succeeded | Should -BeFalse
            $claimStep.AutomaticRollbackAttempted | Should -BeFalse
            Should -Invoke Invoke-CgrGitHubApiMutation -Times 0 -ParameterFilter { $Path -eq '/repos/acme/source/actions/permissions' }
        }
    }

    It 'preserves an unrelated archived destination domain while claiming only reviewed source evidence in delegated replacement modes' {
        InModuleScope CopyGitHubRepo {
            foreach ($contentMode in @('Snapshot', 'FullHistory')) {
                $drift = [pscustomobject] @{ Configured = $true; BuildType = 'workflow'; Branch = $null; Path = $null; CustomDomain = 'source.example.com'; HttpsEnforced = $false }
                $plan = [pscustomobject] @{
                    Mode = 'ExistingDestinationReplacement'; ContentMode = $contentMode; ArchiveRepository = 'acme/destination-archive'
                    SourceState = [pscustomobject] @{}
                    Pages = [pscustomobject] @{ Configured = $true; BuildType = 'workflow'; CustomDomain = 'source.example.com'; HttpsEnforced = $false; Representability = [pscustomobject] @{ IsRepresentable = $true }; DriftEvidence = $drift; ExternalReadiness = [pscustomobject] @{ Dns = 'ExternalNotQueried' } }
                }
                $script:created = $false
                $script:claimed = $false
                Mock Get-CgrGitHubPagesPlanEvidence { [pscustomobject] @{ DriftEvidence = $drift } }
                Mock Get-CgrRepository {
                    if ($Repository -eq 'acme/destination-archive') { [pscustomobject] @{ FullName = 'acme/destination-archive'; Id = 30 } }
                    else { [pscustomobject] @{ FullName = 'acme/destination'; Id = 40 } }
                }
                Mock Get-CgrGitHubApiOptional {
                    if ($Path -eq 'repos/acme/destination/pages') {
                        if (-not $script:created) { return $null }
                        return [pscustomobject] @{ build_type = 'workflow'; cname = $(if ($script:claimed) { 'source.example.com' } else { $null }); https_enforced = $false }
                    }
                    if ($Path -eq 'repos/acme/destination-archive/pages') { return [pscustomobject] @{ cname = 'destination.example.com' } }
                }
                Mock Invoke-CgrGitHubApiMutation {
                    if ($Path -eq '/repos/acme/destination-archive/pages') { throw 'must not release unrelated archived domain' }
                    if ($Path -eq '/repos/acme/destination/pages' -and $Method -eq 'POST') { $script:created = $true; return }
                    if ($Path -eq '/repos/acme/destination/pages' -and $Method -eq 'PUT') { $Body.cname | Should -BeExactly 'source.example.com'; $script:claimed = $true; return }
                    if ($Path -eq '/repos/acme/destination/actions/permissions') { return }
                }
                Mock Get-CgrGitHubApi { [pscustomobject] @{ enabled = $true } }

                $result = Restore-CgrGitHubPagesConfiguration -Plan $plan -SourceRepository ([pscustomobject] @{ FullName = 'acme/source' }) -DestinationRepository ([pscustomobject] @{ FullName = 'acme/destination'; Id = 40 })

                $result.CustomDomainStatus | Should -Be 'HandedOff'
                $result.CustomDomainHandoff.ArchiveReleaseRequired | Should -BeFalse
                $result.CustomDomainHandoff.ArchiveObservedCustomDomain | Should -BeExactly 'destination.example.com'
                Should -Invoke Invoke-CgrGitHubApiMutation -Times 0 -ParameterFilter { $Path -eq '/repos/acme/destination-archive/pages' }
            }
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
