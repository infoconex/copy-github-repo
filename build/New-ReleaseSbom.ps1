#requires -Version 7.4

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingBrokenHashAlgorithms',
    '',
    Justification = 'SPDX 2.3 package verification code requires SHA-1; SHA-256 remains the release artifact and file integrity algorithm.'
)]
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ArtifactPath,

    [Parameter(Mandatory)]
    [string] $SourceCommit,

    [Parameter(Mandatory)]
    [datetimeoffset] $CreatedAt,

    [string] $OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
$manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
$version = [string] $manifest.ModuleVersion

if ([string]::IsNullOrWhiteSpace($version)) {
    throw "Module manifest '$manifestPath' does not define ModuleVersion."
}

if (-not (Test-Path -LiteralPath $ArtifactPath -PathType Leaf)) {
    throw "Release artifact was not found at '$ArtifactPath'."
}

$resolvedArtifactPath = (Resolve-Path -LiteralPath $ArtifactPath).Path
$expectedFileName = "CopyGitHubRepo-$version.zip"
if ([System.IO.Path]::GetFileName($resolvedArtifactPath) -cne $expectedFileName) {
    throw "Release artifact '$resolvedArtifactPath' does not match expected module version '$version'. Expected '$expectedFileName'."
}

if ($SourceCommit -notmatch '^[0-9a-fA-F]{40}$') {
    throw 'SourceCommit must be a full 40-character Git commit SHA.'
}
$normalizedCommit = $SourceCommit.ToLowerInvariant()

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (Split-Path -Parent $resolvedArtifactPath) "CopyGitHubRepo-$version.spdx.json"
}

function Get-CgrStreamHash {
    <#
    .SYNOPSIS
    Computes a lowercase hexadecimal hash for an open stream.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.Stream] $Stream,

        [Parameter(Mandatory)]
        [ValidateSet('SHA1', 'SHA256')]
        [string] $Algorithm
    )

    $hashAlgorithm = [System.Security.Cryptography.HashAlgorithm]::Create($Algorithm)
    if ($null -eq $hashAlgorithm) {
        throw "Unable to create hash algorithm '$Algorithm'."
    }

    try {
        $bytes = $hashAlgorithm.ComputeHash($Stream)
        return ([Convert]::ToHexString($bytes)).ToLowerInvariant()
    }
    finally {
        $hashAlgorithm.Dispose()
    }
}

$artifactSha256 = (Get-FileHash -LiteralPath $resolvedArtifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
$archive = [System.IO.Compression.ZipFile]::OpenRead($resolvedArtifactPath)

try {
    $files = [System.Collections.Generic.List[object]]::new()
    $verificationHashes = [System.Collections.Generic.List[string]]::new()
    $fileIndex = 0

    foreach ($entry in @($archive.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) } | Sort-Object -Property FullName)) {
        $fileIndex++
        $stream = $entry.Open()
        try {
            $sha1 = Get-CgrStreamHash -Stream $stream -Algorithm SHA1
        }
        finally {
            $stream.Dispose()
        }

        $stream = $entry.Open()
        try {
            $sha256 = Get-CgrStreamHash -Stream $stream -Algorithm SHA256
        }
        finally {
            $stream.Dispose()
        }

        $verificationHashes.Add($sha1)
        $files.Add([ordered]@{
            SPDXID = "SPDXRef-File-$fileIndex"
            fileName = "./$($entry.FullName.Replace('\\', '/'))"
            checksums = @(
                [ordered]@{ algorithm = 'SHA1'; checksumValue = $sha1 }
                [ordered]@{ algorithm = 'SHA256'; checksumValue = $sha256 }
            )
            licenseConcluded = 'NOASSERTION'
            copyrightText = 'NOASSERTION'
        })
    }

    if ($files.Count -eq 0) {
        throw "Release artifact '$resolvedArtifactPath' contains no files."
    }

    $verificationInput = [string]::Concat(@($verificationHashes | Sort-Object))
    $verificationBytes = [System.Text.Encoding]::UTF8.GetBytes($verificationInput)
    $verificationStream = [System.IO.MemoryStream]::new($verificationBytes, $false)
    try {
        $packageVerificationCode = Get-CgrStreamHash -Stream $verificationStream -Algorithm SHA1
    }
    finally {
        $verificationStream.Dispose()
    }

    $namespace = "https://github.com/infoconex/copy-github-repo/releases/download/v$version/CopyGitHubRepo-$version.spdx.json#$normalizedCommit"
    $packageId = 'SPDXRef-Package-CopyGitHubRepo'
    $relationships = [System.Collections.Generic.List[object]]::new()
    $relationships.Add([ordered]@{
        spdxElementId = 'SPDXRef-DOCUMENT'
        relationshipType = 'DESCRIBES'
        relatedSpdxElement = $packageId
    })

    foreach ($file in $files) {
        $relationships.Add([ordered]@{
            spdxElementId = $packageId
            relationshipType = 'CONTAINS'
            relatedSpdxElement = $file.SPDXID
        })
    }

    $packageComment = @(
        'Runtime PowerShell module dependencies: none declared in the module manifest.'
        'External runtime prerequisites are PowerShell 7.4+, Git, GitHub CLI, and Git LFS when the selected operation requires LFS.'
        'External prerequisites are intentionally not modeled as SPDX DEPENDS_ON packages because they are not shipped inside this release artifact.'
        'Development-only dependencies such as Pester and PSScriptAnalyzer, GitHub Actions dependencies, and distribution services are intentionally excluded from the shipped runtime dependency graph.'
        "Source commit: $normalizedCommit"
    ) -join ' '

    $document = [ordered]@{
        spdxVersion = 'SPDX-2.3'
        dataLicense = 'CC0-1.0'
        SPDXID = 'SPDXRef-DOCUMENT'
        name = "CopyGitHubRepo-$version"
        documentNamespace = $namespace
        creationInfo = [ordered]@{
            created = $CreatedAt.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            creators = @('Tool: CopyGitHubRepo New-ReleaseSbom.ps1')
        }
        documentDescribes = @($packageId)
        packages = @(
            [ordered]@{
                name = 'CopyGitHubRepo'
                SPDXID = $packageId
                versionInfo = $version
                packageFileName = $expectedFileName
                downloadLocation = "https://github.com/infoconex/copy-github-repo/releases/download/v$version/$expectedFileName"
                filesAnalyzed = $true
                packageVerificationCode = [ordered]@{ packageVerificationCodeValue = $packageVerificationCode }
                checksums = @([ordered]@{ algorithm = 'SHA256'; checksumValue = $artifactSha256 })
                licenseConcluded = 'MIT'
                licenseDeclared = 'MIT'
                copyrightText = 'NOASSERTION'
                primaryPackagePurpose = 'LIBRARY'
                supplier = 'Organization: Infoconex'
                originator = 'Organization: Infoconex'
                sourceInfo = "Built from git commit $normalizedCommit. File inventory and checksums were calculated from the completed release ZIP."
                comment = $packageComment
                externalRefs = @(
                    [ordered]@{
                        referenceCategory = 'PACKAGE-MANAGER'
                        referenceType = 'purl'
                        referenceLocator = "pkg:generic/CopyGitHubRepo@$version"
                    }
                )
            }
        )
        files = @($files)
        relationships = @($relationships)
    }

    $outputDirectory = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
        New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
    }

    $document | ConvertTo-Json -Depth 12 |
        Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM

    [pscustomobject]@{
        PSTypeName = 'CopyGitHubRepo.ReleaseSbom'
        Version = $version
        SbomPath = (Resolve-Path -LiteralPath $OutputPath).Path
        ArtifactPath = $resolvedArtifactPath
        ArtifactSha256 = $artifactSha256
        SourceCommit = $normalizedCommit
        FileCount = $files.Count
        SpdxVersion = 'SPDX-2.3'
    }
}
finally {
    $archive.Dispose()
}
