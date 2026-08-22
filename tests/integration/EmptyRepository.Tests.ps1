BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force
}

Describe 'Empty source repository handling' {
    BeforeAll {
        $script:prerequisites = [pscustomobject] @{
            Git = [pscustomobject] @{
                Found = $true
            }
            GitHubCli = [pscustomobject] @{
                Found = $true
            }
            Authentication = [pscustomobject] @{
                Authenticated = $true
                Message = 'Authenticated.'
            }
        }

        $script:emptySourceRepository = [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.Repository'
            Name = 'empty-source'
            FullName = 'infoconex/empty-source'
            Owner = 'infoconex'
            Visibility = 'public'
            IsPrivate = $false
            IsArchived = $false
            IsFork = $false
            DefaultBranch = ''
            Description = ''
            HtmlUrl = 'https://github.com/infoconex/empty-source'
            CloneUrl = 'https://github.com/infoconex/empty-source.git'
            SshUrl = 'git@github.com:infoconex/empty-source.git'
            HostName = 'github.com'
            Permissions = [pscustomobject] @{
                Pull = $true
                Push = $true
                Admin = $true
            }
            CanAdmin = $true
            CanPush = $true
        }
    }

    It 'rejects planning before checking or creating a destination' {
        InModuleScope CopyGitHubRepo -Parameters @{
            PrerequisitesFixture = $script:prerequisites
            SourceRepositoryFixture = $script:emptySourceRepository
        } {
            Mock Get-CgrPrerequisiteStatus { $PrerequisitesFixture }
            Mock Get-CgrRepository { $SourceRepositoryFixture } -ParameterFilter {
                $Repository -eq 'infoconex/empty-source'
            }
            Mock Test-CgrGitHubRepositoryExistence { $false }
            Mock New-CgrGitHubRepository { throw 'Destination creation must not be attempted.' }

            {
                Copy-GitHubRepository `
                    -SourceRepository 'infoconex/empty-source' `
                    -DestinationRepository 'infoconex/empty-copy' `
                    -PlanOnly
            } | Should -Throw -ErrorId 'SourceRepositoryEmpty,New-CgrMigrationPlan'

            Should -Invoke Test-CgrGitHubRepositoryExistence -Times 0 -Exactly
            Should -Invoke New-CgrGitHubRepository -Times 0 -Exactly
        }
    }

    It 'rejects mutating execution before destination creation' {
        InModuleScope CopyGitHubRepo -Parameters @{
            PrerequisitesFixture = $script:prerequisites
            SourceRepositoryFixture = $script:emptySourceRepository
        } {
            Mock Get-CgrPrerequisiteStatus { $PrerequisitesFixture }
            Mock Get-CgrRepository { $SourceRepositoryFixture } -ParameterFilter {
                $Repository -eq 'infoconex/empty-source'
            }
            Mock Test-CgrGitHubRepositoryExistence { $false }
            Mock New-CgrGitHubRepository { throw 'Destination creation must not be attempted.' }

            {
                Copy-GitHubRepository `
                    -SourceRepository 'infoconex/empty-source' `
                    -DestinationRepository 'infoconex/empty-copy' `
                    -NonInteractive `
                    -Force
            } | Should -Throw -ErrorId 'SourceRepositoryEmpty,New-CgrMigrationPlan'

            Should -Invoke Test-CgrGitHubRepositoryExistence -Times 0 -Exactly
            Should -Invoke New-CgrGitHubRepository -Times 0 -Exactly
        }
    }
}
