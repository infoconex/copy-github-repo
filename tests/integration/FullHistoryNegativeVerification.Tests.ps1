BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force
}

Describe 'FullHistory negative verification behavior' {
    BeforeEach {
        $script:sourceRepository = [pscustomobject] @{
            FullName = 'infoconex/source'
            DefaultBranch = 'main'
            CloneUrl = 'https://github.com/infoconex/source.git'
            HostName = 'github.com'
        }
        $script:destinationRepository = [pscustomobject] @{
            FullName = 'infoconex/destination'
            DefaultBranch = 'develop'
            CloneUrl = 'https://github.com/infoconex/destination.git'
            HostName = 'github.com'
        }
    }

    It 'reports ref default-branch commit-count and branch-tree mismatches as failed verification' {
        InModuleScope CopyGitHubRepo -Parameters @{
            SourceRepositoryFixture = $script:sourceRepository
            DestinationRepositoryFixture = $script:destinationRepository
        } {
            Mock New-Item { $null }
            Mock Test-Path { $false }
            Mock Remove-Item { $null }
            Mock Invoke-CgrGitCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
            }
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @('git-lfs/3.0.0'); ErrorText = '' }
            } -ParameterFilter {
                ($ArgumentList -join ' ') -eq 'lfs version'
            }
            Mock Invoke-CgrNativeCommand {
                $arguments = $ArgumentList -join ' '
                $output = if ($arguments -like '*source.git*') {
                    @(
                        'refs/heads/main 1111111111111111111111111111111111111111'
                        'refs/tags/v1.0.0 2222222222222222222222222222222222222222'
                    )
                }
                else {
                    @(
                        'refs/heads/main aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
                        'refs/tags/v1.0.0 2222222222222222222222222222222222222222'
                    )
                }
                [pscustomobject] @{ ExitCode = 0; Output = $output; ErrorText = '' }
            } -ParameterFilter {
                ($ArgumentList -join ' ') -like '* for-each-ref --format=%(refname) %(objectname) refs/heads refs/tags'
            }
            Mock Invoke-CgrNativeCommand {
                $count = if (($ArgumentList -join ' ') -like '*source.git*') { '3' } else { '2' }
                [pscustomobject] @{ ExitCode = 0; Output = @($count); ErrorText = '' }
            } -ParameterFilter {
                ($ArgumentList -join ' ') -like '* rev-list --all --count'
            }
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @('refs/heads/main'); ErrorText = '' }
            } -ParameterFilter {
                ($ArgumentList -join ' ') -like '* for-each-ref --format=%(refname) refs/heads'
            }
            Mock Invoke-CgrNativeCommand {
                $tree = if (($ArgumentList -join ' ') -like '*source.git*') { 'source-main-tree' } else { 'destination-main-tree' }
                [pscustomobject] @{ ExitCode = 0; Output = @($tree); ErrorText = '' }
            } -ParameterFilter {
                ($ArgumentList -join ' ') -like '* rev-parse refs/heads/*^{tree}'
            }

            $result = Invoke-CgrRepositoryFullHistoryVerification `
                -SourceRepository $SourceRepositoryFixture `
                -DestinationRepository $DestinationRepositoryFixture

            $result.IsSuccessful | Should -BeFalse
            @($result.Checks | Where-Object Name -EQ 'DefaultBranchMatches')[0].Passed | Should -BeFalse
            @($result.Checks | Where-Object Name -EQ 'BranchAndTagTargetsMatch')[0].Passed | Should -BeFalse
            @($result.Checks | Where-Object Name -EQ 'ReachableCommitCountMatches')[0].Passed | Should -BeFalse
            @($result.Checks | Where-Object Name -EQ 'BranchTipTreesMatch')[0].Passed | Should -BeFalse
            @($result.Checks | Where-Object Name -EQ 'GitLfsObjectsAvailable')[0].Passed | Should -BeTrue
        }
    }

    It 'fails verification when destination LFS objects cannot be fetched' {
        InModuleScope CopyGitHubRepo -Parameters @{
            SourceRepositoryFixture = $script:sourceRepository
            DestinationRepositoryFixture = $script:destinationRepository
        } {
            Mock New-Item { $null }
            Mock Test-Path { $false }
            Mock Remove-Item { $null }
            Mock Invoke-CgrGitCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
            }
            Mock Invoke-CgrGitCommand {
                [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = 'missing LFS object' }
            } -ParameterFilter {
                ($ArgumentList -join ' ') -like '*destination.git lfs fetch --all origin'
            }
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @('git-lfs/3.0.0'); ErrorText = '' }
            } -ParameterFilter {
                ($ArgumentList -join ' ') -eq 'lfs version'
            }
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
            }

            {
                Invoke-CgrRepositoryFullHistoryVerification `
                    -SourceRepository $SourceRepositoryFixture `
                    -DestinationRepository $DestinationRepositoryFixture
            } | Should -Throw -ErrorId 'FullHistoryVerificationDestinationGitLfsFetchFailed,Invoke-CgrRepositoryFullHistoryVerification'
        }
    }
}
