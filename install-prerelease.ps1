#requires -Version 7.4

[CmdletBinding()]
param(
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

$repository = 'infoconex/copy-github-repo'
$branch = 'main'
$commitApiUrl = "https://api.github.com/repos/$repository/commits/$branch"
$headers = @{
    Accept = 'application/vnd.github+json'
    'User-Agent' = 'CopyGitHubRepo-Prerelease-Installer'
}

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) "CopyGitHubRepo-prerelease-$([guid]::NewGuid().ToString('N'))"

try {
    New-Item -Path $temporaryRoot -ItemType Directory -Force | Out-Null

    $commit = Invoke-RestMethod -Uri $commitApiUrl -Headers $headers
    $commitSha = [string] $commit.sha
    if ($commitSha -notmatch '^[a-fA-F0-9]{40}$') {
        throw (ConvertTo-CgrApplicationErrorRecord `
            -Message "GitHub did not return a valid commit SHA for '$repository' branch '$branch'." `
            -ErrorId 'CopyGitHubRepo.InvalidPrereleaseCommit' `
            -TargetObject $branch)
    }

    $archiveUrl = "https://github.com/$repository/archive/$commitSha.zip"
    $archivePath = Join-Path $temporaryRoot "copy-github-repo-$commitSha.zip"
    $extractPath = Join-Path $temporaryRoot 'source'

    Write-Information "Installing unreleased CopyGitHubRepo source from commit $commitSha." -InformationAction Continue
    Invoke-WebRequest -Uri $archiveUrl -OutFile $archivePath -Headers $headers
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath

    $sourceRoots = @(Get-ChildItem -LiteralPath $extractPath -Directory)
    if ($sourceRoots.Count -ne 1) {
        throw (ConvertTo-CgrApplicationErrorRecord `
            -Message "Expected exactly one repository source directory after extracting commit '$commitSha'." `
            -ErrorId 'CopyGitHubRepo.InvalidPrereleaseArchive' `
            -TargetObject $archivePath)
    }

    $installerPath = Join-Path $sourceRoots[0].FullName 'install.ps1'
    if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
        throw (ConvertTo-CgrApplicationErrorRecord `
            -Message "Unreleased source archive for commit '$commitSha' does not contain install.ps1." `
            -ErrorId 'CopyGitHubRepo.PrereleaseInstallerMissing' `
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
