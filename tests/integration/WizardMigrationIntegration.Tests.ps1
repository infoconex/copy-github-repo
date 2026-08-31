BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Wizard to migration integration' {
    It 'carries a reviewed Snapshot plan through real execution orchestration and verification' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'acme/source'; Owner = 'acme'; Visibility = 'public'; Id = 10L; NodeId = 'R_source' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination'; Visibility = 'public'; Id = 20L; NodeId = 'R_destination'; HtmlUrl = 'https://github.com/acme/destination' }
            $sourceState = [pscustomobject] @{
                Repository = 'acme/source'; RepositoryId = 10L; RepositoryNodeId = 'R_source'; ContentMode = 'Snapshot'
                DefaultBranch = 'main'; CommitSha = 'source-commit'; TreeSha = 'source-tree'; GitLfsObjectsAvailable = $true; GitLfsPointerFiles = @()
            }
            $plan = [pscustomobject] @{
                PSTypeName = 'CopyGitHubRepo.MigrationPlan'; SchemaVersion = 1
                Mode = 'NewDestination'; SourceRepository = 'acme/source'; DestinationRepository = 'acme/destination'
                ArchiveRepository = $null; ContentMode = 'Snapshot'; IncludeReleases = $false; CommitMessage = 'Initial repository commit'
                SourceVisibility = 'public'; DestinationVisibility = 'public'; SourceDefaultBranch = 'main'
                SourceState = $sourceState; SkipSettings = $true; Protection = $null; Steps = @()
            }

            Mock Write-CgrWizardMessage
            Mock Get-GitHubRepository { @($source) }
            Mock Select-CgrWizardRepository { ConvertTo-CgrWizardNavigationResult -Action Next -Value $source }
            Mock Test-CgrGitHubRepositoryExistence { $false }
            Mock Read-CgrWizardRepositoryName { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'acme/destination' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Snapshot' } -ParameterFilter { $Title -eq 'Content mode' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'public' } -ParameterFilter { $Title -eq 'Destination visibility' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Skip' } -ParameterFilter { $Title -eq 'Supported repository settings' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Skip' } -ParameterFilter { $Title -eq 'Snapshot release preservation' }
            Mock Read-CgrWizardTextValue { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Initial repository commit' } -ParameterFilter { $Title -eq 'Snapshot commit message' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Execute' } -ParameterFilter { $Title -eq 'Repository copy plan' }

            Mock Get-CgrPrerequisiteStatus { [pscustomobject] @{ Git = [pscustomobject] @{ Found = $true }; GitHubCli = [pscustomobject] @{ Found = $true }; Authentication = [pscustomobject] @{ Authenticated = $true; Message = 'ok' } } }
            Mock Get-CgrRepository { if ($Repository -eq 'acme/source') { return $source }; return $destination }
            Mock New-CgrMigrationPlan { $plan }
            Mock Get-CgrRepositoryDefaultBranchTree { [pscustomobject] @{ BranchName = 'main'; CommitSha = 'source-commit'; TreeSha = 'source-tree'; GitLfsObjectsAvailable = $true; GitLfsPointerFiles = @() } }
            Mock New-CgrGitHubRepository { $destination }
            Mock Copy-CgrRepositorySnapshot { [pscustomobject] @{ Verified = $true; SourceCommitSha = 'source-commit'; TreeSha = 'source-tree'; CommitSha = 'destination-root'; BranchName = 'main' } }
            Mock Invoke-CgrRepositorySnapshotVerification { [pscustomobject] @{ PSTypeName = 'CopyGitHubRepo.MigrationVerification'; SchemaVersion = 1; ContentMode = 'Snapshot'; IsSuccessful = $true; IsMatch = $true; SourceTree = 'source-tree'; DestinationTree = 'source-tree'; Checks = @() } }

            $result = Invoke-CgrRepositoryCopyWizard -HostName 'github.com' -ExecutionGuard { $true }

            $result.PSObject.TypeNames | Should -Contain 'CopyGitHubRepo.MigrationExecutionResult'
            $result.Status | Should -Be 'SnapshotVerifiedSettingsSkipped'
            $result.IsVerified | Should -BeTrue
            $result.Plan | Should -Be $plan
            $result.Verification.IsSuccessful | Should -BeTrue
            @($result.CompletedSteps).Name | Should -Contain 'VerifySnapshot'
            Should -Invoke Copy-CgrRepositorySnapshot -Times 1 -Exactly
            Should -Invoke Invoke-CgrRepositorySnapshotVerification -Times 1 -Exactly
            Should -Invoke New-CgrGitHubRepository -Times 1 -Exactly
        }
    }
}
