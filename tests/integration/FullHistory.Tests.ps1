BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force
}

Describe 'FullHistory migration engine' {
    BeforeEach {
        $script:sourceRepository = [pscustomobject] @{
            FullName = 'infoconex/source'
            Owner = 'infoconex'
            Visibility = 'private'
            DefaultBranch = 'main'
            CloneUrl = 'https://github.com/infoconex/source.git'
            HostName = 'github.com'
        }
        $script:destinationRepository = [pscustomobject] @{
            FullName = 'infoconex/destination'
            Owner = 'infoconex'
            Visibility = 'private'
            DefaultBranch = 'main'
            CloneUrl = 'https://github.com/infoconex/destination.git'
            HostName = 'github.com'
        }
    }

    It 'copies branches tags and detected LFS objects and restores the source default branch' {
        InModuleScope CopyGitHubRepo -Parameters @{
            SourceRepositoryFixture = $script:sourceRepository
            DestinationRepositoryFixture = $script:destinationRepository
        } {
            Mock New-Item { $null }
            Mock Test-Path { $false }
            Mock Remove-Item { $null }
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
            }
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @('git-lfs/3.0.0'); ErrorText = '' }
            } -ParameterFilter {
                ($ArgumentList -join ' ') -eq 'lfs version'
            }
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @('assets/large.bin'); ErrorText = '' }
            } -ParameterFilter {
                ($ArgumentList -join ' ') -like '* lfs ls-files --all --name-only'
            }
            Mock Invoke-CgrGitCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
            }
            Mock Get-CgrRepository { $DestinationRepositoryFixture }

            $result = Copy-CgrRepositoryFullHistory `
                -SourceRepository $SourceRepositoryFixture `
                -DestinationRepository $DestinationRepositoryFixture

            $result.PSTypeNames[0] | Should -Be 'CopyGitHubRepo.FullHistoryCopyResult'
            $result.IsSuccessful | Should -BeTrue
            $result.BranchesCopied | Should -BeTrue
            $result.TagsCopied | Should -BeTrue
            $result.SourceUsesGitLfs | Should -BeTrue
            $result.GitLfsTrackedPaths | Should -Contain 'assets/large.bin'
            $result.GitLfsObjectsCopied | Should -BeTrue
            Should -Invoke Invoke-CgrGitCommand -Times 1 -Exactly -ParameterFilter {
                ($ArgumentList -join ' ') -like 'clone --bare https://github.com/infoconex/source.git *source.git'
            }
            Should -Invoke Invoke-CgrGitCommand -Times 1 -Exactly -ParameterFilter {
                ($ArgumentList -join ' ') -like '* lfs fetch --all origin'
            }
            Should -Invoke Invoke-CgrGitCommand -Times 1 -Exactly -ParameterFilter {
                ($ArgumentList -join ' ') -like '* lfs push --all cgr-destination'
            }
            Should -Invoke Invoke-CgrGitCommand -Times 1 -Exactly -ParameterFilter {
                ($ArgumentList -join ' ') -like '* push cgr-destination --all'
            }
            Should -Invoke Invoke-CgrGitCommand -Times 1 -Exactly -ParameterFilter {
                ($ArgumentList -join ' ') -like '* push cgr-destination --tags'
            }
            Should -Invoke Invoke-CgrNativeCommand -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq 'gh' -and
                ($ArgumentList -join ' ') -eq 'api --hostname github.com -X PATCH repos/infoconex/destination -f default_branch=main'
            }
        }
    }

    It 'treats a repository without LFS paths as a successful no-op instead of claiming a transfer' {
        InModuleScope CopyGitHubRepo -Parameters @{
            SourceRepositoryFixture = $script:sourceRepository
            DestinationRepositoryFixture = $script:destinationRepository
        } {
            Mock New-Item { $null }
            Mock Test-Path { $false }
            Mock Remove-Item { $null }
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
            }
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @('git-lfs/3.0.0'); ErrorText = '' }
            } -ParameterFilter {
                ($ArgumentList -join ' ') -eq 'lfs version'
            }
            Mock Invoke-CgrGitCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
            }
            Mock Get-CgrRepository { $DestinationRepositoryFixture }
            $script:activityEvents = [System.Collections.Generic.List[object]]::new()
            Mock Send-CgrActivityEvent {
                param($Name, $State, $Message, $Current, $Total)
                $script:activityEvents.Add([pscustomobject] @{ Name = $Name; State = $State; Message = $Message; Current = $Current; Total = $Total })
            }

            $result = Copy-CgrRepositoryFullHistory `
                -SourceRepository $SourceRepositoryFixture `
                -DestinationRepository $DestinationRepositoryFixture

            $result.IsSuccessful | Should -BeTrue
            $result.SourceUsesGitLfs | Should -BeFalse
            $result.GitLfsObjectsCopied | Should -BeFalse
            Should -Invoke Invoke-CgrGitCommand -Times 0 -Exactly -ParameterFilter {
                ($ArgumentList -join ' ') -like '* lfs fetch --all origin'
            }
            Should -Invoke Invoke-CgrGitCommand -Times 0 -Exactly -ParameterFilter {
                ($ArgumentList -join ' ') -like '* lfs push --all cgr-destination'
            }
            @($script:activityEvents | Where-Object {
                $_.Name -eq 'InspectGitLfs' -and
                $_.State -eq 'Completed' -and
                $_.Message -eq 'No Git LFS objects found; no transfer required.'
            }).Count | Should -Be 1
        }
    }

    It 'requires Git LFS before beginning FullHistory migration' {
        InModuleScope CopyGitHubRepo -Parameters @{
            SourceRepositoryFixture = $script:sourceRepository
            DestinationRepositoryFixture = $script:destinationRepository
        } {
            Mock New-Item { $null }
            Mock Test-Path { $false }
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = 'git: lfs is not a git command' }
            }
            Mock Invoke-CgrGitCommand { throw 'Clone must not occur when Git LFS is unavailable.' }

            {
                Copy-CgrRepositoryFullHistory `
                    -SourceRepository $SourceRepositoryFixture `
                    -DestinationRepository $DestinationRepositoryFixture
            } | Should -Throw -ErrorId 'GitLfsRequiredForFullHistory,Copy-CgrRepositoryFullHistory'

            Should -Invoke Invoke-CgrGitCommand -Times 0 -Exactly
        }
    }
}

Describe 'FullHistory migration verification' {
    BeforeEach {
        $script:sourceRepository = [pscustomobject] @{
            FullName = 'infoconex/source'
            DefaultBranch = 'main'
            CloneUrl = 'https://github.com/infoconex/source.git'
            HostName = 'github.com'
        }
        $script:destinationRepository = [pscustomobject] @{
            FullName = 'infoconex/destination'
            DefaultBranch = 'main'
            CloneUrl = 'https://github.com/infoconex/destination.git'
            HostName = 'github.com'
        }
    }

    It 'verifies identical branch and tag targets commit counts branch trees and LFS availability' {
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
                [pscustomobject] @{ ExitCode = 0; Output = @(
                    'refs/heads/feature 2222222222222222222222222222222222222222'
                    'refs/heads/main 1111111111111111111111111111111111111111'
                    'refs/tags/v1.0.0 3333333333333333333333333333333333333333'
                ); ErrorText = '' }
            } -ParameterFilter {
                ($ArgumentList -join ' ') -like '* for-each-ref --format=%(refname) %(objectname) refs/heads refs/tags'
            }
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @('3'); ErrorText = '' }
            } -ParameterFilter {
                ($ArgumentList -join ' ') -like '* rev-list --all --count'
            }
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @('refs/heads/feature', 'refs/heads/main'); ErrorText = '' }
            } -ParameterFilter {
                ($ArgumentList -join ' ') -like '* for-each-ref --format=%(refname) refs/heads'
            }
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{
                    ExitCode = 0
                    Output = if (($ArgumentList -join ' ') -match 'feature\^\{tree\}') { @('feature-tree') } else { @('main-tree') }
                    ErrorText = ''
                }
            } -ParameterFilter {
                ($ArgumentList -join ' ') -like '* rev-parse refs/heads/*^{tree}'
            }

            $result = Invoke-CgrRepositoryFullHistoryVerification `
                -SourceRepository $SourceRepositoryFixture `
                -DestinationRepository $DestinationRepositoryFixture

            $result.PSTypeNames[0] | Should -Be 'CopyGitHubRepo.MigrationVerificationResult'
            $result.ContentMode | Should -Be 'FullHistory'
            $result.IsSuccessful | Should -BeTrue
            $result.SourceRefCount | Should -Be 3
            $result.DestinationRefCount | Should -Be 3
            $result.SourceReachableCommitCount | Should -Be 3
            $result.DestinationReachableCommitCount | Should -Be 3
            @($result.Checks | Where-Object Name -eq 'BranchAndTagTargetsMatch')[0].Passed | Should -BeTrue
            @($result.Checks | Where-Object Name -eq 'BranchTipTreesMatch')[0].Passed | Should -BeTrue
            @($result.Checks | Where-Object Name -eq 'GitLfsObjectsAvailable')[0].Passed | Should -BeTrue
        }
    }
}
