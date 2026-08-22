#requires -Version 7.4

[CmdletBinding()]
param(
    [string] $OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$moduleSourcePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo'
$manifestPath = Join-Path $moduleSourcePath 'CopyGitHubRepo.psd1'
$installerPath = Join-Path $repositoryRoot 'install.ps1'
$uninstallerPath = Join-Path $repositoryRoot 'uninstall.ps1'

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repositoryRoot 'dist'
}

if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
    throw "Release installer was not found at '$installerPath'."
}
if (-not (Test-Path -LiteralPath $uninstallerPath -PathType Leaf)) {
    throw "Release uninstaller was not found at '$uninstallerPath'."
}

$manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
$version = [string] $manifest.ModuleVersion
if ([string]::IsNullOrWhiteSpace($version)) {
    throw "Module manifest '$manifestPath' does not define ModuleVersion."
}

$artifactFileName = "CopyGitHubRepo-$version.zip"
$artifactPath = Join-Path $OutputDirectory $artifactFileName
$checksumPath = "$artifactPath.sha256"

New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
Remove-Item -LiteralPath $artifactPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $checksumPath -Force -ErrorAction SilentlyContinue

$moduleFiles = @(Get-ChildItem -LiteralPath $moduleSourcePath -File -Recurse)
if ($moduleFiles.Count -eq 0) {
    throw "No module files were found under '$moduleSourcePath'."
}

$packageFiles = @(
    [pscustomobject] @{
        EntryName = 'install.ps1'
        FilePath = $installerPath
    }
    [pscustomobject] @{
        EntryName = 'uninstall.ps1'
        FilePath = $uninstallerPath
    }

    foreach ($file in $moduleFiles) {
        $relativePath = [System.IO.Path]::GetRelativePath($moduleSourcePath, $file.FullName).Replace('\', '/')
        [pscustomobject] @{
            EntryName = "CopyGitHubRepo/$version/$relativePath"
            FilePath = $file.FullName
        }
    }
) | Sort-Object -Property EntryName

$fixedTimestamp = [datetimeoffset]::new(2000, 1, 1, 0, 0, 0, [timespan]::Zero)
$fileStream = $null
$archive = $null

try {
    $fileStream = [System.IO.File]::Open(
        $artifactPath,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )
    $archive = [System.IO.Compression.ZipArchive]::new(
        $fileStream,
        [System.IO.Compression.ZipArchiveMode]::Create,
        $false
    )

    foreach ($packageFile in $packageFiles) {
        $entry = $archive.CreateEntry(
            $packageFile.EntryName,
            [System.IO.Compression.CompressionLevel]::NoCompression
        )
        $entry.LastWriteTime = $fixedTimestamp

        $sourceStream = $null
        $entryStream = $null
        try {
            $sourceStream = [System.IO.File]::OpenRead($packageFile.FilePath)
            $entryStream = $entry.Open()
            $sourceStream.CopyTo($entryStream)
        }
        finally {
            if ($null -ne $entryStream) {
                $entryStream.Dispose()
            }
            if ($null -ne $sourceStream) {
                $sourceStream.Dispose()
            }
        }
    }
}
finally {
    if ($null -ne $archive) {
        $archive.Dispose()
    }
    if ($null -ne $fileStream) {
        $fileStream.Dispose()
    }
}

$hash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $artifactFileName" |
    Set-Content -LiteralPath $checksumPath -Encoding utf8NoBOM

[pscustomobject] @{
    PSTypeName = 'CopyGitHubRepo.ReleaseArtifact'
    Version = $version
    ArtifactPath = $artifactPath
    ChecksumPath = $checksumPath
    Sha256 = $hash
    FileCount = $packageFiles.Count
}
