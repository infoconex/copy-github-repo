BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Independent GitHub Release verification' {
    It 'verifies selected release metadata assets tag identity and Latest designation' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'acme/source' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination' }
            Mock Get-CgrGitHubReleaseSelection {
                [pscustomobject] @{
                    AvailableReleaseCount = 2
                    SelectedReleaseCount = 1
                    SelectedAssetCount = 1
                    SourceLatestTag = 'v2.0.0'
                    SourceLatestSelected = $true
                    IncludePatterns = @('v2.*')
                    ExcludePatterns = @()
                    IncludePrerelease = $false
                    IncludeDraftReleases = $false
                    ReleaseCount = 1
                    Releases = @([pscustomobject] @{
                            ReleaseId = 10
                            TagName = 'v2.0.0'
                            Name = 'Release 2.0'
                            Body = 'release body'
                            Draft = $false
                            Prerelease = $false
                            IsLatest = $true
                            TargetCommitSha = 'abc123'
                            Assets = @([pscustomobject] @{
                                    Name = 'module.zip'
                                    Label = 'package'
                                    Size = 42
                                    ContentType = 'application/zip'
                                    Digest = 'sha256:abc'
                                })
                        })
                }
            }
            Mock Invoke-CgrNativeCommand {
                $joined = $ArgumentList -join ' '
                if ($joined -match 'repos/acme/destination/commits/v2.0.0') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('abc123'); ErrorText = '' }
                }
                if ($joined -match 'repos/acme/destination/releases/tags/v2.0.0') {
                    return [pscustomobject] @{
                        ExitCode = 0
                        Output = @('{"id":20,"tag_name":"v2.0.0","name":"Release 2.0","body":"release body","draft":false,"prerelease":false,"assets":[{"name":"module.zip","label":"package","size":42,"content_type":"application/zip","digest":"sha256:abc"}]}')
                        ErrorText = ''
                    }
                }
                if ($joined -match 'repos/acme/destination/releases/latest') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('{"id":20,"tag_name":"v2.0.0"}'); ErrorText = '' }
                }
                throw "Unexpected native command: $joined"
            }

            $result = Test-CgrGitHubReleaseMigration `
                -SourceRepository $source `
                -DestinationRepository $destination `
                -ReleaseTag 'v2.*' `
                -ReleaseCount 1

            $result.PSTypeNames[0] | Should -Be 'CopyGitHubRepo.ReleaseVerificationResult'
            $result.IsSuccessful | Should -BeTrue
            $result.SelectedReleaseCount | Should -Be 1
            $result.VerifiedReleaseCount | Should -Be 1
            $result.LatestReleaseMatches | Should -BeTrue
            $result.DestinationLatestTag | Should -Be 'v2.0.0'
            $result.Releases[0].Mismatches.Count | Should -Be 0
        }
    }

    It 'returns failed verification when the selected destination release is missing' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'acme/source' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination' }
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
            Mock Invoke-CgrNativeCommand {
                $joined = $ArgumentList -join ' '
                if ($joined -match 'commits/v1.0.0') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('abc123'); ErrorText = '' }
                }
                return [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = 'HTTP 404: Not Found' }
            }

            $result = Test-CgrGitHubReleaseMigration -SourceRepository $source -DestinationRepository $destination

            $result.IsSuccessful | Should -BeFalse
            $result.VerifiedReleaseCount | Should -Be 0
            $result.Releases[0].Mismatches | Should -Contain 'DestinationReleaseMissing'
            $result.LatestReleaseMatches | Should -BeFalse
        }
    }
}

Describe 'Test-GitHubRepositoryMigration release contract' {
    BeforeEach {
        InModuleScope CopyGitHubRepo {
            Mock Get-CgrPrerequisiteStatus {
                [pscustomobject] @{
                    Git = [pscustomobject] @{ Found = $true }
                    GitHubCli = [pscustomobject] @{ Found = $true }
                    Authentication = [pscustomobject] @{ Authenticated = $true; Message = 'Authenticated' }
                }
            }
            Mock Get-CgrRepository {
                param($Repository)
                [pscustomobject] @{
                    FullName = $Repository
                    HostName = 'github.com'
                    CloneUrl = "https://github.com/$Repository.git"
                    DefaultBranch = 'main'
                }
            }
            Mock Invoke-CgrRepositoryFullHistoryVerification {
                [pscustomobject] @{
                    PSTypeName = 'CopyGitHubRepo.MigrationVerificationResult'
                    ContentMode = 'FullHistory'
                    IsSuccessful = $true
                    Checks = @()
                }
            }
            Mock Test-CgrGitHubReleaseMigration {
                [pscustomobject] @{
                    PSTypeName = 'CopyGitHubRepo.ReleaseVerificationResult'
                    SelectedReleaseCount = 1
                    VerifiedReleaseCount = 1
                    IsSuccessful = $true
                }
            }
        }
    }

    It 'combines FullHistory and requested GitHub Release verification' {
        InModuleScope CopyGitHubRepo {
            $result = Test-GitHubRepositoryMigration `
                -SourceRepository 'acme/source' `
                -DestinationRepository 'acme/destination' `
                -ContentMode FullHistory `
                -IncludeReleases `
                -ReleaseTag 'v2.*' `
                -ReleaseCount 1

            $result.GitContentSuccessful | Should -BeTrue
            $result.ReleasesVerified | Should -BeTrue
            $result.ReleaseVerification.SelectedReleaseCount | Should -Be 1
            $result.IsSuccessful | Should -BeTrue
            Should -Invoke Test-CgrGitHubReleaseMigration -Times 1 -Exactly -ParameterFilter {
                $SourceRepository.FullName -eq 'acme/source' -and
                $DestinationRepository.FullName -eq 'acme/destination' -and
                $ReleaseTag[0] -eq 'v2.*' -and
                $ReleaseCount -eq 1
            }
        }
    }

    It 'fails overall verification when releases fail even if Git content passes' {
        InModuleScope CopyGitHubRepo {
            Mock Test-CgrGitHubReleaseMigration {
                [pscustomobject] @{
                    PSTypeName = 'CopyGitHubRepo.ReleaseVerificationResult'
                    SelectedReleaseCount = 1
                    VerifiedReleaseCount = 0
                    IsSuccessful = $false
                }
            }

            $result = Test-GitHubRepositoryMigration `
                -SourceRepository 'acme/source' `
                -DestinationRepository 'acme/destination' `
                -ContentMode FullHistory `
                -IncludeReleases

            $result.GitContentSuccessful | Should -BeTrue
            $result.ReleasesVerified | Should -BeFalse
            $result.IsSuccessful | Should -BeFalse
        }
    }

    It 'rejects release filters without IncludeReleases before prerequisite work' {
        InModuleScope CopyGitHubRepo {
            { Test-GitHubRepositoryMigration `
                    -SourceRepository 'acme/source' `
                    -DestinationRepository 'acme/destination' `
                    -ContentMode FullHistory `
                    -ReleaseTag 'v2.*' } |
                Should -Throw -ErrorId 'ReleaseFilterRequiresIncludeReleases,Test-GitHubRepositoryMigration'

            Should -Invoke Get-CgrPrerequisiteStatus -Times 0
        }
    }

    It 'requires immutable approved evidence for Snapshot release verification' {
        InModuleScope CopyGitHubRepo {
            { Test-GitHubRepositoryMigration `
                    -SourceRepository 'acme/source' `
                    -DestinationRepository 'acme/destination' `
                    -IncludeReleases } |
                Should -Throw -ErrorId 'SnapshotReleaseVerificationPlanRequired,Test-GitHubRepositoryMigration'

            Should -Invoke Get-CgrPrerequisiteStatus -Times 0
        }
    }
}
