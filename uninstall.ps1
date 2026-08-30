#requires -Version 7.4

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Version')]
    [Alias('Version')]
    [string] $CgrUninstallVersion,

    [Parameter(Mandatory, ParameterSetName = 'AllVersions')]
    [Alias('AllVersions')]
    [switch] $CgrUninstallAllVersions,

    [Parameter(ParameterSetName = 'Interactive')]
    [Parameter(ParameterSetName = 'Version')]
    [Parameter(ParameterSetName = 'AllVersions')]
    [Alias('DestinationRoot')]
    [string] $CgrUninstallDestinationRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:moduleName = 'CopyGitHubRepo'
$script:moduleGuid = 'c428210d-c7a4-49db-81d1-830606e16fa6'

function ConvertTo-CgrApplicationErrorRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Message,
        [Parameter(Mandatory)] [string] $ErrorId,
        [object] $TargetObject
    )

    $exception = [System.InvalidOperationException]::new($Message)
    $exception.Data['CopyGitHubRepo.ApplicationError'] = $true
    $exception.Data['CopyGitHubRepo.ErrorId'] = $ErrorId
    return [System.Management.Automation.ErrorRecord]::new(
        $exception,
        $ErrorId,
        [System.Management.Automation.ErrorCategory]::InvalidOperation,
        $TargetObject
    )
}

function Get-CgrDefaultModuleDestinationRoot {
    [CmdletBinding()]
    param()

    if ($IsWindows) {
        $documentsPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
        if ([string]::IsNullOrWhiteSpace($documentsPath)) {
            $documentsPath = Join-Path $HOME 'Documents'
        }
        return Join-Path $documentsPath 'PowerShell/Modules'
    }
    return Join-Path $HOME '.local/share/powershell/Modules'
}

function Test-CgrPathWithinRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RootPath,
        [Parameter(Mandatory)] [string] $CandidatePath
    )

    $root = [System.IO.Path]::GetFullPath($RootPath).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $candidate = [System.IO.Path]::GetFullPath($CandidatePath)
    $comparison = if ($IsWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }
    if ($candidate.Equals($root, $comparison)) {
        return $false
    }
    $prefix = "$root$([System.IO.Path]::DirectorySeparatorChar)"
    return $candidate.StartsWith($prefix, $comparison)
}

function Assert-CgrNotFileSystemLink {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Description
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $item = Get-Item -LiteralPath $Path -Force
    $hasLinkType = -not [string]::IsNullOrWhiteSpace([string] $item.LinkType)
    $hasLinkTarget = @($item.Target).Count -gt 0 -and
    -not [string]::IsNullOrWhiteSpace((@($item.Target) -join ''))

    if ($hasLinkType -or $hasLinkTarget) {
        throw (ConvertTo-CgrApplicationErrorRecord `
                -Message "$Description '$Path' is a symbolic link or junction and will not be removed." `
                -ErrorId 'CopyGitHubRepo.UnsafeUninstallPath' `
                -TargetObject $Path)
    }
}

function Get-CgrInstalledModuleVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $ModuleRoot)

    if (-not (Test-Path -LiteralPath $ModuleRoot -PathType Container)) {
        return @()
    }
    Assert-CgrNotFileSystemLink -Path $ModuleRoot -Description 'CopyGitHubRepo module root'

    $installations = [System.Collections.Generic.List[object]]::new()
    foreach ($directory in @(Get-ChildItem -LiteralPath $ModuleRoot -Directory -Force)) {
        Assert-CgrNotFileSystemLink -Path $directory.FullName -Description 'Installation candidate'

        $parsedVersion = $null
        if (-not [version]::TryParse($directory.Name, [ref] $parsedVersion)) {
            throw (ConvertTo-CgrApplicationErrorRecord `
                    -Message "Unexpected directory '$($directory.FullName)' exists under the CopyGitHubRepo module root. No files were removed." `
                    -ErrorId 'CopyGitHubRepo.UnsafeInstallationLayout' `
                    -TargetObject $directory.FullName)
        }

        $manifestPath = Join-Path $directory.FullName 'CopyGitHubRepo.psd1'
        $rootModulePath = Join-Path $directory.FullName 'CopyGitHubRepo.psm1'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or
            -not (Test-Path -LiteralPath $rootModulePath -PathType Leaf)) {
            throw (ConvertTo-CgrApplicationErrorRecord `
                    -Message "Directory '$($directory.FullName)' does not contain a complete CopyGitHubRepo installation. No files were removed." `
                    -ErrorId 'CopyGitHubRepo.InvalidInstalledModule' `
                    -TargetObject $directory.FullName)
        }

        Assert-CgrNotFileSystemLink -Path $manifestPath -Description 'Installed module manifest'
        Assert-CgrNotFileSystemLink -Path $rootModulePath -Description 'Installed root module'
        $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
        $manifestVersion = [string] $manifest.ModuleVersion
        $manifestGuid = [string] $manifest.GUID
        $rootModule = [string] $manifest.RootModule
        if ($manifestVersion -ne $directory.Name -or
            $manifestGuid -ne $script:moduleGuid -or
            $rootModule -ne 'CopyGitHubRepo.psm1') {
            throw (ConvertTo-CgrApplicationErrorRecord `
                    -Message "Directory '$($directory.FullName)' does not match the expected CopyGitHubRepo module identity/version. No files were removed." `
                    -ErrorId 'CopyGitHubRepo.InvalidInstalledModule' `
                    -TargetObject $directory.FullName)
        }

        $installations.Add([pscustomobject] @{
                Version = $manifestVersion
                VersionObject = $parsedVersion
                Path = [System.IO.Path]::GetFullPath($directory.FullName)
                ManifestPath = [System.IO.Path]::GetFullPath($manifestPath)
            })
    }
    return @($installations | Sort-Object -Property VersionObject)
}

function Write-CgrInstalledVersionList {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object[]] $Installations)

    Write-Information 'Installed versions:' -InformationAction Continue
    for ($index = 0; $index -lt $Installations.Count; $index++) {
        Write-Information "  $($index + 1). $($Installations[$index].Version)" -InformationAction Continue
    }
}

function Read-CgrMenuChoice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Prompt,
        [Parameter(Mandatory)] [string[]] $Options,
        [Parameter(Mandatory)] [ValidateRange(1, 100)] [int] $DefaultChoice,
        [Parameter(Mandatory)] [string] $HelpText
    )

    while ($true) {
        for ($index = 0; $index -lt $Options.Count; $index++) {
            $defaultSuffix = if (($index + 1) -eq $DefaultChoice) { ' (default)' } else { '' }
            Write-Information "  $($index + 1). $($Options[$index])$defaultSuffix" -InformationAction Continue
        }
        Write-Information '  H. Help' -InformationAction Continue
        $response = (Read-Host "$Prompt ($DefaultChoice)").Trim()
        if ([string]::IsNullOrWhiteSpace($response)) {
            return $DefaultChoice
        }
        if ($response -in @('h', 'H', '?')) {
            Write-Information $HelpText -InformationAction Continue
            continue
        }
        $choice = 0
        if ([int]::TryParse($response, [ref] $choice) -and
            $choice -ge 1 -and
            $choice -le $Options.Count) {
            return $choice
        }
        Write-Warning "Enter a number from 1 to $($Options.Count), H for help, or press Enter for the default."
    }
}

function Read-CgrDestructiveConfirmation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Prompt,
        [Parameter(Mandatory)] [string] $HelpText
    )

    while ($true) {
        $response = (Read-Host "$Prompt (y/N)").Trim()
        if ([string]::IsNullOrWhiteSpace($response) -or $response -in @('n', 'N', 'no', 'No', 'NO')) {
            return $false
        }
        if ($response -in @('y', 'Y', 'yes', 'Yes', 'YES')) {
            return $true
        }
        if ($response -in @('h', 'H', '?')) {
            Write-Information $HelpText -InformationAction Continue
            continue
        }
        Write-Warning 'Enter Y to continue, N to cancel, or H for help.'
    }
}

function Get-CgrUninstallationResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ResolvedDestinationRoot,
        [Parameter(Mandatory)] [string] $ModuleRoot,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Discovered,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Targets,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $RemovedPaths,
        [bool] $WasCancelled,
        [bool] $WasChanged
    )

    return [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.UninstallationResult'
        DestinationRoot = $ResolvedDestinationRoot
        ModuleRoot = $ModuleRoot
        DiscoveredVersions = @($Discovered | ForEach-Object { $_.Version })
        TargetedVersions = @($Targets | ForEach-Object { $_.Version })
        RemovedPaths = @($RemovedPaths)
        WasCancelled = $WasCancelled
        WasChanged = $WasChanged
        IsSuccessful = $true
    }
}

function Invoke-CgrUninstall {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Interactive')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Version')]
        [ValidatePattern('^\d+\.\d+\.\d+(?:\.\d+)?$')]
        [string] $Version,

        [Parameter(Mandatory, ParameterSetName = 'AllVersions')]
        [switch] $AllVersions,

        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'Version')]
        [Parameter(ParameterSetName = 'AllVersions')]
        [string] $DestinationRoot
    )

    if ([string]::IsNullOrWhiteSpace($DestinationRoot)) {
        $DestinationRoot = Get-CgrDefaultModuleDestinationRoot
    }
    $resolvedDestinationRoot = [System.IO.Path]::GetFullPath($DestinationRoot)
    $moduleRoot = [System.IO.Path]::GetFullPath((Join-Path $resolvedDestinationRoot $script:moduleName))
    Assert-CgrNotFileSystemLink -Path $resolvedDestinationRoot -Description 'Module destination root'
    if (-not (Test-CgrPathWithinRoot -RootPath $resolvedDestinationRoot -CandidatePath $moduleRoot)) {
        throw (ConvertTo-CgrApplicationErrorRecord `
                -Message "Resolved CopyGitHubRepo module root '$moduleRoot' is outside destination root '$resolvedDestinationRoot'." `
                -ErrorId 'CopyGitHubRepo.UnsafeUninstallPath' `
                -TargetObject $moduleRoot)
    }

    $installations = @(Get-CgrInstalledModuleVersion -ModuleRoot $moduleRoot)
    if ($installations.Count -eq 0) {
        Write-Information "CopyGitHubRepo is not installed under '$resolvedDestinationRoot'. No changes were made." -InformationAction Continue
        return Get-CgrUninstallationResult -ResolvedDestinationRoot $resolvedDestinationRoot -ModuleRoot $moduleRoot -Discovered @() -Targets @() -RemovedPaths @() -WasCancelled $false -WasChanged $false
    }

    $targets = @()
    $interactive = $PSCmdlet.ParameterSetName -eq 'Interactive'
    if ($PSCmdlet.ParameterSetName -eq 'Version') {
        $targets = @($installations | Where-Object { $_.Version -eq $Version })
        if ($targets.Count -eq 0) {
            Write-Information "CopyGitHubRepo $Version is not installed under '$resolvedDestinationRoot'. No changes were made." -InformationAction Continue
            return Get-CgrUninstallationResult -ResolvedDestinationRoot $resolvedDestinationRoot -ModuleRoot $moduleRoot -Discovered $installations -Targets @() -RemovedPaths @() -WasCancelled $false -WasChanged $false
        }
    }
    elseif ($AllVersions) {
        $targets = $installations
    }
    else {
        Write-Information 'CopyGitHubRepo uninstall' -InformationAction Continue
        Write-Information '' -InformationAction Continue
        if ($installations.Count -eq 1) {
            $targets = @($installations[0])
        }
        else {
            Write-CgrInstalledVersionList -Installations $installations
            Write-Information '' -InformationAction Continue
            Write-Information 'What would you like to remove?' -InformationAction Continue
            Write-Information '' -InformationAction Continue
            $actionChoice = Read-CgrMenuChoice -Prompt 'Selection' -Options @('Remove one version', 'Remove all versions', 'Cancel') -DefaultChoice 3 -HelpText 'Remove one version keeps the other installed versions. Remove all versions deletes every validated CopyGitHubRepo version under this module root. Cancel makes no changes.'
            if ($actionChoice -eq 3) {
                Write-Information 'Uninstall cancelled. No changes were made.' -InformationAction Continue
                return Get-CgrUninstallationResult -ResolvedDestinationRoot $resolvedDestinationRoot -ModuleRoot $moduleRoot -Discovered $installations -Targets @() -RemovedPaths @() -WasCancelled $true -WasChanged $false
            }
            if ($actionChoice -eq 2) {
                $targets = $installations
            }
            else {
                Write-Information '' -InformationAction Continue
                $versionOptions = @($installations | ForEach-Object { $_.Version }) + @('Cancel')
                $versionChoice = Read-CgrMenuChoice -Prompt 'Selection' -Options $versionOptions -DefaultChoice $versionOptions.Count -HelpText 'Choose the single CopyGitHubRepo version to remove. Other installed versions will remain unchanged.'
                if ($versionChoice -eq $versionOptions.Count) {
                    Write-Information 'Uninstall cancelled. No changes were made.' -InformationAction Continue
                    return Get-CgrUninstallationResult -ResolvedDestinationRoot $resolvedDestinationRoot -ModuleRoot $moduleRoot -Discovered $installations -Targets @() -RemovedPaths @() -WasCancelled $true -WasChanged $false
                }
                $targets = @($installations[$versionChoice - 1])
            }
        }
    }

    foreach ($target in $targets) {
        if (-not (Test-CgrPathWithinRoot -RootPath $moduleRoot -CandidatePath $target.Path)) {
            throw (ConvertTo-CgrApplicationErrorRecord -Message "Uninstall target '$($target.Path)' is outside the validated CopyGitHubRepo module root '$moduleRoot'." -ErrorId 'CopyGitHubRepo.UnsafeUninstallPath' -TargetObject $target.Path)
        }
        Assert-CgrNotFileSystemLink -Path $target.Path -Description 'Uninstall target'
    }

    if ($interactive) {
        Write-Information '' -InformationAction Continue
        Write-Information 'The following installation files will be removed:' -InformationAction Continue
        foreach ($target in $targets) {
            Write-Information "  Version: $($target.Version)" -InformationAction Continue
            Write-Information "  Path: $($target.Path)" -InformationAction Continue
        }
        Write-Information '' -InformationAction Continue
        $confirmed = Read-CgrDestructiveConfirmation -Prompt 'Proceed?' -HelpText 'This permanently removes the listed local module installation directories. It does not change any GitHub repositories or migration recovery files.'
        if (-not $confirmed) {
            Write-Information 'Uninstall cancelled. No changes were made.' -InformationAction Continue
            return Get-CgrUninstallationResult -ResolvedDestinationRoot $resolvedDestinationRoot -ModuleRoot $moduleRoot -Discovered $installations -Targets $targets -RemovedPaths @() -WasCancelled $true -WasChanged $false
        }
    }

    $targetDescription = ($targets | ForEach-Object { "$($_.Version): $($_.Path)" }) -join '; '
    $operation = if ($targets.Count -eq 1) { "Uninstall CopyGitHubRepo $($targets[0].Version)" } else { 'Uninstall all validated CopyGitHubRepo versions' }
    if (-not $PSCmdlet.ShouldProcess($targetDescription, $operation)) {
        return Get-CgrUninstallationResult -ResolvedDestinationRoot $resolvedDestinationRoot -ModuleRoot $moduleRoot -Discovered $installations -Targets $targets -RemovedPaths @() -WasCancelled $false -WasChanged $false
    }

    $removedPaths = [System.Collections.Generic.List[string]]::new()
    foreach ($target in $targets) {
        foreach ($loadedModule in @(Get-Module -Name $script:moduleName -All)) {
            if ([string]::IsNullOrWhiteSpace($loadedModule.ModuleBase)) {
                continue
            }
            $loadedModuleBase = [System.IO.Path]::GetFullPath($loadedModule.ModuleBase)
            $comparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
            if ($loadedModuleBase.Equals($target.Path, $comparison)) {
                Remove-Module -ModuleInfo $loadedModule -Force -ErrorAction Stop
            }
        }
        Remove-Item -LiteralPath $target.Path -Recurse -Force
        $removedPaths.Add($target.Path)
    }

    if (Test-Path -LiteralPath $moduleRoot -PathType Container) {
        Assert-CgrNotFileSystemLink -Path $moduleRoot -Description 'CopyGitHubRepo module root'
        if (@(Get-ChildItem -LiteralPath $moduleRoot -Force).Count -eq 0) {
            Remove-Item -LiteralPath $moduleRoot -Force
        }
    }

    Write-Information "Removed $($removedPaths.Count) CopyGitHubRepo installation version(s)." -InformationAction Continue
    Get-CgrUninstallationResult -ResolvedDestinationRoot $resolvedDestinationRoot -ModuleRoot $moduleRoot -Discovered $installations -Targets $targets -RemovedPaths @($removedPaths) -WasCancelled $false -WasChanged ($removedPaths.Count -gt 0)
}

$cgrInvocationParameters = @{}
if ($PSBoundParameters.ContainsKey('CgrUninstallVersion')) {
    $cgrInvocationParameters.Version = $CgrUninstallVersion
}
if ($PSBoundParameters.ContainsKey('CgrUninstallAllVersions')) {
    $cgrInvocationParameters.AllVersions = $CgrUninstallAllVersions
}
if ($PSBoundParameters.ContainsKey('CgrUninstallDestinationRoot')) {
    $cgrInvocationParameters.DestinationRoot = $CgrUninstallDestinationRoot
}
if ($PSBoundParameters.ContainsKey('WhatIf')) {
    $cgrInvocationParameters.WhatIf = [bool] $PSBoundParameters.WhatIf
}
if ($PSBoundParameters.ContainsKey('Confirm')) {
    $cgrInvocationParameters.Confirm = [bool] $PSBoundParameters.Confirm
}

Invoke-CgrUninstall @cgrInvocationParameters
