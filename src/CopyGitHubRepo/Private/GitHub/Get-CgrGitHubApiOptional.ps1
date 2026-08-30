function Get-CgrGitHubApiOptional {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com'
    )

    $response = Invoke-CgrGitHubApiReadRequest `
        -ArgumentList @('api', '--hostname', $HostName, $Path) `
        -Path $Path `
        -AllowNotFound

    if ($response.Status -eq 'Error') {
        $PSCmdlet.ThrowTerminatingError($response.ErrorRecord)
    }

    if ($response.Status -in @('NotFound', 'Empty')) {
        return $null
    }

    return $response.Data
}
