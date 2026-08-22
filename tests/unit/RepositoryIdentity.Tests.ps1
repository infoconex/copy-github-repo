BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force
}

Describe 'Repository immutable identity' {
    It 'captures GitHub id and node_id on repository discovery objects' {
        InModuleScope CopyGitHubRepo {
            $apiRepository = [pscustomobject] @{
                id = 1328914530L
                node_id = 'R_kgDOTzWgYg'
                name = 'copy-github-repo'
                full_name = 'infoconex/copy-github-repo'
                owner = [pscustomobject] @{ login = 'infoconex' }
                visibility = 'public'
                private = $false
                archived = $false
                fork = $false
                default_branch = 'main'
                permissions = [pscustomobject] @{ admin = $true; push = $true; pull = $true }
            }

            $repository = ConvertTo-CgrRepository -Repository $apiRepository -HostName 'github.com'

            $repository.PSTypeNames[0] | Should -Be 'CopyGitHubRepo.Repository'
            $repository.Id | Should -Be 1328914530
            $repository.NodeId | Should -Be 'R_kgDOTzWgYg'
            $repository.FullName | Should -Be 'infoconex/copy-github-repo'
        }
    }

    It 'keeps identity properties additive when GitHub identity is unavailable' {
        InModuleScope CopyGitHubRepo {
            $apiRepository = [pscustomobject] @{
                name = 'legacy'
                full_name = 'infoconex/legacy'
                owner = [pscustomobject] @{ login = 'infoconex' }
                private = $true
                archived = $false
                permissions = [pscustomobject] @{ pull = $true }
            }

            $repository = ConvertTo-CgrRepository -Repository $apiRepository -HostName 'github.com'

            $repository.PSObject.Properties.Name | Should -Contain 'Id'
            $repository.PSObject.Properties.Name | Should -Contain 'NodeId'
            $repository.Id | Should -BeNullOrEmpty
            $repository.NodeId | Should -BeNullOrEmpty
        }
    }
}
