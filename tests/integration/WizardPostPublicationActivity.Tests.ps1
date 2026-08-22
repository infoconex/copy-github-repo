BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1') -Force
}

Describe 'Post-publication wizard activity' {
    It 'reports verification settings and protection in execution order with a protection no-op' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                SourceVisibility = 'public'
                DestinationVisibility = 'public'
                SourceDefaultBranch = 'main'
                CommitMessage = 'Initial repository commit'
                SkipSettings = $false
                SourceState = [pscustomobject] @{
                    RepositoryId = 1L
                    RepositoryNodeId = 'source-node'
                    DefaultBranch = 'main'
                    CommitSha = 'source-commit'
                    TreeSha = 'source-tree'
                }
                Protection = [pscustomobject] @{
                    Status = 'Captured'
                    Configuration = [pscustomobject] @{
                        Rulesets = @()
                        BranchProtection = $null
                        Unsupported = @()
                    }
                }
            }
            $source = [pscustomobject] @{ FullName = 'infoconex/source'; Id = 1L; NodeId = 'source-node'; CloneUrl = 'https://github.com/infoconex/source.git' }
            $destination = [pscustomobject] @{ FullName = 'infoconex/destination'; Id = 2L; NodeId = 'destination-node'; HtmlUrl = 'https://github.com/infoconex/destination'; CloneUrl = 'https://github.com/infoconex/destination.git' }
            $script:events = [System.Collections.Generic.List[object]]::new()

            Mock Send-CgrActivityEvent {
                param($Name, $State, $Message, $Current, $Total)
                $script:events.Add([pscustomobject] @{ Name = $Name; State = $State; Message = $Message; Current = $Current; Total = $Total })
            }
            Mock Copy-CgrRepositorySnapshot {
                [pscustomobject] @{ SourceCommitSha = 'source-commit'; BranchName = 'main'; CommitSha = 'destination-commit'; TreeSha = 'source-tree'; Verified = $true }
            }
            Mock Get-CgrRepository { $destination }
            Mock Invoke-CgrRepositorySnapshotVerification {
                [pscustomobject] @{ IsSuccessful = $true; SourceTree = 'source-tree'; DestinationTree = 'source-tree'; Checks = @() }
            }
            Mock Set-CgrGitHubRepositorySetting {
                [pscustomobject] @{ Restored = @('description'); Skipped = @(); Unsupported = @(); IsSuccessful = $true }
            }
            Mock Set-CgrRepositoryProtectionConfiguration {
                [pscustomobject] @{ Status = 'NotApplicable'; Restored = @(); Skipped = @(); IsSuccessful = $true; IsComplete = $true }
            }

            $result = Invoke-CgrNewDestinationSnapshot -Plan $plan -SourceRepository $source -DestinationRepository $destination

            $result.IsVerified | Should -BeTrue
            $result.Protection.Status | Should -Be 'NotApplicable'
            $terminalEvents = @($script:events | Where-Object { $_.State -ne 'Started' })
            @($terminalEvents.Name) | Should -Be @('VerifyDestinationContent', 'RestoreSupportedSettings', 'RestoreRepositoryProtection')
            @($terminalEvents.State) | Should -Be @('Completed', 'Completed', 'Info')
            $terminalEvents[0].Message | Should -Be 'Verified destination content.'
            $terminalEvents[1].Message | Should -Be 'Restored supported repository settings.'
            $terminalEvents[2].Message | Should -Be 'No transferable repository protection to restore.'
        }
    }

    It 'reports failed verification and dependent restoration stages honestly' {
        InModuleScope CopyGitHubRepo {
            $script:events = [System.Collections.Generic.List[object]]::new()
            Mock Send-CgrActivityEvent {
                param($Name, $State, $Message, $Current, $Total)
                $script:events.Add([pscustomobject] @{ Name = $Name; State = $State; Message = $Message; Current = $Current; Total = $Total })
            }

            $verification = Invoke-CgrActivityStage -Name 'VerifyDestinationContent' -Message 'Verify destination content' -Action {
                [pscustomobject] @{ IsSuccessful = $false }
            }
            $settings = Invoke-CgrActivityStage -Name 'RestoreSupportedSettings' -Message 'Restore supported repository settings' -Action {
                [pscustomobject] @{ Restored = @(); Skipped = @('SnapshotVerificationFailed'); Unsupported = @(); IsSuccessful = $false }
            }
            $protection = Invoke-CgrActivityStage -Name 'RestoreRepositoryProtection' -Message 'Restore transferable repository protection' -Action {
                [pscustomobject] @{ Status = 'Failed'; Restored = @(); Skipped = @('SnapshotVerificationFailed'); IsSuccessful = $false; IsComplete = $false }
            }

            $verification.IsSuccessful | Should -BeFalse
            $settings.IsSuccessful | Should -BeFalse
            $protection.Status | Should -Be 'Failed'
            $terminalEvents = @($script:events | Where-Object { $_.State -ne 'Started' })
            @($terminalEvents.State) | Should -Be @('Failed', 'Failed', 'Failed')
            $terminalEvents[0].Message | Should -Be 'Destination content verification failed.'
            $terminalEvents[1].Message | Should -Be 'Supported repository settings were not restored because content verification failed.'
            $terminalEvents[2].Message | Should -Be 'Repository protection restoration failed.'
        }
    }
}
