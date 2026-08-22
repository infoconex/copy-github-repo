BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force

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

Describe 'GitHub API failure boundaries' {
    It 'returns a structured error for a failed GitHub API request' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = '403 Forbidden' }
            }

            {
                Get-CgrGitHubApi -Path 'repos/infoconex/source'
            } | Should -Throw -ErrorId 'GitHubApiRequestFailed,Get-CgrGitHubApi'
        }
    }

    It 'returns a structured error for malformed successful GitHub API JSON' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @('{not-json'); ErrorText = '' }
            }

            {
                Get-CgrGitHubApi -Path 'repos/infoconex/source'
            } | Should -Throw -ErrorId 'GitHubApiResponseInvalid,Get-CgrGitHubApi'
        }
    }

    It 'treats only a not-found repository response as nonexistence' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = 'HTTP 404: Not Found' }
            }

            Test-CgrGitHubRepositoryExistence -Repository 'infoconex/source' | Should -BeFalse
        }
    }

    It 'does not hide non-404 repository existence failures' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = 'HTTP 503: Service Unavailable' }
            }

            {
                Test-CgrGitHubRepositoryExistence -Repository 'infoconex/source'
            } | Should -Throw -ErrorId 'GitHubRepositoryExistenceCheckFailed,Test-CgrGitHubRepositoryExistence'
        }
    }
}

Describe 'Git LFS destructive-boundary failures' {
    BeforeEach {
        Set-Content -LiteralPath (Join-Path $TestDrive '.gitattributes') -Value '*.bin filter=lfs diff=lfs merge=lfs -text'
    }

    It 'stops with a structured error when tracked LFS files cannot be listed' {
        InModuleScope CopyGitHubRepo -Parameters @{
            SourceRepositoryFixture = $script:sourceRepository
            DestinationRepositoryFixture = $script:destinationRepository
            SourcePath = $TestDrive
        } {
            Mock Invoke-CgrNativeCommand {
                $arguments = $ArgumentList -join ' '
                if ($arguments -eq 'lfs version') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('git-lfs/3.7.0'); ErrorText = '' }
                }
                if ($arguments -like '* lfs ls-files --name-only') {
                    return [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = 'corrupt index' }
                }
                throw "Unexpected native Git invocation: $arguments"
            }

            {
                Copy-CgrGitLfsObject -SourcePath $SourcePath -SourceRepository $SourceRepositoryFixture -DestinationRepository $DestinationRepositoryFixture -BranchName main
            } | Should -Throw -ErrorId 'GitLfsPointerDetectionFailed,Copy-CgrGitLfsObject'
        }
    }

    It 'stops before destination mutation when source LFS fetch fails' {
        InModuleScope CopyGitHubRepo -Parameters @{
            SourceRepositoryFixture = $script:sourceRepository
            DestinationRepositoryFixture = $script:destinationRepository
            SourcePath = $TestDrive
        } {
            Mock Invoke-CgrNativeCommand {
                $arguments = $ArgumentList -join ' '
                if ($arguments -eq 'lfs version') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('git-lfs/3.7.0'); ErrorText = '' }
                }
                if ($arguments -like '* lfs ls-files --name-only') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('payload.bin'); ErrorText = '' }
                }
                if ($arguments -like '* remote add cgr-destination *') {
                    throw 'Destination remote must not be configured after source fetch failure.'
                }
                throw "Unexpected native Git invocation: $arguments"
            }
            Mock Invoke-CgrGitCommand {
                [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = 'missing LFS object' }
            }

            {
                Copy-CgrGitLfsObject -SourcePath $SourcePath -SourceRepository $SourceRepositoryFixture -DestinationRepository $DestinationRepositoryFixture -BranchName main
            } | Should -Throw -ErrorId 'SourceGitLfsFetchFailed,Copy-CgrGitLfsObject'

            Should -Invoke Invoke-CgrNativeCommand -Times 0 -Exactly -ParameterFilter {
                ($ArgumentList -join ' ') -like '* remote add cgr-destination *'
            }
        }
    }

    It 'removes the temporary destination remote even when the LFS push fails' {
        InModuleScope CopyGitHubRepo -Parameters @{
            SourceRepositoryFixture = $script:sourceRepository
            DestinationRepositoryFixture = $script:destinationRepository
            SourcePath = $TestDrive
        } {
            Mock Invoke-CgrNativeCommand {
                $arguments = $ArgumentList -join ' '
                if ($arguments -eq 'lfs version') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('git-lfs/3.7.0'); ErrorText = '' }
                }
                if ($arguments -like '* lfs ls-files --name-only') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('payload.bin'); ErrorText = '' }
                }
                if ($arguments -like '* remote add cgr-destination *' -or $arguments -like '* remote remove cgr-destination') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
                }
                throw "Unexpected native Git invocation: $arguments"
            }
            Mock Invoke-CgrGitCommand {
                $arguments = $ArgumentList -join ' '
                if ($arguments -like '* lfs fetch origin main') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
                }
                if ($arguments -like '* lfs push --all cgr-destination main') {
                    return [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = 'destination rejected LFS object' }
                }
                throw "Unexpected authenticated Git invocation: $arguments"
            }

            {
                Copy-CgrGitLfsObject -SourcePath $SourcePath -SourceRepository $SourceRepositoryFixture -DestinationRepository $DestinationRepositoryFixture -BranchName main
            } | Should -Throw -ErrorId 'DestinationGitLfsPushFailed,Copy-CgrGitLfsObject'

            Should -Invoke Invoke-CgrNativeCommand -Times 1 -Exactly -ParameterFilter {
                ($ArgumentList -join ' ') -like '* remote remove cgr-destination'
            }
        }
    }
}

Describe 'Snapshot Git safety failures' {
    It 'reports source clone failure before creating or pushing a snapshot' {
        InModuleScope CopyGitHubRepo -Parameters @{
            SourceRepositoryFixture = $script:sourceRepository
            DestinationRepositoryFixture = $script:destinationRepository
        } {
            Mock Invoke-CgrGitCommand {
                [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = 'source unavailable' }
            }
            Mock Invoke-CgrNativeCommand { throw 'Native Git must not run after clone failure.' }
            Mock Copy-CgrGitLfsObject { throw 'Git LFS must not run after clone failure.' }

            {
                Copy-CgrRepositorySnapshot -SourceRepository $SourceRepositoryFixture -DestinationRepository $DestinationRepositoryFixture -BranchName main -CommitMessage 'Snapshot'
            } | Should -Throw -ErrorId 'SourceRepositoryCloneFailed,Copy-CgrRepositorySnapshot'

            Should -Invoke Invoke-CgrNativeCommand -Times 0 -Exactly
            Should -Invoke Copy-CgrGitLfsObject -Times 0 -Exactly
        }
    }

    It 'reports a destination snapshot push failure after preparing the source snapshot' {
        InModuleScope CopyGitHubRepo -Parameters @{
            SourceRepositoryFixture = $script:sourceRepository
            DestinationRepositoryFixture = $script:destinationRepository
        } {
            Mock Invoke-CgrGitCommand {
                $arguments = $ArgumentList -join ' '
                if ($arguments -match '^clone ') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
                }
                if ($arguments -like '* push https://github.com/infoconex/destination.git *') {
                    return [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = 'protected branch rejected update' }
                }
                throw "Unexpected authenticated Git invocation: $arguments"
            }
            Mock Invoke-CgrNativeCommand {
                $arguments = $ArgumentList -join ' '
                if ($arguments -like '* rev-parse HEAD') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('source-commit-sha'); ErrorText = '' }
                }
                if ($arguments -like '* rev-parse HEAD^{tree}') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('tree-sha'); ErrorText = '' }
                }
                if ($arguments -like '* commit-tree tree-sha *') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('snapshot-sha'); ErrorText = '' }
                }
                throw "Unexpected native Git invocation: $arguments"
            }
            Mock Copy-CgrGitLfsObject {
                [pscustomobject] @{ UsesGitLfs = $false; PointerFiles = @(); ObjectsCopied = $false; IsSuccessful = $true }
            }

            {
                Copy-CgrRepositorySnapshot -SourceRepository $SourceRepositoryFixture -DestinationRepository $DestinationRepositoryFixture -BranchName main -CommitMessage 'Snapshot'
            } | Should -Throw -ErrorId 'DestinationRepositorySnapshotPushFailed,Copy-CgrRepositorySnapshot'
        }
    }

    It 'rejects a destination branch that does not reference the created snapshot commit' {
        InModuleScope CopyGitHubRepo -Parameters @{
            SourceRepositoryFixture = $script:sourceRepository
            DestinationRepositoryFixture = $script:destinationRepository
        } {
            Mock Invoke-CgrGitCommand {
                $arguments = $ArgumentList -join ' '
                if ($arguments -match '^clone ') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
                }
                if ($arguments -like '* push https://github.com/infoconex/destination.git *') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
                }
                if ($arguments -match '^ls-remote --heads ') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('different-sha refs/heads/main'); ErrorText = '' }
                }
                throw "Unexpected authenticated Git invocation: $arguments"
            }
            Mock Invoke-CgrNativeCommand {
                $arguments = $ArgumentList -join ' '
                if ($arguments -like '* rev-parse HEAD') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('source-commit-sha'); ErrorText = '' }
                }
                if ($arguments -like '* rev-parse HEAD^{tree}') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('tree-sha'); ErrorText = '' }
                }
                if ($arguments -like '* commit-tree tree-sha *') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('snapshot-sha'); ErrorText = '' }
                }
                throw "Unexpected native Git invocation: $arguments"
            }
            Mock Copy-CgrGitLfsObject {
                [pscustomobject] @{ UsesGitLfs = $false; PointerFiles = @(); ObjectsCopied = $false; IsSuccessful = $true }
            }

            {
                Copy-CgrRepositorySnapshot -SourceRepository $SourceRepositoryFixture -DestinationRepository $DestinationRepositoryFixture -BranchName main -CommitMessage 'Snapshot'
            } | Should -Throw -ErrorId 'DestinationRepositorySnapshotVerifyMismatch,Copy-CgrRepositorySnapshot'
        }
    }
}
