BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'GitHub Release verification read failures' {
    BeforeEach {
        InModuleScope CopyGitHubRepo {
            Mock Get-CgrGitHubReleaseSelection {
                [pscustomobject] @{
                    AvailableReleaseCount = 1
                    SelectedReleaseCount = 1
                    SelectedAssetCount = 0
                    SourceLatestTag = 'v1.0.0'
                    SourceLatestSelected = $true
                    IncludePatterns = @()
                    ExcludePatterns = @()
                    IncludePrerelease = $false
                    IncludeDraftReleases = $false
                    ReleaseCount = $null
                    Releases = @([pscustomobject] @{
                            ReleaseId = 10
                            TagName = 'v1.0.0'
                            Name = 'Release 1.0'
                            Body = 'body'
                            Draft = $false
                            Prerelease = $false
                            IsLatest = $true
                            TargetCommitSha = 'abc123'
                            Assets = @()
                        })
                }
            }
        }
    }

    It 'treats a non-not-found destination tag read failure as a terminating read error' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrNativeCommand {
                [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = 'HTTP 503: Service Unavailable' }
            }

            { Test-CgrGitHubReleaseMigration `
                    -SourceRepository ([pscustomobject] @{ FullName = 'acme/source' }) `
                    -DestinationRepository ([pscustomobject] @{ FullName = 'acme/destination' }) } |
                Should -Throw -ErrorId 'DestinationGitHubReleaseTagReadFailed,Test-CgrGitHubReleaseMigration'
        }
    }

    It 'treats a non-not-found destination release read failure as a terminating read error' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrNativeCommand {
                $joined = $ArgumentList -join ' '
                if ($joined -match 'commits/v1.0.0') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('abc123'); ErrorText = '' }
                }
                return [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = 'HTTP 503: Service Unavailable' }
            }

            { Test-CgrGitHubReleaseMigration `
                    -SourceRepository ([pscustomobject] @{ FullName = 'acme/source' }) `
                    -DestinationRepository ([pscustomobject] @{ FullName = 'acme/destination' }) } |
                Should -Throw -ErrorId 'DestinationGitHubReleaseVerificationReadFailed,Test-CgrGitHubReleaseMigration'
        }
    }

    It 'treats a non-not-found latest-release read failure as a terminating read error' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrNativeCommand {
                $joined = $ArgumentList -join ' '
                if ($joined -match 'commits/v1.0.0') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('abc123'); ErrorText = '' }
                }
                if ($joined -match 'releases/tags/v1.0.0') {
                    return [pscustomobject] @{
                        ExitCode = 0
                        Output = @('{"id":20,"tag_name":"v1.0.0","name":"Release 1.0","body":"body","draft":false,"prerelease":false,"assets":[]}')
                        ErrorText = ''
                    }
                }
                if ($joined -match 'releases/latest') {
                    return [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = 'HTTP 503: Service Unavailable' }
                }
                throw "Unexpected native command: $joined"
            }

            { Test-CgrGitHubReleaseMigration `
                    -SourceRepository ([pscustomobject] @{ FullName = 'acme/source' }) `
                    -DestinationRepository ([pscustomobject] @{ FullName = 'acme/destination' }) } |
                Should -Throw -ErrorId 'DestinationGitHubLatestReleaseVerificationReadFailed,Test-CgrGitHubReleaseMigration'
        }
    }
}
