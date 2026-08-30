BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force

    $script:authenticatedPrerequisites = [pscustomobject] @{
        GitHubCli = [pscustomobject] @{
            Found = $true
        }
        Authentication = [pscustomobject] @{
            Authenticated = $true
            Message = 'Authenticated.'
        }
    }
}

Describe 'Get-GitHubRepository parameter sets' {
    It 'exposes ByRepository and Search parameter sets with Search as the default' {
        $command = Get-Command Get-GitHubRepository
        $parameterSets = @($command.ParameterSets | Select-Object -ExpandProperty Name | Sort-Object)

        $parameterSets | Should -Be @('ByRepository', 'Search')
        $command.DefaultParameterSet | Should -Be 'Search'
    }

    It 'keeps Repository exclusive to ByRepository and filters exclusive to Search' {
        $command = Get-Command Get-GitHubRepository
        $byRepository = $command.ParameterSets | Where-Object Name -EQ 'ByRepository'
        $search = $command.ParameterSets | Where-Object Name -EQ 'Search'

        @($byRepository.Parameters.Name) | Should -Contain 'Repository'
        @($byRepository.Parameters.Name) | Should -Contain 'HostName'
        @($byRepository.Parameters.Name) | Should -Not -Contain 'Owner'
        @($byRepository.Parameters.Name) | Should -Not -Contain 'Name'
        @($byRepository.Parameters.Name) | Should -Not -Contain 'Visibility'
        @($byRepository.Parameters.Name) | Should -Not -Contain 'Archived'

        @($search.Parameters.Name) | Should -Contain 'Owner'
        @($search.Parameters.Name) | Should -Contain 'Name'
        @($search.Parameters.Name) | Should -Contain 'Visibility'
        @($search.Parameters.Name) | Should -Contain 'Archived'
        @($search.Parameters.Name) | Should -Contain 'HostName'
        @($search.Parameters.Name) | Should -Not -Contain 'Repository'
    }

    It 'performs direct lookup through ByRepository unchanged' {
        InModuleScope CopyGitHubRepo -Parameters @{
            AuthenticatedPrerequisites = $script:authenticatedPrerequisites
        } {
            Mock Get-CgrPrerequisiteStatus { $AuthenticatedPrerequisites }
            Mock Get-CgrRepository {
                [pscustomobject] @{
                    PSTypeName = 'CopyGitHubRepo.Repository'
                    FullName = $Repository.ToLowerInvariant()
                }
            }

            $result = Get-GitHubRepository -Repository 'Infoconex/copy-github-repo'

            $result.FullName | Should -Be 'infoconex/copy-github-repo'
            Should -Invoke Get-CgrRepository -Times 1 -Exactly -ParameterFilter {
                $Repository -eq 'Infoconex/copy-github-repo' -and
                $HostName -eq 'github.com'
            }
        }
    }

    It 'performs filtered discovery through Search unchanged' {
        InModuleScope CopyGitHubRepo -Parameters @{
            AuthenticatedPrerequisites = $script:authenticatedPrerequisites
        } {
            Mock Get-CgrPrerequisiteStatus { $AuthenticatedPrerequisites }
            Mock Get-CgrRepository {
                [pscustomobject] @{
                    PSTypeName = 'CopyGitHubRepo.Repository'
                    FullName = 'infoconex/copy-github-repo'
                }
            }

            Get-GitHubRepository `
                -Owner 'infoconex' `
                -Name 'copy' `
                -Visibility public `
                -Archived $false |
                Out-Null

            Should -Invoke Get-CgrRepository -Times 1 -Exactly -ParameterFilter {
                $Owner -eq 'infoconex' -and
                $Name -eq 'copy' -and
                $Visibility -eq 'public' -and
                $Archived -eq $false -and
                $HostName -eq 'github.com'
            }
        }
    }

    It 'rejects mixed direct lookup and filter parameters during parameter binding' {
        {
            Get-GitHubRepository `
                -Repository 'infoconex/copy-github-repo' `
                -Owner 'infoconex'
        } | Should -Throw -ErrorId 'AmbiguousParameterSet,Get-GitHubRepository'
    }

    It 'publishes parameter-set guidance through command help' {
        $helpText = Get-Help Get-GitHubRepository -Full | Out-String

        $helpText | Should -Match 'ByRepository'
        $helpText | Should -Match 'Search'
        $helpText | Should -Match 'cannot be combined with Owner, Name'
    }
}
