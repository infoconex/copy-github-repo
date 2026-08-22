BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force
}

Describe 'Git LFS snapshot migration' {
    BeforeEach {
        $script:sourceRepository = [pscustomobject] @{
            FullName = 'infoconex/source'
            CloneUrl = 'https://github.com/infoconex/source.git'
            HostName = 'github.com'
        }
        $script:destinationRepository = [pscustomobject] @{
            FullName = 'infoconex/destination'
            CloneUrl = 'https://github.com/infoconex/destination.git'
            HostName = 'github.com'
        }
    }

    It 'does nothing when the checked-out tree is not configured for Git LFS' {
        InModuleScope CopyGitHubRepo -Parameters @{
            SourceRepositoryFixture = $script:sourceRepository
            DestinationRepositoryFixture = $script:destinationRepository
            SourcePath = $TestDrive
        } {
            Mock Invoke-CgrNativeCommand { throw 'Git LFS commands should not run for a non-LFS repository.' }
            Mock Invoke-CgrGitCommand { throw 'Network Git LFS commands should not run for a non-LFS repository.' }

            $result = Copy-CgrGitLfsObject `
                -SourcePath $SourcePath `
                -SourceRepository $SourceRepositoryFixture `
                -DestinationRepository $DestinationRepositoryFixture `
                -BranchName main

            $result.UsesGitLfs | Should -BeFalse
            $result.ObjectsCopied | Should -BeFalse
            $result.IsSuccessful | Should -BeTrue
            Should -Invoke Invoke-CgrNativeCommand -Times 0 -Exactly
            Should -Invoke Invoke-CgrGitCommand -Times 0 -Exactly
        }
    }

    It 'requires Git LFS when tracked files are configured' {
        Set-Content -LiteralPath (Join-Path $TestDrive '.gitattributes') -Value '*.bin filter=lfs diff=lfs merge=lfs -text'

        InModuleScope CopyGitHubRepo -Parameters @{
            SourceRepositoryFixture = $script:sourceRepository
            DestinationRepositoryFixture = $script:destinationRepository
            SourcePath = $TestDrive
        } {
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{
                    ExitCode = 1
                    Output = @()
                    ErrorText = 'git: lfs is not a git command'
                }
            } -ParameterFilter {
                $FilePath -eq 'git' -and ($ArgumentList -join ' ') -eq 'lfs version'
            }

            {
                Copy-CgrGitLfsObject `
                    -SourcePath $SourcePath `
                    -SourceRepository $SourceRepositoryFixture `
                    -DestinationRepository $DestinationRepositoryFixture `
                    -BranchName main
            } | Should -Throw -ErrorId 'GitLfsRequired,Copy-CgrGitLfsObject'
        }
    }

    It 'fetches source LFS objects and pushes them to the destination before success' {
        Set-Content -LiteralPath (Join-Path $TestDrive '.gitattributes') -Value '*.bin filter=lfs diff=lfs merge=lfs -text'

        InModuleScope CopyGitHubRepo -Parameters @{
            SourceRepositoryFixture = $script:sourceRepository
            DestinationRepositoryFixture = $script:destinationRepository
            SourcePath = $TestDrive
        } {
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @('git-lfs/3.7.0'); ErrorText = '' }
            } -ParameterFilter {
                $FilePath -eq 'git' -and ($ArgumentList -join ' ') -eq 'lfs version'
            }
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @('payload.bin'); ErrorText = '' }
            } -ParameterFilter {
                $FilePath -eq 'git' -and ($ArgumentList -join ' ') -like '* lfs ls-files --name-only'
            }
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
            } -ParameterFilter {
                $FilePath -eq 'git' -and ($ArgumentList -join ' ') -like '* remote add cgr-destination https://github.com/infoconex/destination.git'
            }
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
            } -ParameterFilter {
                $FilePath -eq 'git' -and ($ArgumentList -join ' ') -like '* remote remove cgr-destination'
            }
            Mock Invoke-CgrGitCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
            } -ParameterFilter {
                $HostName -eq 'github.com' -and ($ArgumentList -join ' ') -like '* lfs fetch origin main'
            }
            Mock Invoke-CgrGitCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
            } -ParameterFilter {
                $HostName -eq 'github.com' -and ($ArgumentList -join ' ') -like '* lfs push --all cgr-destination main'
            }

            $result = Copy-CgrGitLfsObject `
                -SourcePath $SourcePath `
                -SourceRepository $SourceRepositoryFixture `
                -DestinationRepository $DestinationRepositoryFixture `
                -BranchName main

            $result.UsesGitLfs | Should -BeTrue
            $result.ObjectsCopied | Should -BeTrue
            @($result.PointerFiles) | Should -Contain 'payload.bin'
            Should -Invoke Invoke-CgrGitCommand -Times 1 -Exactly -ParameterFilter {
                ($ArgumentList -join ' ') -like '* lfs fetch origin main'
            }
            Should -Invoke Invoke-CgrGitCommand -Times 1 -Exactly -ParameterFilter {
                ($ArgumentList -join ' ') -like '* lfs push --all cgr-destination main'
            }
            Should -Invoke Invoke-CgrNativeCommand -Times 1 -Exactly -ParameterFilter {
                ($ArgumentList -join ' ') -like '* remote remove cgr-destination'
            }
        }
    }
}
