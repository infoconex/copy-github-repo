BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Repository identity and API path boundaries' {
    It 'normalizes owner casing while preserving valid repository punctuation' {
        InModuleScope CopyGitHubRepo {
            ConvertTo-CgrRepositoryName -Repository 'Acme-Org/Widget.repo_1' |
                Should -Be 'acme-org/Widget.repo_1'
        }
    }

    It 'rejects malformed repository identities' {
        InModuleScope CopyGitHubRepo {
            { ConvertTo-CgrRepositoryName -Repository 'acme' } | Should -Throw
            { ConvertTo-CgrRepositoryName -Repository '/widget' } | Should -Throw
            { ConvertTo-CgrRepositoryName -Repository 'acme/' } | Should -Throw
            { ConvertTo-CgrRepositoryName -Repository 'acme/widget/extra' } | Should -Throw
            { ConvertTo-CgrRepositoryName -Repository 'acme widget/repo' } | Should -Throw
            { ConvertTo-CgrRepositoryName -Repository 'https://github.com/acme/widget' } | Should -Throw
        }
    }

    It 'constructs canonical repository API paths without double encoding' {
        InModuleScope CopyGitHubRepo {
            Mock Get-CgrGitHubApi { @() }

            Get-CgrSnapshotHistory `
                -Repository ([pscustomobject] @{ FullName = 'Acme-Org/Widget.repo_1' }) `
                -HostName 'github.com' |
                Out-Null

            Should -Invoke Get-CgrGitHubApi -Times 1 -ParameterFilter {
                $Path -eq '/repos/acme-org/Widget.repo_1/tags?per_page=100' -and
                $Path -notmatch '%25'
            }
            Should -Invoke Get-CgrGitHubApi -Times 1 -ParameterFilter {
                $Path -eq '/repos/acme-org/Widget.repo_1/releases?per_page=100' -and
                $Path -notmatch '%25'
            }
        }
    }

    It 'keeps hostname routing independent from repository normalization' {
        InModuleScope CopyGitHubRepo {
            Mock Get-CgrGitHubApi { @() }

            Get-CgrSnapshotHistory `
                -Repository ([pscustomobject] @{ FullName = 'Acme/Widget' }) `
                -HostName 'github.example.com' |
                Out-Null

            Should -Invoke Get-CgrGitHubApi -Times 2 -ParameterFilter {
                $HostName -eq 'github.example.com' -and $Path -like '/repos/acme/Widget/*'
            }
        }
    }
}
