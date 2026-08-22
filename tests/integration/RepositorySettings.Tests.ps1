BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force
}

Describe 'Repository settings restoration' {
    BeforeEach {
        $script:sourceRepository = [pscustomobject] @{
            FullName = 'infoconex/source'
            Description = 'Source description'
            Homepage = 'https://example.com/source'
            HasIssues = $true
            HasProjects = $false
            HasWiki = $false
            HasDiscussions = $true
            AllowSquashMerge = $true
            AllowMergeCommit = $false
            AllowRebaseMerge = $true
            AllowAutoMerge = $false
            DeleteBranchOnMerge = $true
            AllowUpdateBranch = $true
            WebCommitSignoffRequired = $true
            Topics = @('automation', 'migration')
        }

        $script:destinationRepository = [pscustomobject] @{
            FullName = 'infoconex/destination'
            Description = 'Old description'
            Homepage = 'https://example.com/source'
            HasIssues = $false
            HasProjects = $false
            HasWiki = $false
            HasDiscussions = $true
            AllowSquashMerge = $true
            AllowMergeCommit = $false
            AllowRebaseMerge = $true
            AllowAutoMerge = $false
            DeleteBranchOnMerge = $true
            AllowUpdateBranch = $true
            WebCommitSignoffRequired = $true
            Topics = @('automation', 'migration')
        }
    }

    It 'patches only changed repository fields and verifies the result' {
        InModuleScope CopyGitHubRepo -Parameters @{
            SourceFixture = $script:sourceRepository
            DestinationFixture = $script:destinationRepository
        } {
            $verifiedDestination = $DestinationFixture.PSObject.Copy()
            $verifiedDestination.Description = $SourceFixture.Description
            $verifiedDestination.HasIssues = $SourceFixture.HasIssues

            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
            }
            Mock Get-CgrRepository { $verifiedDestination }

            $result = Set-CgrGitHubRepositorySetting `
                -SourceRepository $SourceFixture `
                -DestinationRepository $DestinationFixture

            $result.IsSuccessful | Should -BeTrue
            @($result.Restored | Where-Object Name -eq 'Description')[0].Changed | Should -BeTrue
            @($result.Restored | Where-Object Name -eq 'HasIssues')[0].Changed | Should -BeTrue
            @($result.Restored | Where-Object Name -eq 'AllowMergeCommit')[0].Changed | Should -BeFalse

            Should -Invoke Invoke-CgrNativeCommand -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq 'gh' -and
                ($ArgumentList -join ' ') -like '* PATCH repos/infoconex/destination *' -and
                ($ArgumentList -join ' ') -like '* description=Source description *' -and
                ($ArgumentList -join ' ') -like '* has_issues=true*' -and
                ($ArgumentList -join ' ') -notlike '* allow_merge_commit=*'
            }
        }
    }

    It 'restores topics through the topics endpoint and verifies them' {
        InModuleScope CopyGitHubRepo -Parameters @{
            SourceFixture = $script:sourceRepository
            DestinationFixture = $script:destinationRepository
        } {
            $matchingDestination = $SourceFixture.PSObject.Copy()
            $matchingDestination.FullName = $DestinationFixture.FullName
            $destinationWithDifferentTopics = $matchingDestination.PSObject.Copy()
            $destinationWithDifferentTopics.Topics = @('automation')

            Mock Set-Content { $null }
            Mock Remove-Item { $null }
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
            }
            Mock Get-CgrRepository { $matchingDestination }

            $output = @(Set-CgrGitHubRepositorySetting `
                -SourceRepository $SourceFixture `
                -DestinationRepository $destinationWithDifferentTopics)
            $result = $output |
                Where-Object {
                    (Get-CgrObjectProperty -InputObject $_ -Name 'IsSuccessful') -eq $true -and
                    (Get-CgrObjectProperty -InputObject $_ -Name 'Repository') -eq 'infoconex/destination'
                } |
                Select-Object -Last 1

            $result | Should -Not -BeNullOrEmpty
            $result.IsSuccessful | Should -BeTrue
            @($result.Restored | Where-Object Name -eq 'Topics')[0].Changed | Should -BeTrue
            Should -Invoke Set-Content -Times 1 -Exactly
            Should -Invoke Invoke-CgrNativeCommand -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq 'gh' -and
                ($ArgumentList -join ' ') -like '* PUT repos/infoconex/destination/topics --input *'
            }
        }
    }

    It 'fails when read-back verification does not match the source settings' {
        InModuleScope CopyGitHubRepo -Parameters @{
            SourceFixture = $script:sourceRepository
            DestinationFixture = $script:destinationRepository
        } {
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
            }
            Mock Get-CgrRepository { $DestinationFixture }

            {
                Set-CgrGitHubRepositorySetting `
                    -SourceRepository $SourceFixture `
                    -DestinationRepository $DestinationFixture
            } | Should -Throw -ErrorId 'GitHubRepositorySettingsVerificationFailed,Set-CgrGitHubRepositorySetting'
        }
    }

    It 'skips source settings that are unavailable instead of treating them as false' {
        InModuleScope CopyGitHubRepo -Parameters @{
            DestinationFixture = $script:destinationRepository
        } {
            $minimalSource = [pscustomobject] @{
                FullName = 'infoconex/source'
                Description = 'Source description'
            }
            $verifiedDestination = $DestinationFixture.PSObject.Copy()
            $verifiedDestination.Description = 'Source description'

            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
            }
            Mock Get-CgrRepository { $verifiedDestination }

            $result = Set-CgrGitHubRepositorySetting `
                -SourceRepository $minimalSource `
                -DestinationRepository $DestinationFixture

            $result.IsSuccessful | Should -BeTrue
            $result.Skipped | Should -Contain 'HasIssues:UnavailableFromSource'
            $result.Skipped | Should -Contain 'Topics:UnavailableFromSource'
        }
    }
}
