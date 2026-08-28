BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Approved GitHub Release execution' {
    It 'fails closed when approved release metadata changes after planning' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'acme/source' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination' }
            $selection = [pscustomobject] @{
                Releases = @([pscustomobject] @{
                        ReleaseId = 10
                        TagName = 'v1.0.0'
                        Name = 'Release 1.0'
                        Body = 'approved body'
                        Draft = $false
                        Prerelease = $false
                        TargetCommitSha = 'abc123'
                        Assets = @()
                    })
            }

            Mock Invoke-CgrNativeCommand {
                $joined = $ArgumentList -join ' '
                if ($joined -match 'releases/tags/v1.0.0') {
                    return [pscustomobject] @{
                        ExitCode = 0
                        Output = @('{"id":10,"tag_name":"v1.0.0","name":"Release 1.0","body":"changed body","draft":false,"prerelease":false,"assets":[]}')
                        ErrorText = ''
                    }
                }
                if ($joined -match 'repos/acme/source/commits/v1.0.0') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('abc123'); ErrorText = '' }
                }
                if ($joined -match 'repos/acme/destination/commits/v1.0.0') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('abc123'); ErrorText = '' }
                }
                throw "Unexpected native command: $joined"
            }

            { Copy-CgrApprovedGitHubRelease -SourceRepository $source -DestinationRepository $destination -ApprovedSelection $selection } |
                Should -Throw -ErrorId 'SourceReleaseStateChangedSincePlanning,Copy-CgrApprovedGitHubRelease'
        }
    }

    It 'fails closed when the destination release tag target differs from the approved commit' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'acme/source' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination' }
            $selection = [pscustomobject] @{
                Releases = @([pscustomobject] @{
                        ReleaseId = 10
                        TagName = 'v1.0.0'
                        Name = 'Release 1.0'
                        Body = 'approved body'
                        Draft = $false
                        Prerelease = $false
                        TargetCommitSha = 'abc123'
                        Assets = @()
                    })
            }

            Mock Invoke-CgrNativeCommand {
                $joined = $ArgumentList -join ' '
                if ($joined -match 'releases/tags/v1.0.0') {
                    return [pscustomobject] @{
                        ExitCode = 0
                        Output = @('{"id":10,"tag_name":"v1.0.0","name":"Release 1.0","body":"approved body","draft":false,"prerelease":false,"assets":[]}')
                        ErrorText = ''
                    }
                }
                if ($joined -match 'repos/acme/source/commits/v1.0.0') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('abc123'); ErrorText = '' }
                }
                if ($joined -match 'repos/acme/destination/commits/v1.0.0') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('different'); ErrorText = '' }
                }
                throw "Unexpected native command: $joined"
            }

            { Copy-CgrApprovedGitHubRelease -SourceRepository $source -DestinationRepository $destination -ApprovedSelection $selection } |
                Should -Throw -ErrorId 'GitHubReleaseTagTargetMismatch,Copy-CgrApprovedGitHubRelease'
        }
    }

    It 'returns successful no-op evidence for an approved empty selection' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'acme/source' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination' }
            $selection = [pscustomobject] @{ Releases = @() }

            $result = Copy-CgrApprovedGitHubRelease -SourceRepository $source -DestinationRepository $destination -ApprovedSelection $selection

            $result.IsSuccessful | Should -BeTrue
            $result.ApprovedReleaseCount | Should -Be 0
            $result.DestinationReleaseCount | Should -Be 0
            Should -Invoke Invoke-CgrNativeCommand -Times 0
        }
    }
}
