BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force
}

InModuleScope CopyGitHubRepo {
    Describe 'Public existing-destination replacement safety boundary' {
        BeforeEach {
            $script:prerequisites = [pscustomobject] @{
                Git = [pscustomobject] @{ Found = $true }
                GitHubCli = [pscustomobject] @{ Found = $true }
                Authentication = [pscustomobject] @{ Authenticated = $true; Message = 'Authenticated.' }
            }
            $script:sourceRepository = [pscustomobject] @{
                PSTypeName = 'CopyGitHubRepo.Repository'
                Id = 101L
                NodeId = 'R_source'
                Name = 'source'
                FullName = 'infoconex/source'
                Owner = 'infoconex'
                Visibility = 'public'
                IsPrivate = $false
                IsArchived = $false
                IsFork = $false
                DefaultBranch = 'main'
                Description = 'Source repository.'
                HtmlUrl = 'https://github.com/infoconex/source'
                CloneUrl = 'https://github.com/infoconex/source.git'
                SshUrl = 'git@github.com:infoconex/source.git'
                HostName = 'github.com'
                CanAdmin = $true
                CanPush = $true
            }

            Mock Get-CgrPrerequisiteStatus { $script:prerequisites }
            Mock Get-CgrRepository { $script:sourceRepository }
            Mock Test-CgrGitHubRepositoryExistence {
                param($Repository)
                $Repository -eq 'infoconex/destination'
            }
            Mock Get-CgrRepositoryProtectionConfiguration {
                [pscustomobject] @{
                    Rulesets = @()
                    BranchProtection = $null
                    Unsupported = @()
                }
            }
            Mock Get-CgrApprovedSourceState {
                [pscustomobject] @{
                    PSTypeName = 'CopyGitHubRepo.ApprovedSourceState'
                    ContentMode = 'Snapshot'
                    Repository = 'infoconex/source'
                    RepositoryId = 101L
                    RepositoryNodeId = 'R_source'
                    DefaultBranch = 'main'
                    CommitSha = 'source-commit'
                    TreeSha = 'source-tree'
                    GitLfsObjectsAvailable = $false
                    GitLfsPointerFiles = @()
                }
            }
            Mock Assert-CgrApprovedSourceState { $SourceState }
            Mock Assert-CgrLocalResourcePreflight { $true }
            Mock Invoke-CgrExistingDestinationReplacement { throw 'Replacement execution must not be reached without exact confirmation.' }
        }

        It 'does not allow Force to bypass exact existing-destination replacement confirmation' {
            {
                Copy-GitHubRepository `
                    -SourceRepository infoconex/source `
                    -DestinationRepository infoconex/destination `
                    -ExistingDestinationArchiveName destination-archive `
                    -NonInteractive `
                    -Force
            } | Should -Throw -ErrorId 'ExistingDestinationReplacementConfirmationRequired,Assert-CgrExistingDestinationReplacementConfirmation'

            Should -Invoke Invoke-CgrExistingDestinationReplacement -Times 0 -Exactly
        }

        It 'does not allow Confirm false to bypass exact existing-destination replacement confirmation' {
            {
                Copy-GitHubRepository `
                    -SourceRepository infoconex/source `
                    -DestinationRepository infoconex/destination `
                    -ExistingDestinationArchiveName destination-archive `
                    -Confirm:$false
            } | Should -Throw -ErrorId 'ExistingDestinationReplacementConfirmationRequired,Assert-CgrExistingDestinationReplacementConfirmation'

            Should -Invoke Invoke-CgrExistingDestinationReplacement -Times 0 -Exactly
        }
    }
}
