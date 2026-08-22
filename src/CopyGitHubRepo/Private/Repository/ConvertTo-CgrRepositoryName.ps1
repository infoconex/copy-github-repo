function ConvertTo-CgrRepositoryName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
        [string] $Repository
    )

    $parts = $Repository.Split('/', 2)
    "$($parts[0].ToLowerInvariant())/$($parts[1])"
}
