BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'GitHub Release destination safety' {
    It 'refuses to overwrite an existing destination GitHub Release' {
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
                if ($joined -match 'repos/acme/source/releases/tags/v1.0.0') {
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
                    return [pscustomobject] @{ ExitCode = 0; Output = @('abc123'); ErrorText = '' }
                }
                if ($joined -match 'repos/acme/destination/releases/tags/v1.0.0') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('{"id":20,"tag_name":"v1.0.0"}'); ErrorText = '' }
                }
                if ($joined -match '^release create v1.0.0') {
                    throw 'release create must not run when destination release already exists'
                }
                throw "Unexpected native command: $joined"
            }

            { Copy-CgrApprovedGitHubRelease `
                    -SourceRepository $source `
                    -DestinationRepository $destination `
                    -ApprovedSelection $selection } |
                Should -Throw -ErrorId 'DestinationGitHubReleaseAlreadyExists,Copy-CgrApprovedGitHubRelease'

            Should -Invoke Invoke-CgrNativeCommand -Times 0 -ParameterFilter {
                $FilePath -eq 'gh' -and ($ArgumentList -join ' ') -match '^release create v1.0.0'
            }
        }
    }

    It 'fails closed when destination release existence cannot be read' {
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
                if ($joined -match 'repos/acme/source/releases/tags/v1.0.0') {
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
                    return [pscustomobject] @{ ExitCode = 0; Output = @('abc123'); ErrorText = '' }
                }
                if ($joined -match 'repos/acme/destination/releases/tags/v1.0.0') {
                    return [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = 'HTTP 503: Service Unavailable' }
                }
                if ($joined -match '^release create v1.0.0') {
                    throw 'release create must not run when the destination release read is ambiguous'
                }
                throw "Unexpected native command: $joined"
            }

            { Copy-CgrApprovedGitHubRelease `
                    -SourceRepository $source `
                    -DestinationRepository $destination `
                    -ApprovedSelection $selection } |
                Should -Throw -ErrorId 'DestinationGitHubReleaseReadFailed,Copy-CgrApprovedGitHubRelease'

            Should -Invoke Invoke-CgrNativeCommand -Times 0 -ParameterFilter {
                $FilePath -eq 'gh' -and ($ArgumentList -join ' ') -match '^release create v1.0.0'
            }
        }
    }
}
