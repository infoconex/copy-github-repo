BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1') -Force
}

Describe 'Repository protection restoration status' {
    It 'returns a successful NotApplicable result when no transferable protection exists' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'infoconex/source'; DefaultBranch = 'main' }
            $destination = [pscustomobject] @{ FullName = 'infoconex/destination'; DefaultBranch = 'main' }
            $configuration = [pscustomobject] @{
                Rulesets = @()
                BranchProtection = $null
                Unsupported = @()
            }

            Mock Get-CgrRepositoryProtectionConfiguration { $configuration }
            Mock Invoke-CgrGitHubApiMutation { throw 'No protection mutation should occur for an empty configuration.' }

            $result = Set-CgrRepositoryProtectionConfiguration `
                -SourceRepository $source `
                -DestinationRepository $destination `
                -SourceConfiguration $configuration

            $result.Status | Should -Be 'NotApplicable'
            $result.IsSuccessful | Should -BeTrue
            $result.IsComplete | Should -BeTrue
            @($result.Restored).Count | Should -Be 0
            @($result.Skipped).Count | Should -Be 0
            Should -Invoke Invoke-CgrGitHubApiMutation -Times 0 -Exactly
        }
    }

    It 'distinguishes partial and unsupported successful outcomes' {
        InModuleScope CopyGitHubRepo {
            $partial = [pscustomobject] @{ Status = 'Partial'; Restored = @('rule'); Skipped = @('unsupported'); IsSuccessful = $true; IsComplete = $false }
            $unsupported = [pscustomobject] @{ Status = 'Unsupported'; Restored = @(); Skipped = @('unsupported'); IsSuccessful = $true; IsComplete = $false }

            (Get-CgrActivityTerminalState -Name 'RestoreRepositoryProtection' -Result $partial) | Should -Be 'Warning'
            (Get-CgrActivityTerminalState -Name 'RestoreRepositoryProtection' -Result $unsupported) | Should -Be 'Warning'
        }
    }

    It 'renders every meaningful protection outcome with distinct completion semantics' {
        InModuleScope CopyGitHubRepo {
            $cases = @(
                [pscustomobject] @{ Status = 'Restored'; Restored = @('ruleset'); Skipped = @(); IsSuccessful = $true; IsComplete = $true; Expected = 'Restore transferable repository protection'; Heading = 'Repository copy complete' }
                [pscustomobject] @{ Status = 'NotApplicable'; Restored = @(); Skipped = @(); IsSuccessful = $true; IsComplete = $true; Expected = 'No transferable repository protection to restore.'; Heading = 'Repository copy complete' }
                [pscustomobject] @{ Status = 'Skipped'; Restored = @(); Skipped = @('Policy'); IsSuccessful = $true; IsComplete = $false; Expected = 'Repository protection restoration was skipped.'; Heading = 'Repository copy complete' }
                [pscustomobject] @{ Status = 'Unsupported'; Restored = @(); Skipped = @('Ruleset:UnsupportedRule'); IsSuccessful = $true; IsComplete = $false; Expected = 'Repository protection was not transferable'; Heading = 'Repository copy completed with warnings' }
                [pscustomobject] @{ Status = 'Partial'; Restored = @('ruleset'); Skipped = @('Ruleset:UnsupportedRule'); IsSuccessful = $true; IsComplete = $false; Expected = 'Repository protection was only partially restored.'; Heading = 'Repository copy completed with warnings' }
                [pscustomobject] @{ Status = 'Failed'; Restored = @(); Skipped = @(); IsSuccessful = $false; IsComplete = $false; Expected = 'Repository protection restoration failed.'; Heading = 'Repository copy completed with warnings' }
            )

            foreach ($case in $cases) {
                $script:messages = [System.Collections.Generic.List[string]]::new()
                Mock Write-CgrWizardMessage { param($Message) if ($Message) { $script:messages.Add([string] $Message) } }
                $result = [pscustomobject] @{
                    DestinationRepository = 'infoconex/destination'
                    DestinationHtmlUrl = 'https://example.invalid/infoconex/destination'
                    IsVerified = $true
                    SettingsRestored = $true
                    ProtectionRestored = $case.Status -eq 'Restored'
                    Settings = [pscustomobject] @{ IsSuccessful = $true }
                    Protection = $case
                    Plan = [pscustomobject] @{ ContentMode = 'Snapshot'; SkipSettings = $false; ArchiveRepository = $null }
                    Provenance = $null
                }

                Write-CgrWizardCompletionSummary -Result $result
                $text = $script:messages -join "`n"
                $text | Should -Match ([regex]::Escape($case.Expected))
                $text | Should -Match ([regex]::Escape($case.Heading))
                $text.IndexOf($case.Expected) | Should -BeLessThan $text.IndexOf($case.Heading)
            }
        }
    }
}
