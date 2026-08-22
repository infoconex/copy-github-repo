function Get-CgrPrerequisiteStatus {
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com'
    )

    $git = Resolve-CgrNativeCommand -Name 'git'
    $gh = Resolve-CgrNativeCommand -Name 'gh'
    $authentication = $null

    if ($gh.Found) {
        $authentication = Get-CgrGitHubAuthenticationStatus -HostName $HostName
    }

    [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.PrerequisiteStatus'
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        IsPowerShellSupported = $PSVersionTable.PSVersion -ge [version] '7.4'
        Git = $git
        GitHubCli = $gh
        Authentication = $authentication
        IsReadyForDiscovery = [bool] ($git.Found -and $gh.Found -and $authentication -and $authentication.Authenticated)
    }
}
