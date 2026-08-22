BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force
}

Describe 'GitHub host support contract' {
    It 'accepts github.com as the version 1 host' {
        InModuleScope CopyGitHubRepo {
            { Assert-CgrSupportedHostName -HostName 'github.com' } | Should -Not -Throw
            { Assert-CgrSupportedHostName -HostName 'GITHUB.COM' } | Should -Not -Throw
        }
    }

    It 'rejects an unsupported host before copy prerequisites or mutation paths are reached' {
        InModuleScope CopyGitHubRepo {
            Mock Get-CgrPrerequisiteStatus { throw 'Prerequisites must not run for an unsupported host.' }
            Mock Get-CgrRepository { throw 'Discovery must not run for an unsupported host.' }
            Mock New-CgrGitHubRepository { throw 'Mutation must not run for an unsupported host.' }

            {
                Copy-GitHubRepository `
                    -SourceRepository 'infoconex/source' `
                    -DestinationRepository 'infoconex/destination' `
                    -HostName 'github.example.com' `
                    -Confirm:$false
            } | Should -Throw -ErrorId 'GitHubHostNotSupported,Assert-CgrSupportedHostName'

            Should -Invoke Get-CgrPrerequisiteStatus -Times 0 -Exactly
            Should -Invoke Get-CgrRepository -Times 0 -Exactly
            Should -Invoke New-CgrGitHubRepository -Times 0 -Exactly
        }
    }

    It 'rejects an unsupported host before repository discovery prerequisites are reached' {
        InModuleScope CopyGitHubRepo {
            Mock Get-CgrPrerequisiteStatus { throw 'Prerequisites must not run for an unsupported host.' }
            Mock Get-CgrRepository { throw 'Discovery must not run for an unsupported host.' }

            {
                Get-GitHubRepository `
                    -Repository 'infoconex/source' `
                    -HostName 'github.example.com'
            } | Should -Throw -ErrorId 'GitHubHostNotSupported,Assert-CgrSupportedHostName'

            Should -Invoke Get-CgrPrerequisiteStatus -Times 0 -Exactly
            Should -Invoke Get-CgrRepository -Times 0 -Exactly
        }
    }

    It 'rejects an unsupported host before migration verification prerequisites are reached' {
        InModuleScope CopyGitHubRepo {
            Mock Get-CgrPrerequisiteStatus { throw 'Prerequisites must not run for an unsupported host.' }
            Mock Get-CgrRepository { throw 'Discovery must not run for an unsupported host.' }
            Mock Invoke-CgrRepositorySnapshotVerification { throw 'Verification must not run for an unsupported host.' }

            {
                Test-GitHubRepositoryMigration `
                    -SourceRepository 'infoconex/source' `
                    -DestinationRepository 'infoconex/destination' `
                    -HostName 'github.example.com'
            } | Should -Throw -ErrorId 'GitHubHostNotSupported,Assert-CgrSupportedHostName'

            Should -Invoke Get-CgrPrerequisiteStatus -Times 0 -Exactly
            Should -Invoke Get-CgrRepository -Times 0 -Exactly
            Should -Invoke Invoke-CgrRepositorySnapshotVerification -Times 0 -Exactly
        }
    }
}
