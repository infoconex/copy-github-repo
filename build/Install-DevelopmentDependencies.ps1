#requires -Version 7.4

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$dependencyVersions = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'DevelopmentDependencies.psd1')

foreach ($moduleName in @('Pester', 'PSScriptAnalyzer')) {
    $requiredVersion = [version] [string] $dependencyVersions[$moduleName]
    $installedModule = Get-Module -ListAvailable -Name $moduleName |
        Where-Object { $_.Version -eq $requiredVersion } |
        Select-Object -First 1

    if ($null -ne $installedModule) {
        Write-Verbose "Using $moduleName $requiredVersion from '$($installedModule.ModuleBase)'."
        continue
    }

    Install-Module `
        -Name $moduleName `
        -RequiredVersion $requiredVersion `
        -Repository PSGallery `
        -Scope CurrentUser `
        -Force
}
