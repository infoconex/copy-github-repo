BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1') -Force
}

Describe 'Test-GitHubRepositoryMigration Pages verification boundary' {
    It 'requires reviewed Pages evidence before prerequisite or repository discovery' {
        InModuleScope CopyGitHubRepo {
            Mock Get-CgrPrerequisiteStatus { throw 'prerequisites must not run' }
            Mock Get-CgrRepository { throw 'repository discovery must not run' }

            { Test-GitHubRepositoryMigration -SourceRepository acme/source -DestinationRepository acme/destination -VerifyPages } |
                Should -Throw -ErrorId 'PagesVerificationPlanRequired,Test-GitHubRepositoryMigration'

            Should -Invoke Get-CgrPrerequisiteStatus -Times 0
            Should -Invoke Get-CgrRepository -Times 0
        }
    }

    It 'rejects Pages evidence that is not bound to the requested migration identity' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                RestorePages = $true; ContentMode = 'Snapshot'; SourceRepository = 'acme/source'
                DestinationRepository = 'acme/other'; HostName = 'github.com'
                Pages = [pscustomobject] @{ Configured = $false }
            }
            Mock Get-CgrPrerequisiteStatus { throw 'prerequisites must not run' }

            { Test-GitHubRepositoryMigration -SourceRepository acme/source -DestinationRepository acme/destination -VerifyPages -ApprovedPlan $plan } |
                Should -Throw -ErrorId 'PagesVerificationPlanInvalid,Test-GitHubRepositoryMigration'

            Should -Invoke Get-CgrPrerequisiteStatus -Times 0
        }
    }

    It 'combines independent Pages verification with plain Snapshot verification using approved source state' {
        InModuleScope CopyGitHubRepo {
            $sourceState = [pscustomobject] @{ DefaultBranch = 'main'; TreeSha = 'reviewed-tree' }
            $plan = [pscustomobject] @{
                RestorePages = $true; ContentMode = 'Snapshot'; SourceRepository = 'acme/source'
                DestinationRepository = 'acme/destination'; HostName = 'github.com'; SourceState = $sourceState
                Pages = [pscustomobject] @{ Configured = $true; BuildType = 'workflow' }
            }
            Mock Get-CgrPrerequisiteStatus {
                [pscustomobject] @{
                    Git = [pscustomobject] @{ Found = $true }
                    GitHubCli = [pscustomobject] @{ Found = $true }
                    Authentication = [pscustomobject] @{ Authenticated = $true; Message = 'ok' }
                }
            }
            Mock Get-CgrRepository {
                [pscustomobject] @{
                    FullName = $Repository
                    DefaultBranch = 'main'
                    CloneUrl = "https://github.com/$Repository.git"
                    HostName = 'github.com'
                }
            }
            Mock Invoke-CgrRepositorySnapshotVerification {
                [pscustomobject] @{ PSTypeName = 'CopyGitHubRepo.MigrationVerificationResult'; IsSuccessful = $true; Checks = @() }
            }
            Mock Test-CgrGitHubPagesMigration {
                [pscustomobject] @{ PSTypeName = 'CopyGitHubRepo.GitHubPagesVerificationResult'; IsSuccessful = $false; Checks = @([pscustomobject] @{ Name = 'PagesBuildTypeMatches'; Passed = $false }) }
            }

            $result = Test-GitHubRepositoryMigration -SourceRepository acme/source -DestinationRepository acme/destination -VerifyPages -ApprovedPlan $plan

            $result.GitContentSuccessful | Should -BeTrue
            $result.PagesVerified | Should -BeFalse
            $result.IsSuccessful | Should -BeFalse
            Should -Invoke Invoke-CgrRepositorySnapshotVerification -Times 1 -Exactly -ParameterFilter { $ApprovedSourceState -eq $sourceState }
            Should -Invoke Test-CgrGitHubPagesMigration -Times 1 -Exactly -ParameterFilter { $Plan -eq $plan -and $DestinationRepository.FullName -eq 'acme/destination' }
        }
    }
}
