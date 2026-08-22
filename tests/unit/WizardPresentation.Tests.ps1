BeforeAll {
    $script:repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $script:repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force
}

Describe 'Wizard semantic presentation' {
    It 'applies semantic heading styling only when terminal styling is available' {
        InModuleScope CopyGitHubRepo {
            Mock Test-CgrConsoleStylingAvailable { $true }

            $formatted = Format-CgrWizardText -Text 'Heading' -Style Heading

            $formatted | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightCyan))
            $formatted | Should -Match 'Heading'
            $formatted | Should -Match ([regex]::Escape($PSStyle.Reset))
        }
    }

    It 'returns plain text when semantic styling is disabled' {
        InModuleScope CopyGitHubRepo {
            Mock Test-CgrConsoleStylingAvailable { $true }

            Format-CgrWizardText -Text 'Heading' -Style Heading -NoStyle |
                Should -BeExactly 'Heading'
        }
    }

    It 'honors NO_COLOR before considering terminal rendering capabilities' {
        InModuleScope CopyGitHubRepo {
            $previousNoColor = $env:NO_COLOR
            try {
                $env:NO_COLOR = '1'
                Test-CgrConsoleStylingAvailable | Should -BeFalse
            }
            finally {
                $env:NO_COLOR = $previousNoColor
            }
        }
    }

    It 'keeps the first repository visually neutral when no selection or unique default exists' {
        InModuleScope CopyGitHubRepo {
            $repositories = @(
                [pscustomobject] @{ FullName = 'infoconex/one' }
                [pscustomobject] @{ FullName = 'infoconex/two' }
            )
            $script:messages = [System.Collections.Generic.List[string]]::new()
            Mock Write-CgrWizardMessage {
                if (-not [string]::IsNullOrEmpty($Message)) {
                    $script:messages.Add($Message)
                }
            }
            Mock Read-CgrWizardInput { '2' }

            $result = Select-CgrWizardRepository -Repositories $repositories -AllowCancel

            $result.Value.FullName | Should -Be 'infoconex/two'
            ($script:messages -join "`n") | Should -Not -Match '1\. infoconex/one \(default\)'
        }
    }

    It 'renders a concise completion summary with the important human evidence' {
        InModuleScope CopyGitHubRepo {
            $result = [pscustomobject] @{
                DestinationRepository = 'infoconex/destination'
                DestinationHtmlUrl = 'https://github.com/infoconex/destination'
                IsVerified = $true
                SettingsRestored = $true
                ProtectionRestored = $true
                Plan = [pscustomobject] @{
                    ArchiveRepository = 'infoconex/destination-archive'
                    ContentMode = 'Snapshot'
                    SkipSettings = $false
                }
                Provenance = [pscustomobject] @{
                    SourceCommitSha = 'source-commit'
                    SourceTreeSha = 'source-tree'
                    DestinationRootCommitSha = 'destination-root'
                }
                Protection = [pscustomobject] @{ Skipped = @() }
            }
            $script:messages = [System.Collections.Generic.List[string]]::new()
            Mock Write-CgrWizardMessage {
                if (-not [string]::IsNullOrEmpty($Message)) {
                    $script:messages.Add($Message)
                }
            }

            Write-CgrWizardCompletionSummary -Result $result -ReportPath '/tmp/report.md'

            $rendered = $script:messages -join "`n"
            $rendered | Should -Match 'Destination: infoconex/destination'
            $rendered | Should -Match 'Archive: infoconex/destination-archive'
            $rendered | Should -Match 'Mode: Snapshot'
            $rendered | Should -Match 'Source commit: source-commit'
            $rendered | Should -Match 'Source tree: source-tree'
            $rendered | Should -Match 'Snapshot root commit: destination-root'
            $rendered | Should -Match 'Report: /tmp/report.md'
        }
    }

    It 'does not emit the raw migration execution result from the public wizard success path' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrRepositoryCopyWizard {
                [pscustomobject] @{
                    PSTypeName = 'CopyGitHubRepo.MigrationExecutionResult'
                    Plan = [pscustomobject] @{ ContentMode = 'Snapshot' }
                    CompletedSteps = @([pscustomobject] @{ Name = 'CopySnapshot' })
                }
            }

            $output = @(Start-CopyGitHubRepositoryWizard -Confirm:$false)

            $output.Count | Should -Be 0
        }
    }
}
