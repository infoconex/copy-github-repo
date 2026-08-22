function Get-CgrRepository {
    [CmdletBinding()]
    param(
        [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
        [string] $Repository,

        [string] $Owner,

        [string] $Name,

        [ValidateSet('public', 'private', 'internal')]
        [string] $Visibility,

        [Nullable[bool]] $Archived,

        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com'
    )

    if ($Repository) {
        $normalizedRepository = ConvertTo-CgrRepositoryName -Repository $Repository
        $path = "repos/$normalizedRepository"
        return Get-CgrGitHubApi -Path $path -HostName $HostName |
            ConvertTo-CgrRepository -HostName $HostName
    }

    $path = 'user/repos?per_page=100&affiliation=owner,collaborator,organization_member&sort=updated'
    $repositories = Get-CgrGitHubApi -Path $path -HostName $HostName -Paginate |
        ConvertTo-CgrRepository -HostName $HostName

    if ($Owner) {
        $repositories = $repositories | Where-Object { $_.Owner -eq $Owner }
    }

    if ($Name) {
        $namePattern = "*$Name*"
        $repositories = $repositories | Where-Object { $_.Name -like $namePattern -or $_.FullName -like $namePattern }
    }

    if ($Visibility) {
        $repositories = $repositories | Where-Object { $_.Visibility -eq $Visibility }
    }

    if ($PSBoundParameters.ContainsKey('Archived')) {
        $repositories = $repositories | Where-Object { $_.IsArchived -eq $Archived }
    }

    return @($repositories)
}
