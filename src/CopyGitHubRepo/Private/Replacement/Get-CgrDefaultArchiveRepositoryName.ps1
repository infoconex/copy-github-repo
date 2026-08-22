function Get-CgrDefaultArchiveRepositoryName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
        [string] $Repository
    )

    $normalized = ConvertTo-CgrRepositoryName -Repository $Repository
    $repositoryName = $normalized.Split('/', 2)[1]
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    return '{0}-archive-{1}' -f $repositoryName, $timestamp
}
