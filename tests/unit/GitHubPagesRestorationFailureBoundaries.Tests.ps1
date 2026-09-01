BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1') -Force
}

Describe 'GitHub Pages restoration failure boundaries' {
    It 'restores the exact reviewed branch/path configuration when destination source exists' {
        InModuleScope CopyGitHubRepo {
            $drift = [pscustomobject] @{ Configured = $true; BuildType = 'legacy'; Branch = 'pages'; Path = '/docs'; CustomDomain = $null; HttpsEnforced = $false }
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'; ContentMode = 'FullHistory'; SourceState = [pscustomobject] @{ Refs = @('refs/heads/pages abc') }
                Pages = [pscustomobject] @{
                    Configured = $true; BuildType = 'legacy'; Source = [pscustomobject] @{ Branch = 'pages'; Path = '/docs' }
                    CustomDomain = $null; HttpsEnforced = $false
                    Representability = [pscustomobject] @{ IsRepresentable = $true; Reason = 'Supported' }
                    DriftEvidence = $drift
                }
            }
            $script:created = $false
            Mock Get-CgrGitHubPagesPlanEvidence { [pscustomobject] @{ DriftEvidence = $drift } }
            Mock Get-CgrGitHubApiOptional {
                if ($Path -eq 'repos/acme/destination/pages') {
                    if ($script:created) { return [pscustomobject] @{ build_type = 'legacy'; source = [pscustomobject] @{ branch = 'pages'; path = '/docs' }; cname = $null; https_enforced = $false } }
                    return $null
                }
                if ($Path -eq 'repos/acme/destination/branches/pages') { return [pscustomobject] @{ name = 'pages' } }
                if ($Path -eq 'repos/acme/destination/contents/docs?ref=pages') { return @([pscustomobject] @{ name = 'index.html' }) }
                throw "Unexpected read: $Path"
            }
            Mock Invoke-CgrGitHubApiMutation {
                if ($Method -eq 'POST' -and $Path -eq '/repos/acme/destination/pages') { $script:created = $true }
            }
            Mock Get-CgrGitHubApi { [pscustomobject] @{ enabled = $true } }

            $result = Restore-CgrGitHubPagesConfiguration -Plan $plan -SourceRepository ([pscustomobject] @{ FullName = 'acme/source' }) -DestinationRepository ([pscustomobject] @{ FullName = 'acme/destination' })

            $result.BuildType | Should -Be 'legacy'
            $result.Source.Branch | Should -Be 'pages'
            $result.Source.Path | Should -Be '/docs'
            Should -Invoke Invoke-CgrGitHubApiMutation -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Path -eq '/repos/acme/destination/pages' -and
                $Body.build_type -eq 'legacy' -and $Body.source.branch -eq 'pages' -and $Body.source.path -eq '/docs'
            }
        }
    }

    It 'fails before guard release when destination Pages readback disagrees' {
        InModuleScope CopyGitHubRepo {
            $drift = [pscustomobject] @{ Configured = $true; BuildType = 'workflow'; Branch = $null; Path = $null; CustomDomain = $null; HttpsEnforced = $true }
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'; ContentMode = 'Snapshot'; SourceState = [pscustomobject] @{}
                Pages = [pscustomobject] @{ Configured = $true; BuildType = 'workflow'; CustomDomain = $null; HttpsEnforced = $true; Representability = [pscustomobject] @{ IsRepresentable = $true }; DriftEvidence = $drift }
            }
            $script:created = $false
            Mock Get-CgrGitHubPagesPlanEvidence { [pscustomobject] @{ DriftEvidence = $drift } }
            Mock Get-CgrGitHubApiOptional {
                if (-not $script:created) { return $null }
                [pscustomobject] @{ build_type = 'legacy'; source = [pscustomobject] @{ branch = 'main'; path = '/' }; cname = $null; https_enforced = $true }
            }
            Mock Invoke-CgrGitHubApiMutation {
                if ($Path -eq '/repos/acme/destination/pages') { $script:created = $true }
            }
            Mock Get-CgrGitHubApi { throw 'guard must remain disabled' }

            { Restore-CgrGitHubPagesConfiguration -Plan $plan -SourceRepository ([pscustomobject] @{ FullName = 'acme/source' }) -DestinationRepository ([pscustomobject] @{ FullName = 'acme/destination' }) } |
                Should -Throw -ErrorId 'DestinationPagesVerificationFailed,Assert-CgrDestinationPagesReadBack'
            Should -Invoke Invoke-CgrGitHubApiMutation -Times 0 -Exactly -ParameterFilter { $Path -eq '/repos/acme/destination/actions/permissions' }
        }
    }

    It 'fails closed when the temporary guard cannot be released after verified Pages restoration' {
        InModuleScope CopyGitHubRepo {
            $drift = [pscustomobject] @{ Configured = $false; BuildType = $null; Branch = $null; Path = $null; CustomDomain = $null; HttpsEnforced = $null }
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'; ContentMode = 'Snapshot'; SourceState = [pscustomobject] @{}
                Pages = [pscustomobject] @{ Configured = $false; BuildType = $null; Representability = [pscustomobject] @{ IsRepresentable = $true }; DriftEvidence = $drift }
            }
            Mock Get-CgrGitHubPagesPlanEvidence { [pscustomobject] @{ DriftEvidence = $drift } }
            Mock Get-CgrGitHubApiOptional { $null }
            Mock Invoke-CgrGitHubApiMutation {}
            Mock Get-CgrGitHubApi { [pscustomobject] @{ enabled = $false } }

            { Restore-CgrGitHubPagesConfiguration -Plan $plan -SourceRepository ([pscustomobject] @{ FullName = 'acme/source' }) -DestinationRepository ([pscustomobject] @{ FullName = 'acme/destination' }) } |
                Should -Throw -ErrorId 'PagesWorkflowActivationGuardReleaseFailed,Enable-CgrPagesWorkflowActivationAfterRestore'
        }
    }

    It 'revalidates same-name replacement Pages state against the preserved archive identity' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                Mode = 'SameNameReplacement'; SourceRepository = 'acme/source'; ArchiveRepository = 'acme/source-archive'
                ContentMode = 'FullHistory'; IncludeReleases = $false; RestorePages = $true; SkipSettings = $true
                Protection = [pscustomobject] @{ Status = 'Captured'; Configuration = [pscustomobject] @{} }
            }
            $verification = [pscustomobject] @{ IsSuccessful = $true }
            $steps = [System.Collections.Generic.List[object]]::new()
            $failureStage = 'VerifyFullHistory'
            Mock Restore-CgrGitHubPagesConfiguration {
                [pscustomobject] @{ Status = 'ReviewedNotConfigured'; Restored = $false; Verified = $true; GuardReleased = $true; IsSuccessful = $true; IsComplete = $true }
            }
            Mock Set-CgrGitHubRepositorySetting { throw 'settings are skipped' }
            Mock Set-CgrRepositoryProtectionConfiguration { throw 'protection is skipped' }

            Invoke-CgrPostVerificationConfigurationRestore -Plan $plan -SourceRepository ([pscustomobject] @{ FullName = 'acme/source' }) -DestinationRepository ([pscustomobject] @{ FullName = 'acme/source' }) -Verification $verification -VerificationFailureReason 'FullHistoryVerificationFailed' -CompletedSteps $steps -FailureStage ([ref] $failureStage) | Out-Null

            Should -Invoke Restore-CgrGitHubPagesConfiguration -Times 1 -Exactly -ParameterFilter { $SourceRepository.FullName -eq 'acme/source-archive' }
        }
    }
}
