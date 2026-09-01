BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Approved Snapshot GitHub Release missing asset verification' {
    It 'fails when a reviewed selected release asset is missing from the destination' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'acme/source' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination' }
            $selection = [pscustomobject] @{
                AvailableReleaseCount = 1
                SelectedReleaseCount = 1
                SelectedAssetCount = 1
                SourceLatestTag = 'v2.0.0'
                SourceLatestSelected = $true
                IncludePatterns = @()
                ExcludePatterns = @()
                IncludePrerelease = $false
                IncludeDraftReleases = $false
                ReleaseCount = $null
                Releases = @([pscustomobject] @{
                        ReleaseId = 10
                        TagName = 'v2.0.0'
                        Name = 'Release 2.0'
                        Body = 'reviewed body'
                        Draft = $false
                        Prerelease = $false
                        IsLatest = $true
                        TargetCommitSha = 'source-v2'
                        Assets = @([pscustomobject] @{
                                Name = 'module.zip'
                                Label = 'package'
                                Size = 42
                                ContentType = 'application/zip'
                                Digest = 'sha256:abc'
                            })
                    })
            }
            $targets = @([pscustomobject] @{ TagName = 'v2.0.0'; DestinationCommitSha = 'destination-2' })

            Mock Get-CgrGitHubReleaseSelection { throw 'Approved Snapshot verification must not rerun live source release selection.' }
            Mock Invoke-CgrGitHubApiReadRequest {
                $joined = $ArgumentList -join ' '
                if ($joined -match 'releases\?per_page=100') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('[[{"tag_name":"v2.0.0"}]]'); ErrorText = '' }
                }
                if ($joined -match 'commits/v2.0.0') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('destination-2'); ErrorText = '' }
                }
                if ($joined -match 'releases/tags/v2.0.0') {
                    return [pscustomobject] @{
                        ExitCode = 0
                        Output = @('{"id":20,"tag_name":"v2.0.0","name":"Release 2.0","body":"reviewed body","draft":false,"prerelease":false,"assets":[]}')
                        ErrorText = ''
                    }
                }
                if ($joined -match 'releases/latest') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('{"tag_name":"v2.0.0"}'); ErrorText = '' }
                }
                throw "Unexpected release verification read: $joined"
            }

            $result = Test-CgrGitHubReleaseMigration `
                -SourceRepository $source `
                -DestinationRepository $destination `
                -ApprovedSelection $selection `
                -DestinationTagTargets $targets `
                -RequireExactDestinationReleaseSet

            $result.IsSuccessful | Should -BeFalse
            $result.Releases[0].Mismatches | Should -Contain 'AssetCount'
            $result.Releases[0].Mismatches | Should -Contain 'AssetMissing:module.zip'
            Should -Invoke Get-CgrGitHubReleaseSelection -Times 0
        }
    }
}
