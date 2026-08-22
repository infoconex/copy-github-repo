function Resolve-CgrNativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    $command = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($null -eq $command) {
        return [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.NativeCommandStatus'
            Name = $Name
            Found = $false
            Path = $null
            Version = $null
        }
    }

    $version = $null
    $versionResult = Invoke-CgrNativeCommand -FilePath $Name -ArgumentList @('--version')
    if ($versionResult.ExitCode -eq 0 -and @($versionResult.Output).Count -gt 0) {
        $version = [string] @($versionResult.Output)[0]
    }

    [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.NativeCommandStatus'
        Name = $Name
        Found = $true
        Path = $command.Source
        Version = $version
    }
}
