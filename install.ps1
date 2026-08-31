#requires -Version 7.4

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string] $SourcePath,

    [string] $DestinationRoot,

    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-CgrApplicationErrorRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Message,

        [Parameter(Mandatory)]
        [string] $ErrorId,

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

if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    $developmentSourcePath = Join-Path $PSScriptRoot 'src/CopyGitHubRepo'
    $developmentManifestPath = Join-Path $developmentSourcePath 'CopyGitHubRepo.psd1'

    if (Test-Path -LiteralPath $developmentManifestPath -PathType Leaf) {
        $SourcePath = $developmentSourcePath
    }
    else {
        $packagedModuleRoot = Join-Path $PSScriptRoot 'CopyGitHubRepo'
        $manifestCandidates = @(
            Get-ChildItem -LiteralPath $packagedModuleRoot -Filter 'CopyGitHubRepo.psd1' -File -Recurse -ErrorAction SilentlyContinue
        )

        if ($manifestCandidates.Count -ne 1) {
            throw (ConvertTo-CgrApplicationErrorRecord `
                    -Message "Unable to resolve exactly one packaged CopyGitHubRepo module under '$packagedModuleRoot'." `
                    -ErrorId 'CopyGitHubRepo.PackagedModuleNotFound' `
                    -TargetObject $packagedModuleRoot)
        }

        $SourcePath = $manifestCandidates[0].Directory.FullName
    }
}

$SourcePath = [System.IO.Path]::GetFullPath($SourcePath)
$sourceManifestPath = Join-Path $SourcePath 'CopyGitHubRepo.psd1'
if (-not (Test-Path -LiteralPath $sourceManifestPath -PathType Leaf)) {
    throw (ConvertTo-CgrApplicationErrorRecord `
            -Message "CopyGitHubRepo module manifest was not found at '$sourceManifestPath'." `
            -ErrorId 'CopyGitHubRepo.ManifestNotFound' `
            -TargetObject $sourceManifestPath)
}

$sourceModule = Test-ModuleManifest -Path $sourceManifestPath -ErrorAction Stop
$version = $sourceModule.Version.ToString()

if ([string]::IsNullOrWhiteSpace($DestinationRoot)) {
    if ($IsWindows) {
        $documentsPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
        if ([string]::IsNullOrWhiteSpace($documentsPath)) {
            $documentsPath = Join-Path $HOME 'Documents'
        }
        $DestinationRoot = Join-Path $documentsPath 'PowerShell/Modules'
    }
    else {
        $DestinationRoot = Join-Path $HOME '.local/share/powershell/Modules'
    }
}

$DestinationRoot = [System.IO.Path]::GetFullPath($DestinationRoot)
$moduleRoot = Join-Path $DestinationRoot 'CopyGitHubRepo'
$destinationPath = Join-Path $moduleRoot $version
$destinationExists = Test-Path -LiteralPath $destinationPath

if ($destinationExists -and -not $Force) {
    throw (ConvertTo-CgrApplicationErrorRecord `
            -Message "CopyGitHubRepo $version is already installed at '$destinationPath'. Use -Force to replace that version." `
            -ErrorId 'CopyGitHubRepo.VersionAlreadyInstalled' `
            -TargetObject $destinationPath)
}

$operation = if ($destinationExists) {
    "Replace CopyGitHubRepo $version"
}
else {
    "Install CopyGitHubRepo $version"
}

if (-not $PSCmdlet.ShouldProcess($destinationPath, $operation)) {
    return
}

if ($destinationExists) {
    Remove-Item -LiteralPath $destinationPath -Recurse -Force
}

New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
Get-ChildItem -LiteralPath $SourcePath -Force |
    Copy-Item -Destination $destinationPath -Recurse -Force

$installedManifestPath = Join-Path $destinationPath 'CopyGitHubRepo.psd1'
$installedModule = Test-ModuleManifest -Path $installedManifestPath -ErrorAction Stop
if ($installedModule.Version.ToString() -ne $version) {
    throw (ConvertTo-CgrApplicationErrorRecord `
            -Message "Installed module version '$($installedModule.Version)' does not match source version '$version'." `
            -ErrorId 'CopyGitHubRepo.InstalledVersionMismatch' `
            -TargetObject $installedManifestPath)
}

[pscustomobject] @{
    PSTypeName = 'CopyGitHubRepo.InstallationResult'
    Version = $version
    SourcePath = $SourcePath
    DestinationPath = $destinationPath
    ManifestPath = $installedManifestPath
    ReplacedExistingVersion = $destinationExists
    IsSuccessful = $true
}
