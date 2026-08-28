BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'GitHub Release selection' {
    BeforeEach {
        InModuleScope CopyGitHubRepo {
            $script:releasePayload = @(
                [pscustomobject] @{
                    id = 1; tag_name = 'v1.0.0'; name = '1.0.0'; body = 'stable one'; draft = $false; prerelease = $false
                    created_at = '2026-01-01T00:00:00Z'; published_at = '2026-01-01T00:00:00Z'; assets = @()
                },
                [pscustomobject] @{
                    id = 2; tag_name = 'v1.1.0-rc.1'; name = '1.1 RC'; body = 'candidate'; draft = $false; prerelease = $true
                    created_at = '2026-02-01T00:00:00Z'; published_at = '2026-02-01T00:00:00Z'; assets = @()
                },
                [pscustomobject] @{
                    id = 3; tag_name = 'v1.1.0'; name = '1.1.0'; body = 'stable two'; draft = $false; prerelease = $false
                    created_at = '2026-03-01T00:00:00Z'; published_at = '2026-03-01T00:00:00Z'
                    assets = @([pscustomobject] @{ id = 31; name = 'module.zip'; label = ''; size = 42; content_type = 'application/zip'; digest = 'sha256:abc' })
                },
                [pscustomobject] @{
                    id = 4; tag_name = 'v2.0.0'; name = '2.0 draft'; body = 'draft'; draft = $true; prerelease = $false
                    created_at = '2026-04-01T00:00:00Z'; published_at = $null; assets = @()
                }
            )

            Mock Invoke-CgrNativeCommand {
                if ($ArgumentList -contains '--paginate') {
                    $json = @($script:releasePayload) | ConvertTo-Json -Depth 20 -Compress
                    return [pscustomobject] @{ ExitCode = 0; Output = @("[$json]"); ErrorText = '' }
                }

                $path = @($ArgumentList | Where-Object { $_ -like 'repos/*/commits/*' }) | Select-Object -First 1
                $tag = [uri]::UnescapeDataString(($path -split '/commits/', 2)[1])
                return [pscustomobject] @{ ExitCode = 0; Output = @("sha-$tag"); ErrorText = '' }
            }
        }
    }

    It 'selects all stable non-draft releases by default' {
        InModuleScope CopyGitHubRepo {
            $repository = [pscustomobject] @{ FullName = 'acme/widget' }
            $result = Get-CgrGitHubReleaseSelection -Repository $repository

            $result.AvailableReleaseCount | Should -Be 4
            $result.SelectedReleaseCount | Should -Be 2
            @($result.Releases.TagName) | Should -Be @('v1.1.0', 'v1.0.0')
            $result.SelectedAssetCount | Should -Be 1
        }
    }

    It 'supports wildcard include and exclude filters' {
        InModuleScope CopyGitHubRepo {
            $repository = [pscustomobject] @{ FullName = 'acme/widget' }
            $result = Get-CgrGitHubReleaseSelection `
                -Repository $repository `
                -ReleaseTag 'v1.*' `
                -ReleaseExcludeTag '*1.0.0'

            @($result.Releases.TagName) | Should -Be @('v1.1.0')
        }
    }

    It 'can include prereleases and drafts explicitly' {
        InModuleScope CopyGitHubRepo {
            $repository = [pscustomobject] @{ FullName = 'acme/widget' }
            $result = Get-CgrGitHubReleaseSelection `
                -Repository $repository `
                -IncludePrerelease `
                -IncludeDraftReleases

            $result.SelectedReleaseCount | Should -Be 4
            @($result.Releases.TagName) | Should -Contain 'v1.1.0-rc.1'
            @($result.Releases.TagName) | Should -Contain 'v2.0.0'
        }
    }

    It 'applies ReleaseCount after filtering and newest-first ordering' {
        InModuleScope CopyGitHubRepo {
            $repository = [pscustomobject] @{ FullName = 'acme/widget' }
            $result = Get-CgrGitHubReleaseSelection `
                -Repository $repository `
                -ReleaseTag 'v1.*' `
                -IncludePrerelease `
                -ReleaseCount 2

            @($result.Releases.TagName) | Should -Be @('v1.1.0', 'v1.1.0-rc.1')
        }
    }

    It 'captures immutable tag target and asset evidence for selected releases' {
        InModuleScope CopyGitHubRepo {
            $repository = [pscustomobject] @{ FullName = 'acme/widget' }
            $result = Get-CgrGitHubReleaseSelection -Repository $repository -ReleaseTag 'v1.1.0'

            $result.Releases[0].TargetCommitSha | Should -Be 'sha-v1.1.0'
            $result.Releases[0].Assets[0].Name | Should -Be 'module.zip'
            $result.Releases[0].Assets[0].Digest | Should -Be 'sha256:abc'
        }
    }

    It 'fails closed when a selected release tag cannot resolve to a commit' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrNativeCommand {
                if ($ArgumentList -contains '--paginate') {
                    $json = @($script:releasePayload) | ConvertTo-Json -Depth 20 -Compress
                    return [pscustomobject] @{ ExitCode = 0; Output = @("[$json]"); ErrorText = '' }
                }
                return [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = 'not found' }
            }

            $repository = [pscustomobject] @{ FullName = 'acme/widget' }
            { Get-CgrGitHubReleaseSelection -Repository $repository -ReleaseTag 'v1.1.0' } |
                Should -Throw -ErrorId 'SourceGitHubReleaseTagResolutionFailed,Get-CgrGitHubReleaseSelection'
        }
    }
}
