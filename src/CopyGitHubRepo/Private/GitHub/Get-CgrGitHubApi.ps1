function Get-CgrGitHubApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com',

        [switch] $Paginate
    )

    $arguments = @('api', '--hostname', $HostName)
    if ($Paginate) {
        $arguments += @('--paginate', '--slurp')
    }

    $arguments += $Path

    $result = Invoke-CgrGitHubApiReadRequest -ArgumentList $arguments
    $response = & $script:ResolveCgrGitHubApiReadResponse -Result $result -Path $Path
    if ($response.Status -eq 'Error') {
        $PSCmdlet.ThrowTerminatingError($response.ErrorRecord)
    }

    if ($response.Status -eq 'Empty') {
        return @()
    }

    $data = $response.Data
    if (-not $Paginate) {
        return $data
    }

    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($page in @($data)) {
        foreach ($item in @($page)) {
            $items.Add($item)
        }
    }

    return $items.ToArray()
}
