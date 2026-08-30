BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Public structured output contracts' {
    It 'preserves repository type names and important scalar/property types' {
        InModuleScope CopyGitHubRepo {
            $repository = ConvertTo-CgrRepository -HostName 'github.com' -Repository ([pscustomobject] @{
                    id = 42
                    node_id = 'R_42'
                    name = 'widget'
                    full_name = 'acme/widget'
                    owner = [pscustomobject] @{ login = 'acme' }
                    visibility = 'public'
                    private = $false
                    archived = $false
                    fork = $false
                    default_branch = 'main'
                    topics = @('two', 'one')
                    permissions = [pscustomobject] @{ admin = $true; push = $true; pull = $true }
                    updated_at = '2026-08-15T00:00:00Z'
                })

            $repository.PSObject.TypeNames | Should -Contain 'CopyGitHubRepo.Repository'
            $repository.Id | Should -BeOfType ([long])
            $repository.IsPrivate | Should -BeOfType ([bool])
            $repository.CanAdmin | Should -BeOfType ([bool])
            $repository.UpdatedAt | Should -BeOfType ([datetimeoffset])
            @($repository.Topics) | Should -Be @('one', 'two')
        }
    }

    It 'keeps zero, one and many repository topic values collection-compatible' -ForEach @(
        @{ Topics = @(); Expected = 0 }
        @{ Topics = @('one'); Expected = 1 }
        @{ Topics = @('one', 'two'); Expected = 2 }
    ) {
        InModuleScope CopyGitHubRepo -Parameters @{ Topics = $_.Topics; Expected = $_.Expected } {
            param($Topics, $Expected)
            $repository = ConvertTo-CgrRepository -HostName 'github.com' -Repository ([pscustomobject] @{
                    id = 42; node_id = 'R_42'; name = 'widget'; full_name = 'acme/widget'
                    owner = [pscustomobject] @{ login = 'acme' }; visibility = 'public'; private = $false
                    archived = $false; fork = $false; default_branch = 'main'; topics = $Topics
                    permissions = [pscustomobject] @{}
                })

            @($repository.Topics | Where-Object { $null -ne $_ }).Count | Should -Be $Expected
        }
    }

    It 'returns the verifier structured object unchanged from Test-GitHubRepositoryMigration' {
        InModuleScope CopyGitHubRepo {
            Mock Get-CgrPrerequisiteStatus {
                [pscustomobject] @{
                    Git = [pscustomobject] @{ Found = $true }
                    GitHubCli = [pscustomobject] @{ Found = $true }
                    Authentication = [pscustomobject] @{ Authenticated = $true; Message = 'ok' }
                }
            }
            Mock Get-CgrRepository { [pscustomobject] @{ FullName = $Repository } }
            Mock Invoke-CgrRepositorySnapshotVerification {
                [pscustomobject] @{
                    PSTypeName = 'CopyGitHubRepo.MigrationVerification'
                    SchemaVersion = 1
                    ContentMode = 'Snapshot'
                    IsMatch = $true
                    Checks = @([pscustomobject] @{ Name = 'Tree'; Passed = $true })
                }
            }

            $result = Test-GitHubRepositoryMigration -SourceRepository 'acme/source' -DestinationRepository 'acme/dest'

            $result.PSObject.TypeNames | Should -Contain 'CopyGitHubRepo.MigrationVerification'
            $result.SchemaVersion | Should -Be 1
            $result.IsMatch | Should -BeOfType ([bool])
            @($result.Checks).Count | Should -Be 1
            $result.Checks[0].Passed | Should -BeOfType ([bool])
        }
    }

    It 'returns the structured migration plan from Copy-GitHubRepository PlanOnly Interactive mode' {
        InModuleScope CopyGitHubRepo {
            Mock Get-CgrPrerequisiteStatus {
                [pscustomobject] @{
                    Git = [pscustomobject] @{ Found = $true }
                    GitHubCli = [pscustomobject] @{ Found = $true }
                    Authentication = [pscustomobject] @{ Authenticated = $true; Message = 'ok' }
                }
            }
            Mock Get-CgrRepository {
                [pscustomobject] @{ FullName = 'acme/source'; Visibility = 'public'; Id = 10L; NodeId = 'R_source' }
            }
            Mock New-CgrMigrationPlan {
                [pscustomobject] @{
                    PSTypeName = 'CopyGitHubRepo.MigrationPlan'
                    SchemaVersion = 1
                    SourceRepository = 'acme/source'
                    DestinationRepository = 'acme/dest'
                    ContentMode = 'Snapshot'
                    PlanOnly = $true
                    Steps = @()
                }
            }

            $result = Copy-GitHubRepository -SourceRepository 'acme/source' -DestinationRepository 'acme/dest' -PlanOnly

            $result.PSObject.TypeNames | Should -Contain 'CopyGitHubRepo.MigrationPlan'
            $result.SchemaVersion | Should -Be 1
            $result.PlanOnly | Should -BeOfType ([bool])
            @($result.Steps).Count | Should -Be 0
        }
    }
}
