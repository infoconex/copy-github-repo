BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Snapshot historical-record pagination' {
    It 'requests pagination for both tags and releases' {
        InModuleScope CopyGitHubRepo {
            Mock Get-CgrGitHubApi { @() }
            $repository = [pscustomobject] @{ FullName = 'acme/widget' }

            Get-CgrSnapshotHistory -Repository $repository | Out-Null

            Should -Invoke Get-CgrGitHubApi -Times 1 -ParameterFilter { $Path -like '*/tags?*' -and $Paginate }
            Should -Invoke Get-CgrGitHubApi -Times 1 -ParameterFilter { $Path -like '*/releases?*' -and $Paginate }
        }
    }

    It 'counts 101 tags and releases without marking results truncated' {
        InModuleScope CopyGitHubRepo {
            $tags = 1..101 | ForEach-Object { [pscustomobject] @{ name = "tag-$_" } }
            $tags[100].name = 'v9.9.9'
            $releases = 1..101 | ForEach-Object {
                [pscustomobject] @{ tag_name = "tag-$_"; name = "Release $_"; draft = $false; prerelease = $false }
            }
            Mock Get-CgrGitHubApi {
                if ($Path -like '*/tags?*') { return $tags }
                return $releases
            }

            $result = Get-CgrSnapshotHistory -Repository ([pscustomobject] @{ FullName = 'acme/widget' }) -DisplayLimit 100

            $result.TagCount | Should -Be 101
            $result.ReleaseCount | Should -Be 101
            $result.VersionLikeTagNames | Should -Contain 'v9.9.9'
            $result.TagCountMayBeTruncated | Should -BeFalse
            $result.ReleaseCountMayBeTruncated | Should -BeFalse
        }
    }

    It 'limits displayed records without changing aggregate counts' {
        InModuleScope CopyGitHubRepo {
            $tags = 1..101 | ForEach-Object { [pscustomobject] @{ name = "v1.0.$_" } }
            $releases = 1..101 | ForEach-Object {
                [pscustomobject] @{ tag_name = "v1.0.$_"; name = "Release $_"; draft = $false; prerelease = $false }
            }
            Mock Get-CgrGitHubApi {
                if ($Path -like '*/tags?*') { return $tags }
                return $releases
            }

            $result = Get-CgrSnapshotHistory -Repository ([pscustomobject] @{ FullName = 'acme/widget' }) -DisplayLimit 10

            $result.TagCount | Should -Be 101
            $result.ReleaseCount | Should -Be 101
            @($result.TagNames).Count | Should -Be 10
            @($result.VersionLikeTagNames).Count | Should -Be 10
            @($result.Releases).Count | Should -Be 10
        }
    }

    It 'handles zero and exactly one API page consistently' -ForEach @(
        @{ Count = 0 }
        @{ Count = 100 }
    ) {
        InModuleScope CopyGitHubRepo -Parameters @{ ExpectedCount = $_.Count } {
            param($ExpectedCount)
            $tags = if ($ExpectedCount -eq 0) { @() } else { 1..$ExpectedCount | ForEach-Object { [pscustomobject] @{ name = "tag-$_" } } }
            Mock Get-CgrGitHubApi {
                if ($Path -like '*/tags?*') { return $tags }
                return @()
            }

            $result = Get-CgrSnapshotHistory -Repository ([pscustomobject] @{ FullName = 'acme/widget' }) -DisplayLimit 10
            $result.TagCount | Should -Be $ExpectedCount
            $result.TagCountMayBeTruncated | Should -BeFalse
        }
    }
}
