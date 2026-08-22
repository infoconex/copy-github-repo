BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Repository protection restoration' {
    It 'restores protection only after content verification and ordinary settings' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{ SourceRepository = 'infoconex/source'; DestinationRepository = 'infoconex/destination'; SourceVisibility = 'public'; DestinationVisibility = 'public'; SourceDefaultBranch = 'main'; CommitMessage = 'Initial repository commit'; SkipSettings = $false }
            $source = [pscustomobject] @{ FullName = 'infoconex/source'; Id = 1L; NodeId = 'source-node' }
            $destination = [pscustomobject] @{ FullName = 'infoconex/destination'; Id = 2L; NodeId = 'destination-node'; HtmlUrl = 'https://github.com/infoconex/destination' }
            $script:sequence = [System.Collections.Generic.List[string]]::new()

            Mock Copy-CgrRepositorySnapshot { $script:sequence.Add('copy'); [pscustomobject] @{ SourceCommitSha = 'source'; BranchName = 'main'; CommitSha = 'destination'; TreeSha = 'tree'; Verified = $true } }
            Mock Get-CgrRepository { $destination }
            Mock Invoke-CgrRepositorySnapshotVerification { $script:sequence.Add('verify'); [pscustomobject] @{ IsSuccessful = $true; Checks = @() } }
            Mock Set-CgrGitHubRepositorySetting { $script:sequence.Add('settings'); [pscustomobject] @{ Restored = @(); Skipped = @(); Unsupported = @(); IsSuccessful = $true } }
            Mock Set-CgrRepositoryProtectionConfiguration { $script:sequence.Add('protection'); [pscustomobject] @{ Restored = @(); Skipped = @(); IsSuccessful = $true; IsComplete = $true } }

            $result = Invoke-CgrNewDestinationSnapshot -Plan $plan -SourceRepository $source -DestinationRepository $destination

            ($script:sequence -join ',') | Should -Be 'copy,verify,settings,protection'
            @($result.CompletedSteps)[-1].Name | Should -Be 'RestoreRepositoryProtection'
            $result.ProtectionRestored | Should -BeTrue
        }
    }

    It 'skips identity-bound ruleset actors instead of weakening them' {
        InModuleScope CopyGitHubRepo {
            $repository = [pscustomobject] @{ FullName = 'infoconex/source'; DefaultBranch = 'main' }
            Mock Get-CgrGitHubApi {
                if ($Path -match '/rulesets\?') {
                    return @([pscustomobject] @{ id = 7; source_type = 'Repository' })
                }
                return [pscustomobject] @{
                    id = 7
                    name = 'protected-main'
                    source_type = 'Repository'
                    target = 'branch'
                    enforcement = 'active'
                    bypass_actors = @([pscustomobject] @{ actor_id = 10; actor_type = 'Team'; bypass_mode = 'always' })
                    conditions = [pscustomobject] @{ ref_name = [pscustomobject] @{ include = @('refs/heads/main'); exclude = @() } }
                    rules = @([pscustomobject] @{ type = 'deletion' })
                }
            }
            Mock Get-CgrGitHubApiOptional { $null }

            $config = Get-CgrRepositoryProtectionConfiguration -Repository $repository
            @($config.Rulesets).Count | Should -Be 0
            @($config.Unsupported).Count | Should -Be 1
            @($config.Unsupported[0].Reasons) | Should -Contain 'BypassActorsAreIdentityBound'
        }
    }

    It 'does not treat inherited organization rulesets as copied repository rulesets' {
        InModuleScope CopyGitHubRepo {
            $repository = [pscustomobject] @{ FullName = 'infoconex/source'; DefaultBranch = 'main' }
            Mock Get-CgrGitHubApi {
                @([pscustomobject] @{ id = 11; source_type = 'Organization' })
            }
            Mock Get-CgrGitHubApiOptional { $null }

            $config = Get-CgrRepositoryProtectionConfiguration -Repository $repository
            @($config.Rulesets).Count | Should -Be 0
            @($config.Unsupported).Count | Should -Be 0
        }
    }

    It 'skips branch protection with identity-bound push restrictions' {
        InModuleScope CopyGitHubRepo {
            $repository = [pscustomobject] @{ FullName = 'infoconex/source'; DefaultBranch = 'main' }
            Mock Get-CgrGitHubApi { @() }
            Mock Get-CgrGitHubApiOptional {
                [pscustomobject] @{
                    restrictions = [pscustomobject] @{ users = @([pscustomobject] @{ login = 'octocat' }); teams = @(); apps = @() }
                    required_pull_request_reviews = $null
                    required_status_checks = $null
                    enforce_admins = [pscustomobject] @{ enabled = $false }
                    required_linear_history = [pscustomobject] @{ enabled = $false }
                    allow_force_pushes = [pscustomobject] @{ enabled = $false }
                    allow_deletions = [pscustomobject] @{ enabled = $false }
                    block_creations = [pscustomobject] @{ enabled = $false }
                    required_conversation_resolution = [pscustomobject] @{ enabled = $false }
                    lock_branch = [pscustomobject] @{ enabled = $false }
                    allow_fork_syncing = [pscustomobject] @{ enabled = $false }
                    required_signatures = [pscustomobject] @{ enabled = $false }
                }
            }

            $config = Get-CgrRepositoryProtectionConfiguration -Repository $repository
            $config.BranchProtection | Should -BeNullOrEmpty
            @($config.Unsupported[0].Reasons) | Should -Contain 'PushRestrictionsAreIdentityBound'
        }
    }
}
