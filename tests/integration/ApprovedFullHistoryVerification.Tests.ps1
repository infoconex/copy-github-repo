BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1') -Force
}

Describe 'Approved FullHistory verification cardinality' {
    It 'preserves one reviewed ref and branch tree as collections' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{
                FullName = 'infoconex/source'
                DefaultBranch = 'main'
                CloneUrl = 'https://github.com/infoconex/source.git'
                HostName = 'github.com'
            }
            $destination = [pscustomobject] @{
                FullName = 'infoconex/destination'
                DefaultBranch = 'main'
                CloneUrl = 'https://github.com/infoconex/destination.git'
                HostName = 'github.com'
            }
            $approvedState = [pscustomobject] @{
                Refs = @('refs/heads/main 1111111111111111111111111111111111111111')
                ReachableCommitCount = 1
                BranchTrees = @('refs/heads/main main-tree')
                DefaultBranch = 'main'
                GitLfsObjectsAvailable = $true
            }

            Mock New-Item { $null }
            Mock Test-Path { $false }
            Mock Remove-Item { $null }
            Mock Invoke-CgrGitCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
            }
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{
                    ExitCode = 0
                    Output = @('refs/heads/main 1111111111111111111111111111111111111111')
                    ErrorText = ''
                }
            } -ParameterFilter {
                ($ArgumentList -join ' ') -like '* for-each-ref --format=%(refname) %(objectname) refs/heads refs/tags'
            }
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @('1'); ErrorText = '' }
            } -ParameterFilter {
                ($ArgumentList -join ' ') -like '* rev-list --all --count'
            }
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @('refs/heads/main'); ErrorText = '' }
            } -ParameterFilter {
                ($ArgumentList -join ' ') -like '* for-each-ref --format=%(refname) refs/heads'
            }
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @('main-tree'); ErrorText = '' }
            } -ParameterFilter {
                ($ArgumentList -join ' ') -like '* rev-parse refs/heads/main^{tree}'
            }

            $result = Invoke-CgrApprovedFullHistoryVerification `
                -SourceRepository $source `
                -DestinationRepository $destination `
                -ApprovedSourceState $approvedState

            $result.IsSuccessful | Should -BeTrue
            $result.SourceRefCount | Should -Be 1
            $result.DestinationRefCount | Should -Be 1
            @($result.Checks | Where-Object Name -EQ 'BranchAndTagTargetsMatch')[0].Passed | Should -BeTrue
            @($result.Checks | Where-Object Name -EQ 'BranchTipTreesMatch')[0].Passed | Should -BeTrue
        }
    }
}
