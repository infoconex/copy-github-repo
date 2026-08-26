#requires -Version 7.4

<#
.SYNOPSIS
Builds and validates the PowerShell Gallery module payload.

.DESCRIPTION
Copies only the module source into a clean package directory, injects version-specific
Gallery release notes from CHANGELOG.md, validates manifest and export contracts,
imports the package in-process and in an isolated PowerShell process, and verifies that
every exported public command retains complete native comment-based help. The script
fails before publication when package contents, exports, formatting data, importability,
release metadata, or public help drift from the release contract.

.PARAMETER OutputDirectory
Directory that receives the CopyGitHubRepo package. Defaults to dist/PSGallery under
the repository root.
#>
[CmdletBinding()]
param(
    [string] $OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$moduleSourcePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo'
$releaseNotesScriptPath = Join-Path $PSScriptRoot 'Set-PowerShellGalleryReleaseNotes.ps1'
$changelogPath = Join-Path $repositoryRoot 'CHANGELOG.md'

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repositoryRoot 'dist/PSGallery'
}

$packagePath = Join-Path $OutputDirectory 'CopyGitHubRepo'
$manifestPath = Join-Path $packagePath 'CopyGitHubRepo.psd1'

if (Test-Path -LiteralPath $packagePath) {
    Remove-Item -LiteralPath $packagePath -Recurse -Force
}

New-Item -Path $packagePath -ItemType Directory -Force | Out-Null
Copy-Item -Path (Join-Path $moduleSourcePath '*') -Destination $packagePath -Recurse -Force

& $releaseNotesScriptPath -ManifestPath $manifestPath -ChangelogPath $changelogPath | Out-Null

$manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
$manifestData = Import-PowerShellDataFile -Path $manifestPath
$version = [string] $manifest.Version
if ([string]::IsNullOrWhiteSpace($version)) {
    throw "Packaged module manifest '$manifestPath' does not define a version."
}

$unexpectedNames = @('.github', 'build', 'docs', 'tests')
foreach ($unexpectedName in $unexpectedNames) {
    $unexpectedPath = Join-Path $packagePath $unexpectedName
    if (Test-Path -LiteralPath $unexpectedPath) {
        throw "PowerShell Gallery package contains unintended development content '$unexpectedName'."
    }
}

$expectedCommands = @(
    'Copy-GitHubRepository'
    'Get-GitHubRepository'
    'Start-CopyGitHubRepositoryWizard'
    'Test-GitHubRepositoryMigration'
) | Sort-Object

$manifestFunctions = @($manifestData.FunctionsToExport | Sort-Object)
if (($manifestFunctions -join "`n") -ne ($expectedCommands -join "`n")) {
    throw "Packaged manifest exports '$($manifestFunctions -join ', ')' but expected '$($expectedCommands -join ', ')'."
}

if (@($manifestData.CmdletsToExport).Count -ne 0) {
    throw 'PowerShell Gallery package must not export cmdlets.'
}
if (@($manifestData.AliasesToExport).Count -ne 0) {
    throw 'PowerShell Gallery package must not export aliases.'
}
if (@($manifestData.VariablesToExport).Count -ne 0) {
    throw 'PowerShell Gallery package must not export variables.'
}

foreach ($formatFile in @($manifestData.FormatsToProcess)) {
    $formatPath = Join-Path $packagePath $formatFile
    if (-not (Test-Path -LiteralPath $formatPath -PathType Leaf)) {
        throw "PowerShell Gallery package is missing required format file '$formatFile'."
    }
}

$importedModule = $null
$actualCommands = @()
try {
    $importedModule = Import-Module -Name $manifestPath -Force -PassThru -Scope Local -ErrorAction Stop
    $actualCommands = @($importedModule.ExportedFunctions.Keys | Sort-Object)
    if (($actualCommands -join "`n") -ne ($expectedCommands -join "`n")) {
        throw "Packaged module exports '$($actualCommands -join ', ')' but expected '$($expectedCommands -join ', ')'."
    }
    if (@($importedModule.ExportedAliases.Keys).Count -ne 0) {
        throw 'Imported PowerShell Gallery package unexpectedly exports aliases.'
    }
    if (@($importedModule.ExportedVariables.Keys).Count -ne 0) {
        throw 'Imported PowerShell Gallery package unexpectedly exports variables.'
    }

    foreach ($commandName in $actualCommands) {
        $help = Get-Help -Name $commandName -Full -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace([string] $help.Synopsis) -or
            [string]::IsNullOrWhiteSpace([string] ($help.Description.Text -join ' ')) -or
            @($help.Examples.Example).Count -lt 2 -or
            @($help.RelatedLinks.NavigationLink).Count -lt 1 -or
            [string]::IsNullOrWhiteSpace([string] $help.InputTypes.InputType.Type.Name) -or
            [string]::IsNullOrWhiteSpace([string] $help.ReturnValues.ReturnValue.Type.Name)) {
            throw "Packaged public command '$commandName' does not expose complete native PowerShell help."
        }
    }
}
finally {
    if ($null -ne $importedModule) {
        Remove-Module -ModuleInfo $importedModule -Force -ErrorAction SilentlyContinue
    }
}

$smokeScriptPath = Join-Path $OutputDirectory 'Test-CopyGitHubRepoPackageImport.ps1'
$smokeScript = @'
param(
    [Parameter(Mandatory)]
    [string] $ManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expectedCommands = @(
    'Copy-GitHubRepository'
    'Get-GitHubRepository'
    'Start-CopyGitHubRepositoryWizard'
    'Test-GitHubRepositoryMigration'
) | Sort-Object

$module = Import-Module -Name $ManifestPath -Force -PassThru -ErrorAction Stop
$actualCommands = @($module.ExportedFunctions.Keys | Sort-Object)
if (($actualCommands -join "`n") -ne ($expectedCommands -join "`n")) {
    throw "Isolated package import exported '$($actualCommands -join ', ')' but expected '$($expectedCommands -join ', ')'."
}

foreach ($commandName in $expectedCommands) {
    Get-Command -Name $commandName -Module CopyGitHubRepo -ErrorAction Stop | Out-Null
    $help = Get-Help -Name $commandName -Full -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace([string] $help.Synopsis) -or
        [string]::IsNullOrWhiteSpace([string] ($help.Description.Text -join ' ')) -or
        @($help.Examples.Example).Count -lt 2 -or
        @($help.RelatedLinks.NavigationLink).Count -lt 1 -or
        [string]::IsNullOrWhiteSpace([string] $help.InputTypes.InputType.Type.Name) -or
        [string]::IsNullOrWhiteSpace([string] $help.ReturnValues.ReturnValue.Type.Name)) {
        throw "Isolated package command '$commandName' does not expose complete native PowerShell help."
    }
}
'@

Set-Content -LiteralPath $smokeScriptPath -Value $smokeScript -Encoding utf8NoBOM
try {
    $pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
    & $pwshPath -NoLogo -NoProfile -NonInteractive -File $smokeScriptPath -ManifestPath $manifestPath
    if ($LASTEXITCODE -ne 0) {
        throw "Isolated PowerShell Gallery package import failed with exit code $LASTEXITCODE."
    }
}
finally {
    Remove-Item -LiteralPath $smokeScriptPath -Force -ErrorAction SilentlyContinue
}

[pscustomobject] @{
    PSTypeName = 'CopyGitHubRepo.PowerShellGalleryPackage'
    Version = $version
    PackagePath = $packagePath
    ManifestPath = $manifestPath
    ExportedFunctions = $actualCommands
    FileCount = @(Get-ChildItem -LiteralPath $packagePath -File -Recurse).Count
    IsolatedImportValidated = $true
    PublicHelpValidated = $true
}
