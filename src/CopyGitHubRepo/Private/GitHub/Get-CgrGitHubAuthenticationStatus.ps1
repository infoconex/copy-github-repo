function Get-CgrGitHubAuthenticationStatus {
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com'
    )

    $usesToken = -not [string]::IsNullOrWhiteSpace($env:GH_TOKEN)
    $authResult = Invoke-CgrNativeCommand `
        -FilePath 'gh' `
        -ArgumentList @('auth', 'status', '--hostname', $HostName)

    if ($authResult.ExitCode -ne 0) {
        return [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.AuthenticationStatus'
            HostName = $HostName
            Authenticated = $false
            Account = $null
            AuthenticationMethod = if ($usesToken) { 'GH_TOKEN' } else { $null }
            Message = "GitHub CLI is not authenticated for '$HostName'. Run 'gh auth login --hostname $HostName' or set GH_TOKEN for automation."
            Details = $authResult.ErrorText
        }
    }

    $account = $null
    $userResult = Invoke-CgrNativeCommand `
        -FilePath 'gh' `
        -ArgumentList @('api', '--hostname', $HostName, 'user')

    if ($userResult.ExitCode -eq 0) {
        $userJson = ($userResult.Output | Out-String).Trim()
        if (-not [string]::IsNullOrWhiteSpace($userJson)) {
            $user = $userJson | ConvertFrom-Json -Depth 20
            $account = [string] $user.login
        }
    }

    [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.AuthenticationStatus'
        HostName = $HostName
        Authenticated = $true
        Account = $account
        AuthenticationMethod = if ($usesToken) { 'GH_TOKEN' } else { 'GitHubCLI' }
        Message = if ($account) { "Authenticated to '$HostName' as '$account'." } else { "Authenticated to '$HostName'." }
        Details = $authResult.ErrorText
    }
}
