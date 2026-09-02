BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $root 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Wizard GitHub Pages restoration' {
    It 'opts into Pages, reviews Actions-based evidence, and delegates the exact reviewed plan' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'infoconex/source'; Owner = 'infoconex'; Visibility = 'public' }
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                ArchiveRepository = $null
                ContentMode = 'FullHistory'
                DestinationVisibility = 'public'
                RestorePages = $true
                SourceState = [pscustomobject] @{ ContentMode = 'FullHistory'; Refs = @('refs/heads/main abc'); ReachableCommitCount = 1; DefaultBranch = 'main' }
                Pages = [pscustomobject] @{
                    Status = 'Configured'
                    Configured = $true
                    BuildType = 'workflow'
                    Source = $null
                    CustomDomain = 'docs.example.com'
                    HttpsEnforced = $true
                    Representability = [pscustomobject] @{ IsRepresentable = $true; Reason = 'Supported.' }
                    ExternalReadiness = [pscustomobject] @{
                        DomainVerification = 'verified'
                        Certificate = [pscustomobject] @{ state = 'approved' }
                        Dns = 'ExternalNotQueried'
                    }
                }
                Steps = @([pscustomobject] @{ Description = 'Restore GitHub Pages from approved plan evidence.' })
            }
            Mock Write-CgrWizardMessage
            Mock Get-GitHubRepository { @($source) }
            Mock Select-CgrWizardRepository { ConvertTo-CgrWizardNavigationResult -Action Next -Value $source }
            Mock Test-CgrGitHubRepositoryExistence { $false }
            Mock Read-CgrWizardRepositoryName { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'infoconex/destination' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'FullHistory' } -ParameterFilter { $Title -eq 'Content mode' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'public' } -ParameterFilter { $Title -eq 'Destination visibility' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Restore settings + GitHub Pages' } -ParameterFilter { $Title -eq 'Supported repository settings' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Execute' } -ParameterFilter { $Title -eq 'Repository copy plan' }
            Mock Copy-GitHubRepository { $plan } -ParameterFilter { $PlanOnly }
            Mock Invoke-CgrApprovedMigrationPlan { [pscustomobject] @{ Status = 'Completed'; Plan = $Plan; CompletedSteps = @() } }

            Invoke-CgrRepositoryCopyWizard -HostName github.com -ExecutionGuard { $true } | Out-Null

            Should -Invoke Copy-GitHubRepository -Times 1 -Exactly -ParameterFilter { $PlanOnly -and $RestorePages -and -not $SkipSettings }
            Should -Invoke Invoke-CgrApprovedMigrationPlan -Times 1 -Exactly -ParameterFilter { [object]::ReferenceEquals($Plan, $plan) }
            Should -Invoke Write-CgrWizardMessage -ParameterFilter { $Message -match 'GitHub Actions \(workflow-based Pages\)' }
            Should -Invoke Write-CgrWizardMessage -ParameterFilter { $Message -match 'Custom domain: docs\.example\.com' }
            Should -Invoke Write-CgrWizardMessage -ParameterFilter { $Message -match 'HTTPS enforcement intent: True' }
            Should -Invoke Write-CgrWizardMessage -ParameterFilter { $Message -match 'Domain verification readiness: verified' }
            Should -Invoke Write-CgrWizardMessage -ParameterFilter { $Message -match 'Certificate readiness: approved' }
            Should -Invoke Write-CgrWizardMessage -ParameterFilter { $Message -match 'DNS evidence: ExternalNotQueried' }
            Should -Invoke Write-CgrWizardMessage -ParameterFilter { $Message -match 'does not discover or mutate external DNS' }
        }
    }

    It 'shows a reviewed source with no Pages configured without inventing restoration work' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'infoconex/source'; Owner = 'infoconex'; Visibility = 'public' }
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'; SourceRepository = 'infoconex/source'; DestinationRepository = 'infoconex/destination'; ArchiveRepository = $null
                ContentMode = 'FullHistory'; DestinationVisibility = 'public'; RestorePages = $true
                SourceState = [pscustomobject] @{ ContentMode = 'FullHistory'; Refs = @('refs/heads/main abc'); ReachableCommitCount = 1; DefaultBranch = 'main' }
                Pages = [pscustomobject] @{ Status = 'NotConfigured'; Configured = $false; BuildType = $null; Source = $null; CustomDomain = $null; HttpsEnforced = $false }
                Steps = @()
            }
            Mock Write-CgrWizardMessage
            Mock Get-GitHubRepository { @($source) }
            Mock Select-CgrWizardRepository { ConvertTo-CgrWizardNavigationResult -Action Next -Value $source }
            Mock Test-CgrGitHubRepositoryExistence { $false }
            Mock Read-CgrWizardRepositoryName { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'infoconex/destination' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'FullHistory' } -ParameterFilter { $Title -eq 'Content mode' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'public' } -ParameterFilter { $Title -eq 'Destination visibility' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Skip settings + restore GitHub Pages' } -ParameterFilter { $Title -eq 'Supported repository settings' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Execute' } -ParameterFilter { $Title -eq 'Repository copy plan' }
            Mock Copy-GitHubRepository { $plan } -ParameterFilter { $PlanOnly }
            Mock Invoke-CgrApprovedMigrationPlan { [pscustomobject] @{ Status = 'Completed'; Plan = $Plan; CompletedSteps = @() } }

            Invoke-CgrRepositoryCopyWizard -HostName github.com -ExecutionGuard { $true } | Out-Null

            Should -Invoke Copy-GitHubRepository -Times 1 -Exactly -ParameterFilter { $PlanOnly -and $RestorePages -and $SkipSettings }
            Should -Invoke Write-CgrWizardMessage -ParameterFilter { $Message -match 'Source Pages status: NotConfigured' }
            Should -Invoke Write-CgrWizardMessage -ParameterFilter { $Message -match 'will not create a destination Pages site' }
        }
    }

    It 'distinguishes reviewed branch/path Pages and surfaces unsupported representability accurately' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'infoconex/source'; Owner = 'infoconex'; Visibility = 'public' }
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'; SourceRepository = 'infoconex/source'; DestinationRepository = 'infoconex/destination'; ArchiveRepository = $null
                ContentMode = 'FullHistory'; DestinationVisibility = 'public'; RestorePages = $true
                SourceState = [pscustomobject] @{ ContentMode = 'FullHistory'; Refs = @('refs/heads/gh-pages abc'); ReachableCommitCount = 1; DefaultBranch = 'main' }
                Pages = [pscustomobject] @{
                    Status = 'Unsupported'; Configured = $true; BuildType = 'legacy'
                    Source = [pscustomobject] @{ Branch = 'gh-pages'; Path = '/docs' }
                    CustomDomain = $null; HttpsEnforced = $false
                    Representability = [pscustomobject] @{ IsRepresentable = $false; Reason = 'This reviewed Pages configuration is not supported for restoration.' }
                    ExternalReadiness = [pscustomobject] @{ DomainVerification = 'NotApplicable'; Certificate = 'NotReportedByGitHub'; Dns = 'ExternalNotQueried' }
                }
                Steps = @()
            }
            Mock Write-CgrWizardMessage
            Mock Get-GitHubRepository { @($source) }
            Mock Select-CgrWizardRepository { ConvertTo-CgrWizardNavigationResult -Action Next -Value $source }
            Mock Test-CgrGitHubRepositoryExistence { $false }
            Mock Read-CgrWizardRepositoryName { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'infoconex/destination' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'FullHistory' } -ParameterFilter { $Title -eq 'Content mode' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'public' } -ParameterFilter { $Title -eq 'Destination visibility' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Restore settings + GitHub Pages' } -ParameterFilter { $Title -eq 'Supported repository settings' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Cancel' } -ParameterFilter { $Title -eq 'Repository copy plan' }
            Mock Copy-GitHubRepository { $plan } -ParameterFilter { $PlanOnly }
            Mock Invoke-CgrApprovedMigrationPlan

            Invoke-CgrRepositoryCopyWizard -HostName github.com -ExecutionGuard { $true } | Out-Null

            Should -Invoke Write-CgrWizardMessage -ParameterFilter { $Message -match 'legacy \(branch/path-based Pages\)' }
            Should -Invoke Write-CgrWizardMessage -ParameterFilter { $Message -match 'Publishing source: gh-pages/docs' }
            Should -Invoke Write-CgrWizardMessage -ParameterFilter { $Message -match 'not restorable from this reviewed plan' }
            Should -Invoke Write-CgrWizardMessage -ParameterFilter { $Message -match 'not supported for restoration' }
            Should -Invoke Invoke-CgrApprovedMigrationPlan -Times 0 -Exactly
        }
    }

    It 'shows same-name custom-domain handoff before collecting destructive authority' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'infoconex/source'; Owner = 'infoconex'; Visibility = 'public' }
            $expected = 'SOURCE=infoconex/source;ARCHIVE=infoconex/source-archive;REPLACEMENT=infoconex/source'
            $plan = [pscustomobject] @{
                Mode = 'SameNameReplacement'; SourceRepository = 'infoconex/source'; DestinationRepository = 'infoconex/source'; ArchiveRepository = 'infoconex/source-archive'
                ContentMode = 'FullHistory'; DestinationVisibility = 'public'; RestorePages = $true
                SourceState = [pscustomobject] @{ ContentMode = 'FullHistory'; Refs = @('refs/heads/main abc'); ReachableCommitCount = 1; DefaultBranch = 'main' }
                Pages = [pscustomobject] @{
                    Status = 'Configured'; Configured = $true; BuildType = 'workflow'; Source = $null; CustomDomain = 'docs.example.com'; HttpsEnforced = $true
                    Representability = [pscustomobject] @{ IsRepresentable = $true; Reason = 'Supported.' }
                    ExternalReadiness = [pscustomobject] @{ DomainVerification = 'verified'; Certificate = [pscustomobject] @{ state = 'approved' }; Dns = 'ExternalNotQueried' }
                }
                Steps = @([pscustomobject] @{ Description = 'Hand off the reviewed Pages custom domain.' })
            }
            $script:sequence = @()
            Mock Write-CgrWizardMessage {
                if ([string] $Message -match 'Same-name replacement must hand off custom-domain ownership') {
                    $script:sequence += 'handoff-warning'
                }
            }
            Mock Get-GitHubRepository { @($source) }
            Mock Select-CgrWizardRepository { ConvertTo-CgrWizardNavigationResult -Action Next -Value $source }
            Mock Read-CgrWizardRepositoryName { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'infoconex/source' } -ParameterFilter { $Kind -eq 'Destination' }
            Mock Read-CgrWizardRepositoryName { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'source-archive' } -ParameterFilter { $Kind -eq 'Archive' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'FullHistory' } -ParameterFilter { $Title -eq 'Content mode' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'public' } -ParameterFilter { $Title -eq 'Destination visibility' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Restore settings + GitHub Pages' } -ParameterFilter { $Title -eq 'Supported repository settings' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Execute' } -ParameterFilter { $Title -eq 'Repository copy plan' }
            Mock Read-CgrWizardInput { $script:sequence += 'destructive-confirmation'; $expected }
            Mock Copy-GitHubRepository { $plan } -ParameterFilter { $PlanOnly }
            Mock Invoke-CgrApprovedMigrationPlan { [pscustomobject] @{ Status = 'Completed'; Plan = $Plan; CompletedSteps = @() } }

            Invoke-CgrRepositoryCopyWizard -HostName github.com -ExecutionGuard { $true } | Out-Null

            $script:sequence | Should -Be @('handoff-warning', 'destructive-confirmation')
            Should -Invoke Invoke-CgrApprovedMigrationPlan -Times 1 -Exactly -ParameterFilter {
                [object]::ReferenceEquals($Plan, $plan) -and $SameNameConfirmation -ceq $expected
            }
        }
    }

    It 'preserves Back and Cancel behavior around the Pages-capable settings choice' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'infoconex/source'; Owner = 'infoconex'; Visibility = 'public' }
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'; SourceRepository = 'infoconex/source'; DestinationRepository = 'infoconex/destination'; ArchiveRepository = $null
                ContentMode = 'FullHistory'; DestinationVisibility = 'public'; RestorePages = $true
                SourceState = [pscustomobject] @{ ContentMode = 'FullHistory'; Refs = @('refs/heads/main abc'); ReachableCommitCount = 1; DefaultBranch = 'main' }
                Pages = [pscustomobject] @{ Status = 'NotConfigured'; Configured = $false; BuildType = $null; Source = $null; CustomDomain = $null; HttpsEnforced = $false }
                Steps = @()
            }
            $script:settingsCalls = 0
            Mock Write-CgrWizardMessage
            Mock Get-GitHubRepository { @($source) }
            Mock Select-CgrWizardRepository { ConvertTo-CgrWizardNavigationResult -Action Next -Value $source }
            Mock Test-CgrGitHubRepositoryExistence { $false }
            Mock Read-CgrWizardRepositoryName { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'infoconex/destination' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'FullHistory' } -ParameterFilter { $Title -eq 'Content mode' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'public' } -ParameterFilter { $Title -eq 'Destination visibility' }
            Mock Read-CgrWizardChoice {
                $script:settingsCalls++
                if ($script:settingsCalls -eq 1) { return ConvertTo-CgrWizardNavigationResult -Action Back }
                ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Restore settings + GitHub Pages'
            } -ParameterFilter { $Title -eq 'Supported repository settings' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Cancel } -ParameterFilter { $Title -eq 'Repository copy plan' }
            Mock Copy-GitHubRepository { $plan } -ParameterFilter { $PlanOnly }
            Mock Invoke-CgrApprovedMigrationPlan

            $result = Invoke-CgrRepositoryCopyWizard -HostName github.com -ExecutionGuard { $true }

            $result.Status | Should -Be 'Cancelled'
            $script:settingsCalls | Should -Be 2
            Should -Invoke Read-CgrWizardChoice -Times 2 -Exactly -ParameterFilter { $Title -eq 'Destination visibility' }
            Should -Invoke Copy-GitHubRepository -Times 1 -Exactly -ParameterFilter { $PlanOnly -and $RestorePages }
            Should -Invoke Invoke-CgrApprovedMigrationPlan -Times 0 -Exactly
        }
    }

    It 'regenerates a stale Pages plan and still crosses only the approved-plan execution boundary' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'infoconex/source'; Owner = 'infoconex'; Visibility = 'public' }
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'; SourceRepository = 'infoconex/source'; DestinationRepository = 'infoconex/destination'; ArchiveRepository = $null
                ContentMode = 'FullHistory'; DestinationVisibility = 'public'; RestorePages = $true
                SourceState = [pscustomobject] @{ ContentMode = 'FullHistory'; Refs = @('refs/heads/main abc'); ReachableCommitCount = 1; DefaultBranch = 'main' }
                Pages = [pscustomobject] @{ Status = 'NotConfigured'; Configured = $false; BuildType = $null; Source = $null; CustomDomain = $null; HttpsEnforced = $false }
                Steps = @()
            }
            $script:executionCalls = 0
            Mock Write-CgrWizardMessage
            Mock Get-GitHubRepository { @($source) }
            Mock Select-CgrWizardRepository { ConvertTo-CgrWizardNavigationResult -Action Next -Value $source }
            Mock Test-CgrGitHubRepositoryExistence { $false }
            Mock Read-CgrWizardRepositoryName { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'infoconex/destination' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'FullHistory' } -ParameterFilter { $Title -eq 'Content mode' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'public' } -ParameterFilter { $Title -eq 'Destination visibility' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Restore settings + GitHub Pages' } -ParameterFilter { $Title -eq 'Supported repository settings' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Execute' } -ParameterFilter { $Title -eq 'Repository copy plan' }
            Mock Copy-GitHubRepository { $plan } -ParameterFilter { $PlanOnly }
            Mock Invoke-CgrApprovedMigrationPlan {
                $script:executionCalls++
                if ($script:executionCalls -eq 1) {
                    $exception = [System.InvalidOperationException]::new('Source state changed after planning.')
                    $record = [System.Management.Automation.ErrorRecord]::new($exception, 'SourceStateChangedSincePlanning', [System.Management.Automation.ErrorCategory]::InvalidOperation, $Plan)
                    throw $record
                }
                [pscustomobject] @{ Status = 'Completed'; Plan = $Plan; CompletedSteps = @() }
            }

            $result = Invoke-CgrRepositoryCopyWizard -HostName github.com -ExecutionGuard { $true }

            $result.Status | Should -Be 'Completed'
            Should -Invoke Copy-GitHubRepository -Times 2 -Exactly -ParameterFilter { $PlanOnly -and $RestorePages }
            Should -Invoke Invoke-CgrApprovedMigrationPlan -Times 2 -Exactly -ParameterFilter { [object]::ReferenceEquals($Plan, $plan) }
        }
    }

    It 'keeps omitted Pages flows free of RestorePages planning authority' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'infoconex/source'; Owner = 'infoconex'; Visibility = 'public' }
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'; SourceRepository = 'infoconex/source'; DestinationRepository = 'infoconex/destination'; ArchiveRepository = $null
                ContentMode = 'FullHistory'; DestinationVisibility = 'public'
                SourceState = [pscustomobject] @{ ContentMode = 'FullHistory'; Refs = @('refs/heads/main abc'); ReachableCommitCount = 1; DefaultBranch = 'main' }
                Steps = @()
            }
            Mock Write-CgrWizardMessage
            Mock Get-GitHubRepository { @($source) }
            Mock Select-CgrWizardRepository { ConvertTo-CgrWizardNavigationResult -Action Next -Value $source }
            Mock Test-CgrGitHubRepositoryExistence { $false }
            Mock Read-CgrWizardRepositoryName { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'infoconex/destination' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'FullHistory' } -ParameterFilter { $Title -eq 'Content mode' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'public' } -ParameterFilter { $Title -eq 'Destination visibility' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Restore' } -ParameterFilter { $Title -eq 'Supported repository settings' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Execute' } -ParameterFilter { $Title -eq 'Repository copy plan' }
            Mock Copy-GitHubRepository { $plan } -ParameterFilter { $PlanOnly }
            Mock Invoke-CgrApprovedMigrationPlan { [pscustomobject] @{ Status = 'Completed'; Plan = $Plan; CompletedSteps = @() } }

            Invoke-CgrRepositoryCopyWizard -HostName github.com -ExecutionGuard { $true } | Out-Null

            Should -Invoke Copy-GitHubRepository -Times 1 -Exactly -ParameterFilter { $PlanOnly -and -not $RestorePages }
            Should -Invoke Write-CgrWizardMessage -Times 0 -Exactly -ParameterFilter { $Message -match 'Source Pages status:' }
            Should -Invoke Invoke-CgrApprovedMigrationPlan -Times 1 -Exactly -ParameterFilter { [object]::ReferenceEquals($Plan, $plan) }
        }
    }
}
