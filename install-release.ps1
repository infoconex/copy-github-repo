#requires -Version 7.4

[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string] $Version,

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

function Test-CgrApplicationErrorRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    return $ErrorRecord.Exception.Data.Contains('CopyGitHubRepo.ApplicationError') -and
        [bool] $ErrorRecord.Exception.Data['CopyGitHubRepo.ApplicationError']
}

function Write-CgrUnhandledError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('CopyGitHubRepo encountered an unexpected error.')
    $lines.Add("Message: $($ErrorRecord.Exception.Message)")
    $lines.Add("ExceptionType: $($ErrorRecord.Exception.GetType().FullName)")
    $lines.Add("FullyQualifiedErrorId: $($ErrorRecord.FullyQualifiedErrorId)")
    $lines.Add("Category: $($ErrorRecord.CategoryInfo.Category)")

    if ($null -ne $ErrorRecord.TargetObject) {
        $lines.Add("TargetObject: $($ErrorRecord.TargetObject)")
    }

    if (-not [string]::IsNullOrWhiteSpace($ErrorRecord.InvocationInfo.ScriptName)) {
        $lines.Add("Script: $($ErrorRecord.InvocationInfo.ScriptName)")
        $lines.Add("Line: $($ErrorRecord.InvocationInfo.ScriptLineNumber)")
        $lines.Add("Offset: $($ErrorRecord.InvocationInfo.OffsetInLine)")
    }

    if (-not [string]::IsNullOrWhiteSpace($ErrorRecord.ScriptStackTrace)) {
        $lines.Add('ScriptStackTrace:')
        $lines.Add($ErrorRecord.ScriptStackTrace)
    }

    $innerException = $ErrorRecord.Exception.InnerException
    $innerDepth = 0
    while ($null -ne $innerException) {
        $innerDepth++
        $lines.Add("InnerException[$innerDepth]: $($innerException.GetType().FullName): $($innerException.Message)")
        $innerException = $innerException.InnerException
    }

    [Console]::Error.WriteLine(($lines -join [Environment]::NewLine))
}

function Test-CgrReleaseArtifactAttestation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ArtifactPath,

        [Parameter(Mandatory)]
        [string] $Repository,

        [Parameter(Mandatory)]
        [ValidatePattern('^[a-fA-F0-9]{40}$')]
        [string] $SourceCommit,

        [Parameter(Mandatory)]
        [string] $SignerWorkflow
    )

    $ghCommand = Get-Command gh -ErrorAction SilentlyContinue
    if ($null -eq $ghCommand) {
        throw (ConvertTo-CgrApplicationErrorRecord `
            -Message 'GitHub CLI (gh) is required to verify the stable release artifact provenance before installation.' `
            -ErrorId 'CopyGitHubRepo.ReleaseAttestationVerifierUnavailable' `
            -TargetObject 'gh')
    }

    $verificationOutput = @(
        & gh attestation verify $ArtifactPath `
            --repo $Repository `
            --signer-workflow $SignerWorkflow `
            --source-digest $SourceCommit 2>&1
    )
    $verificationExitCode = $LASTEXITCODE

    if ($verificationExitCode -ne 0) {
        $diagnostic = ($verificationOutput | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ }) -join ' '
        if ($diagnostic.Length -gt 500) {
            $diagnostic = $diagnostic.Substring(0, 500) + '...'
        }

        $message = "Cryptographic provenance verification failed for '$([System.IO.Path]::GetFileName($ArtifactPath))'. Installation stopped before extraction."
        if (-not [string]::IsNullOrWhiteSpace($diagnostic)) {
            $message += " GitHub CLI reported: $diagnostic"
        }

        throw (ConvertTo-CgrApplicationErrorRecord `
            -Message $message `
            -ErrorId 'CopyGitHubRepo.ReleaseAttestationInvalid' `
            -TargetObject ([System.IO.Path]::GetFileName($ArtifactPath)))
    }

    return $true
}

$repository = 'infoconex/copy-github-repo'
$releaseSignerWorkflow = 'infoconex/copy-github-repo/.github/workflows/publish-release.yml'
$headers = @{
    Accept = 'application/vnd.github+json'
    'User-Agent' = 'CopyGitHubRepo-Installer'
}

$apiUrl = if ([string]::IsNullOrWhiteSpace($Version)) {
    "https://api.github.com/repos/$repository/releases/latest"
}
else {
    "https://api.github.com/repos/$repository/releases/tags/v$Version"
}

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) "CopyGitHubRepo-install-$([guid]::NewGuid().ToString('N'))"

try {
    New-Item -Path $temporaryRoot -ItemType Directory -Force | Out-Null

    $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers
    if ([string]::IsNullOrWhiteSpace([string] $release.tag_name)) {
        throw (ConvertTo-CgrApplicationErrorRecord `
            -Message 'GitHub did not return a stable CopyGitHubRepo release tag.' `
            -ErrorId 'CopyGitHubRepo.ReleaseTagMissing')
    }

    if ([string] $release.tag_name -notmatch '^v(?<ResolvedVersion>\d+\.\d+\.\d+)$') {
        throw (ConvertTo-CgrApplicationErrorRecord `
            -Message "Release tag '$($release.tag_name)' is not a supported stable version tag." `
            -ErrorId 'CopyGitHubRepo.InvalidReleaseTag' `
            -TargetObject $release.tag_name)
    }

    $resolvedVersion = $Matches.ResolvedVersion
    if (-not [string]::IsNullOrWhiteSpace($Version) -and $resolvedVersion -ne $Version) {
        throw (ConvertTo-CgrApplicationErrorRecord `
            -Message "GitHub returned release '$($release.tag_name)' while version '$Version' was requested." `
            -ErrorId 'CopyGitHubRepo.ReleaseVersionMismatch' `
            -TargetObject $release.tag_name)
    }

    $releaseCommitApiUrl = "https://api.github.com/repos/$repository/commits/$($release.tag_name)"
    $releaseCommit = Invoke-RestMethod -Uri $releaseCommitApiUrl -Headers $headers
    $releaseCommitSha = [string] $releaseCommit.sha
    if ($releaseCommitSha -notmatch '^[a-fA-F0-9]{40}$') {
        throw (ConvertTo-CgrApplicationErrorRecord `
            -Message "GitHub did not return a valid commit identity for release '$($release.tag_name)'." `
            -ErrorId 'CopyGitHubRepo.ReleaseCommitIdentityMissing' `
            -TargetObject $release.tag_name)
    }

    $artifactName = "CopyGitHubRepo-$resolvedVersion.zip"
    $checksumName = "$artifactName.sha256"

    $artifactAsset = @($release.assets | Where-Object { $_.name -eq $artifactName })
    $checksumAsset = @($release.assets | Where-Object { $_.name -eq $checksumName })

    if ($artifactAsset.Count -ne 1) {
        throw (ConvertTo-CgrApplicationErrorRecord `
            -Message "Expected exactly one release asset named '$artifactName'." `
            -ErrorId 'CopyGitHubRepo.ReleaseArtifactMissing' `
            -TargetObject $artifactName)
    }

    if ($checksumAsset.Count -ne 1) {
        throw (ConvertTo-CgrApplicationErrorRecord `
            -Message "Expected exactly one release asset named '$checksumName'." `
            -ErrorId 'CopyGitHubRepo.ReleaseChecksumMissing' `
            -TargetObject $checksumName)
    }

    $artifactPath = Join-Path $temporaryRoot $artifactName
    $checksumPath = Join-Path $temporaryRoot $checksumName

    Invoke-WebRequest -Uri $artifactAsset[0].browser_download_url -OutFile $artifactPath -Headers $headers
    Invoke-WebRequest -Uri $checksumAsset[0].browser_download_url -OutFile $checksumPath -Headers $headers

    $checksumText = (Get-Content -LiteralPath $checksumPath -Raw).Trim()
    if ($checksumText -notmatch '^(?<Hash>[a-fA-F0-9]{64})\s+\S+$') {
        throw (ConvertTo-CgrApplicationErrorRecord `
            -Message "Checksum file '$checksumName' is not in the expected SHA-256 format." `
            -ErrorId 'CopyGitHubRepo.InvalidReleaseChecksum' `
            -TargetObject $checksumName)
    }

    $expectedHash = $Matches.Hash.ToLowerInvariant()
    $actualHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()

    if ($actualHash -ne $expectedHash) {
        throw (ConvertTo-CgrApplicationErrorRecord `
            -Message "SHA-256 verification failed for '$artifactName'." `
            -ErrorId 'CopyGitHubRepo.ReleaseChecksumMismatch' `
            -TargetObject $artifactName)
    }

    Test-CgrReleaseArtifactAttestation `
        -ArtifactPath $artifactPath `
        -Repository $repository `
        -SourceCommit $releaseCommitSha `
        -SignerWorkflow $releaseSignerWorkflow | Out-Null

    $extractPath = Join-Path $temporaryRoot 'package'
    Expand-Archive -LiteralPath $artifactPath -DestinationPath $extractPath

    $installerPath = Join-Path $extractPath 'install.ps1'
    if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
        throw (ConvertTo-CgrApplicationErrorRecord `
            -Message "Release package '$artifactName' does not contain install.ps1." `
            -ErrorId 'CopyGitHubRepo.ReleaseInstallerMissing' `
            -TargetObject $installerPath)
    }

    if ($Force) {
        & $installerPath -Force
    }
    else {
        & $installerPath
    }
}
catch {
    if (Test-CgrApplicationErrorRecord -ErrorRecord $_) {
        $errorId = [string] $_.Exception.Data['CopyGitHubRepo.ErrorId']
        $message = [string] $_.Exception.Message

        if ($errorId -eq 'CopyGitHubRepo.VersionAlreadyInstalled') {
            $friendlyMessage = $message -replace '\. Use -Force to replace that version\.$', '. No changes were made. Use -Force to replace that version.'
            Write-Warning $friendlyMessage
            return
        }

        Write-Error -Message "CopyGitHubRepo: $message" -ErrorId $errorId -Category InvalidOperation -ErrorAction Continue
        return
    }

    Write-CgrUnhandledError -ErrorRecord $_
    throw
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
