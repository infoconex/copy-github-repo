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
                        IsLatest = $false
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
                        IsLatest = $false
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

    It 'preserves and verifies the approved source latest-release designation' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'acme/source' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination' }
            $selection = [pscustomobject] @{
                Releases = @([pscustomobject] @{
                        ReleaseId = 10
                        TagName = 'v2.0.0'
                        Name = 'Release 2.0'
                        Body = 'approved body'
                        Draft = $false
                        Prerelease = $false
                        IsLatest = $true
                        TargetCommitSha = 'abc123'
                        Assets = @()
                    })
            }
            $script:destinationReleaseReads = 0

            Mock Invoke-CgrNativeCommand {
                $joined = $ArgumentList -join ' '
                if ($joined -match 'repos/acme/source/releases/tags/v2.0.0') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('{"id":10,"tag_name":"v2.0.0","name":"Release 2.0","body":"approved body","draft":false,"prerelease":false,"assets":[]}'); ErrorText = '' }
                }
                if ($joined -match 'repos/acme/source/commits/v2.0.0') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('abc123'); ErrorText = '' }
                }
                if ($joined -match 'repos/acme/destination/commits/v2.0.0') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('abc123'); ErrorText = '' }
                }
                if ($joined -match 'repos/acme/destination/releases/tags/v2.0.0') {
                    $script:destinationReleaseReads++
                    if ($script:destinationReleaseReads -eq 1) {
                        return [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = 'HTTP 404: Not Found' }
                    }
                    return [pscustomobject] @{ ExitCode = 0; Output = @('{"id":20,"tag_name":"v2.0.0","name":"Release 2.0","body":"approved body","draft":false,"prerelease":false,"assets":[]}'); ErrorText = '' }
                }
                if ($joined -match '^release create v2.0.0') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('created'); ErrorText = '' }
                }
                if ($joined -match 'repos/acme/destination/releases/latest') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('{"id":20,"tag_name":"v2.0.0"}'); ErrorText = '' }
                }
                throw "Unexpected native command: $joined"
            }

            $result = Copy-CgrApprovedGitHubRelease -SourceRepository $source -DestinationRepository $destination -ApprovedSelection $selection

            $result.IsSuccessful | Should -BeTrue
            $result.LatestReleasePreserved | Should -BeTrue
            $result.LatestReleaseTag | Should -Be 'v2.0.0'
            Should -Invoke Invoke-CgrNativeCommand -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq 'gh' -and
                ($ArgumentList -join ' ') -match '^release create v2.0.0 .*--latest( |$)'
            }
        }
    }

    It 'returns successful no-op evidence for an approved empty selection' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'acme/source' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination' }
            $selection = [pscustomobject] @{ Releases = @() }
            Mock Invoke-CgrNativeCommand { throw 'Native GitHub operations must not run for an empty approved selection.' }

            $result = Copy-CgrApprovedGitHubRelease -SourceRepository $source -DestinationRepository $destination -ApprovedSelection $selection

            $result.IsSuccessful | Should -BeTrue
            $result.ApprovedReleaseCount | Should -Be 0
            $result.DestinationReleaseCount | Should -Be 0
            Should -Invoke Invoke-CgrNativeCommand -Times 0
        }
    }
}
