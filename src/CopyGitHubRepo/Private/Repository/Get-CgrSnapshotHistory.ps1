function Get-CgrSnapshotHistory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Repository,

        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com',

        [ValidateRange(1, 100)]
        [int] $DisplayLimit = 10
    )

    $repositoryName = ConvertTo-CgrRepositoryName -Repository $Repository.FullName
    $encodedRepositoryName = $repositoryName.Split('/') | ForEach-Object { [uri]::EscapeDataString($_) }
    $repositoryPath = $encodedRepositoryName -join '/'

    $tags = @(Get-CgrGitHubApi -Path "/repos/$repositoryPath/tags?per_page=100" -HostName $HostName -Paginate)
    $releases = @(Get-CgrGitHubApi -Path "/repos/$repositoryPath/releases?per_page=100" -HostName $HostName -Paginate)

    $tagNames = @(
        $tags |
            ForEach-Object { [string] (Get-CgrObjectProperty -InputObject $_ -Name 'name') } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    $releaseRecords = @(
        $releases | ForEach-Object {
            [pscustomobject] @{
                TagName = [string] (Get-CgrObjectProperty -InputObject $_ -Name 'tag_name')
                Name = [string] (Get-CgrObjectProperty -InputObject $_ -Name 'name')
                Draft = [bool] (Get-CgrObjectProperty -InputObject $_ -Name 'draft')
                Prerelease = [bool] (Get-CgrObjectProperty -InputObject $_ -Name 'prerelease')
            }
        }
    )

    $versionLikePattern = '^(?:v)?\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$'
    $versionLikeTags = @($tagNames | Where-Object { $_ -match $versionLikePattern })

    [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.SnapshotHistoricalRecords'
        SchemaVersion = 1
        TagCount = $tagNames.Count
        TagCountMayBeTruncated = $false
        TagNames = @($tagNames | Select-Object -First $DisplayLimit)
        VersionLikeTagNames = @($versionLikeTags | Select-Object -First $DisplayLimit)
        ReleaseCount = $releaseRecords.Count
        ReleaseCountMayBeTruncated = $false
        Releases = @($releaseRecords | Select-Object -First $DisplayLimit)
        TagsAreCopied = $false
        ReleasesAreCopied = $false
    }
}
