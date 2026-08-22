BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force
}

Describe 'Same-name replacement safety primitives' {
    BeforeEach {
        $script:sourceRepository = [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.Repository'
            Id = 101L
            NodeId = 'R_source'
            Name = 'source'
            FullName = 'infoconex/source'
            Owner = 'infoconex'
            Visibility = 'private'
            DefaultBranch = 'main'
            CloneUrl = 'https://github.com/infoconex/source.git'
            HostName = 'github.com'
        }

        $script:archiveRepository = [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.Repository'
            Id = 101L
            NodeId = 'R_source'
            Name = 'source-archive'
            FullName = 'infoconex/source-archive'
            Owner = 'infoconex'
            Visibility = 'private'
            DefaultBranch = 'main'
            CloneUrl = 'https://github.com/infoconex/source-archive.git'
            HostName = 'github.com'
        }
    }

    It 'captures the default-branch Git tree without smudging LFS objects' {
        InModuleScope CopyGitHubRepo -Parameters @{
            SourceRepositoryFixture = $script:sourceRepository
        } {
            Mock Invoke-CgrGitCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
            }
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{
                    ExitCode = 0
                    Output = @('89abcdef0123456789abcdef0123456789abcdef')
                    ErrorText = ''
                }
            } -ParameterFilter {
                $FilePath -eq 'git' -and ($ArgumentList -join ' ') -like '* rev-parse HEAD'
            }
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{
                    ExitCode = 0
                    Output = @('0123456789abcdef0123456789abcdef01234567')
                    ErrorText = ''
                }
            } -ParameterFilter {
                $FilePath -eq 'git' -and ($ArgumentList -join ' ') -like '* rev-parse HEAD^{tree}'
            }

            $result = Get-CgrRepositoryDefaultBranchTree -Repository $SourceRepositoryFixture

            $result.PSTypeNames[0] | Should -Be 'CopyGitHubRepo.RepositoryTreeIdentity'
            $result.Repository | Should -Be 'infoconex/source'
            $result.BranchName | Should -Be 'main'
            $result.CommitSha | Should -Be '89abcdef0123456789abcdef0123456789abcdef'
            $result.TreeSha | Should -Be '0123456789abcdef0123456789abcdef01234567'
            Should -Invoke Invoke-CgrGitCommand -Times 1 -Exactly -ParameterFilter {
                $HostName -eq 'github.com' -and
                ($ArgumentList -join ' ') -like 'clone --depth 1 --branch main https://github.com/infoconex/source.git *' -and
                $Environment.GIT_LFS_SKIP_SMUDGE -eq '1'
            }
        }
    }

    It 'renames the source to the exact archive repository and verifies immutable identity' {
        InModuleScope CopyGitHubRepo -Parameters @{
            SourceRepositoryFixture = $script:sourceRepository
            ArchiveRepositoryFixture = $script:archiveRepository
        } {
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
            } -ParameterFilter {
                $FilePath -eq 'gh' -and
                ($ArgumentList -join ' ') -eq 'api --hostname github.com -X PATCH repos/infoconex/source -f name=source-archive'
            }
            Mock Get-CgrRepository { $ArchiveRepositoryFixture } -ParameterFilter {
                $Repository -eq 'infoconex/source-archive' -and $HostName -eq 'github.com'
            }

            $result = Rename-CgrGitHubRepository `
                -SourceRepository $SourceRepositoryFixture `
                -ArchiveRepository 'infoconex/source-archive'

            $result.FullName | Should -Be 'infoconex/source-archive'
            $result.Id | Should -Be 101
            Should -Invoke Invoke-CgrNativeCommand -Times 1 -Exactly
            Should -Invoke Get-CgrRepository -Times 1 -Exactly
        }
    }

    It 'rejects missing source identity before mutation' {
        $sourceWithoutId = $script:sourceRepository.PSObject.Copy()
        $sourceWithoutId.PSObject.Properties.Remove('Id')

        InModuleScope CopyGitHubRepo -Parameters @{
            SourceRepositoryFixture = $sourceWithoutId
        } {
            Mock Invoke-CgrNativeCommand { throw 'Rename must not run without source identity.' }

            {
                Rename-CgrGitHubRepository `
                    -SourceRepository $SourceRepositoryFixture `
                    -ArchiveRepository 'infoconex/source-archive'
            } | Should -Throw -ErrorId 'SourceRepositoryIdentityMissing,Rename-CgrGitHubRepository'

            Should -Invoke Invoke-CgrNativeCommand -Times 0 -Exactly
        }
    }

    It 'rejects an archive with a different immutable repository ID' {
        $differentArchive = $script:archiveRepository.PSObject.Copy()
        $differentArchive.Id = 999L

        InModuleScope CopyGitHubRepo -Parameters @{
            SourceRepositoryFixture = $script:sourceRepository
            DifferentArchiveFixture = $differentArchive
        } {
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
            }
            Mock Get-CgrRepository { $DifferentArchiveFixture }

            {
                Rename-CgrGitHubRepository `
                    -SourceRepository $SourceRepositoryFixture `
                    -ArchiveRepository 'infoconex/source-archive'
            } | Should -Throw -ErrorId 'GitHubRepositoryRenameIdentityMismatch,Rename-CgrGitHubRepository'
        }
    }

    It 'rejects moving the archive to a different owner before mutation' {
        InModuleScope CopyGitHubRepo -Parameters @{
            SourceRepositoryFixture = $script:sourceRepository
        } {
            Mock Invoke-CgrNativeCommand { throw 'Rename must not run for an owner mismatch.' }

            {
                Rename-CgrGitHubRepository `
                    -SourceRepository $SourceRepositoryFixture `
                    -ArchiveRepository 'someone-else/source-archive'
            } | Should -Throw -ErrorId 'ArchiveRepositoryOwnerMismatch,Rename-CgrGitHubRepository'

            Should -Invoke Invoke-CgrNativeCommand -Times 0 -Exactly
        }
    }

    It 'fails when GitHub does not expose the renamed repository under the expected archive name' {
        $unexpectedRepository = $script:archiveRepository.PSObject.Copy()
        $unexpectedRepository.FullName = 'infoconex/unexpected-name'

        InModuleScope CopyGitHubRepo -Parameters @{
            SourceRepositoryFixture = $script:sourceRepository
            UnexpectedRepositoryFixture = $unexpectedRepository
        } {
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
            }
            Mock Get-CgrRepository { $UnexpectedRepositoryFixture }

            {
                Rename-CgrGitHubRepository `
                    -SourceRepository $SourceRepositoryFixture `
                    -ArchiveRepository 'infoconex/source-archive'
            } | Should -Throw -ErrorId 'GitHubRepositoryRenameVerificationFailed,Rename-CgrGitHubRepository'
        }
    }

    It 'requires a new replacement repository to have a distinct immutable ID' {
        $replacement = $script:sourceRepository.PSObject.Copy()
        $replacement.FullName = 'infoconex/source'

        InModuleScope CopyGitHubRepo -Parameters @{
            SourceRepositoryFixture = $script:sourceRepository
            ArchiveRepositoryFixture = $script:archiveRepository
            ReplacementRepositoryFixture = $replacement
        } {
            {
                Assert-CgrReplacementRepositoryIdentity `
                    -SourceRepository $SourceRepositoryFixture `
                    -ArchiveRepository $ArchiveRepositoryFixture `
                    -ReplacementRepository $ReplacementRepositoryFixture
            } | Should -Throw -ErrorId 'ReplacementRepositoryIdentityCollision,Assert-CgrReplacementRepositoryIdentity'
        }
    }

    It 'rejects a replacement repository with missing immutable identity' {
        $replacement = [pscustomobject] @{ FullName = 'infoconex/source' }

        InModuleScope CopyGitHubRepo -Parameters @{
            SourceRepositoryFixture = $script:sourceRepository
            ArchiveRepositoryFixture = $script:archiveRepository
            ReplacementRepositoryFixture = $replacement
        } {
            {
                Assert-CgrReplacementRepositoryIdentity `
                    -SourceRepository $SourceRepositoryFixture `
                    -ArchiveRepository $ArchiveRepositoryFixture `
                    -ReplacementRepository $ReplacementRepositoryFixture
            } | Should -Throw -ErrorId 'ReplacementRepositoryIdentityMissing,Assert-CgrReplacementRepositoryIdentity'
        }
    }
}
