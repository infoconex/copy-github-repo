#requires -Version 7.4

[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string] $Owner = 'infoconex',

    [switch] $KeepRepositories
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
$runId = [guid]::NewGuid().ToString('N').Substring(0, 10)
$repositoryPrefix = "copy-github-repo-lfs-e2e-$runId"
$createdRepositories = [System.Collections.Generic.List[string]]::new()
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) $repositoryPrefix
$expectedPayload = "copy-github-repo-lfs-e2e-$runId-payload"

function Invoke-E2eNativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $FilePath,

        [Parameter(Mandatory)]
        [string[]] $ArgumentList,

        [string] $WorkingDirectory
    )

    $originalLocation = Get-Location
    try {
        if ($WorkingDirectory) {
            Set-Location -LiteralPath $WorkingDirectory
        }

        $output = & $FilePath @ArgumentList 2>&1
        $exitCode = if ($null -ne $global:LASTEXITCODE) { $global:LASTEXITCODE } else { 0 }
        if ($exitCode -ne 0) {
            $message = (@($output) | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
            throw "$FilePath failed with exit code $exitCode. $message"
        }

        return @($output)
    }
    finally {
        Set-Location -LiteralPath $originalLocation
    }
}

function Assert-E2eCleanupCapability {
    [CmdletBinding()]
    param()

    if ($KeepRepositories) {
        return
    }

    $headerOutput = & gh api --include user 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = (@($headerOutput) | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "Unable to verify GitHub cleanup capability before E2E repository creation. $message"
    }

    $scopeLine = @($headerOutput | ForEach-Object { $_.ToString() }) |
        Where-Object { $_ -match '^(?i)x-oauth-scopes:\s*' } |
        Select-Object -First 1

    if (-not $scopeLine) {
        throw 'Unable to prove repository-delete capability from the authenticated GitHub token. No E2E repositories were created. Use -KeepRepositories only when deliberate manual cleanup is acceptable.'
    }

    $scopes = ($scopeLine -replace '^(?i)x-oauth-scopes:\s*', '').Split(',') |
        ForEach-Object { $_.Trim() }
    if ($scopes -notcontains 'delete_repo') {
        throw "The authenticated GitHub token does not advertise the 'delete_repo' scope required for automatic E2E cleanup. No E2E repositories were created. Run 'gh auth refresh --hostname github.com --scopes delete_repo' before retrying, or use -KeepRepositories for deliberate manual cleanup."
    }
}

function Assert-GitLfsAvailable {
    [CmdletBinding()]
    param()

    $result = & git lfs version 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = (@($result) | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "Git LFS is required for this E2E harness. $message"
    }
}

function New-E2eRepository {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    if ($Name -notlike "$repositoryPrefix-*") {
        throw "Refusing to create an E2E repository outside the protected prefix '$repositoryPrefix-*'."
    }

    $fullName = "$Owner/$Name"
    if (-not $PSCmdlet.ShouldProcess($fullName, 'Create temporary private Git LFS E2E repository')) {
        return $null
    }

    Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @('repo', 'create', $fullName, '--private') | Out-Null
    $createdRepositories.Add($fullName)
    return $fullName
}

function Remove-E2eRepository {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Repository
    )

    $expectedPrefix = "$Owner/$repositoryPrefix-"
    if (-not $Repository.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to delete repository '$Repository' because it is outside the protected E2E prefix '$expectedPrefix'."
    }

    if (-not $PSCmdlet.ShouldProcess($Repository, 'Delete temporary Git LFS E2E repository')) {
        return
    }

    $output = & gh repo delete $Repository --yes 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = (@($output) | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "Failed to delete E2E repository '$Repository'. $message"
    }
}

function Publish-E2eSourceRepository {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Repository,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LocalPath
    )

    $module = Get-Module CopyGitHubRepo
    if (-not $module) {
        throw 'CopyGitHubRepo module is not loaded.'
    }

    $pushResult = & $module {
        param($RepositoryUrl, $LocalPath)
        Invoke-CgrGitCommand -HostName 'github.com' -ArgumentList @('-C', $LocalPath, 'push', '-u', $RepositoryUrl, 'main')
    } "https://github.com/$Repository.git" $LocalPath

    if ($pushResult.ExitCode -ne 0) {
        throw "Failed to publish E2E source '$Repository'. $($pushResult.ErrorText)"
    }
}

function Assert-E2eDestinationContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Repository,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ExpectedPayload
    )

    $clonePath = Join-Path $tempRoot 'destination-clone'
    $module = Get-Module CopyGitHubRepo
    $cloneResult = & $module {
        param($RepositoryUrl, $ClonePath)
        Invoke-CgrGitCommand -HostName 'github.com' -ArgumentList @('clone', '--depth', '1', $RepositoryUrl, $ClonePath)
    } "https://github.com/$Repository.git" $clonePath

    if ($cloneResult.ExitCode -ne 0) {
        throw "Failed to clone Git LFS E2E destination '$Repository'. $($cloneResult.ErrorText)"
    }

    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('lfs', 'pull') -WorkingDirectory $clonePath | Out-Null

    $payloadPath = Join-Path $clonePath 'payload.bin'
    if (-not (Test-Path -LiteralPath $payloadPath -PathType Leaf)) {
        throw "Git LFS payload file was not present in '$Repository'."
    }

    $actualPayload = [System.IO.File]::ReadAllText($payloadPath).TrimEnd("`r", "`n")
    if ($actualPayload -ne $ExpectedPayload) {
        throw "Git LFS payload mismatch in '$Repository'. Expected '$ExpectedPayload' but found '$actualPayload'."
    }

    $pointerText = Invoke-E2eNativeCommand `
        -FilePath 'git' `
        -ArgumentList @('show', 'HEAD:payload.bin') `
        -WorkingDirectory $clonePath
    if (($pointerText -join [Environment]::NewLine) -notmatch '^version https://git-lfs.github.com/spec/v1') {
        throw "Destination Git tree does not contain a Git LFS pointer for 'payload.bin'."
    }
}

if ($Owner -notmatch '^[A-Za-z0-9_.-]+$') {
    throw "Owner '$Owner' is not valid."
}

Assert-E2eCleanupCapability
Assert-GitLfsAvailable
Import-Module $modulePath -Force -ErrorAction Stop
New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

try {
    $sourceRepository = New-E2eRepository -Name "$repositoryPrefix-source" -Confirm:$false
    $destinationRepository = "$Owner/$repositoryPrefix-destination"
    $createdRepositories.Add($destinationRepository)
    $sourcePath = Join-Path $tempRoot 'source'

    New-Item -Path $sourcePath -ItemType Directory -Force | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('init', '-b', 'main') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('config', 'user.name', 'Copy GitHub Repo Git LFS E2E') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('config', 'user.email', 'copy-github-repo-lfs-e2e@users.noreply.github.com') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('lfs', 'install', '--local') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('lfs', 'track', '*.bin') -WorkingDirectory $sourcePath | Out-Null
    Set-Content -LiteralPath (Join-Path $sourcePath 'README.md') -Value '# Git LFS Snapshot E2E Fixture' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $sourcePath 'payload.bin') -Value $expectedPayload -Encoding utf8NoBOM
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('add', '.gitattributes', 'README.md', 'payload.bin') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('commit', '-m', 'Create Git LFS E2E fixture') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('remote', 'add', 'origin', "https://github.com/$sourceRepository.git") -WorkingDirectory $sourcePath | Out-Null
    Publish-E2eSourceRepository -Repository $sourceRepository -LocalPath $sourcePath

    $result = Copy-GitHubRepository `
        -SourceRepository $sourceRepository `
        -DestinationRepository $destinationRepository `
        -SkipSettings `
        -NonInteractive `
        -Force

    if (-not $result.IsVerified) {
        throw 'Git LFS snapshot verification did not report success.'
    }

    Assert-E2eDestinationContent -Repository $destinationRepository -ExpectedPayload $expectedPayload

    [pscustomobject] @{
        Scenario = 'Successful Git LFS snapshot'
        SourceRepository = $sourceRepository
        DestinationRepository = $destinationRepository
        SnapshotCommitSha = $result.SnapshotCommitSha
        Verified = $result.IsVerified
        GitLfsPointerPreserved = $true
        GitLfsObjectRetrievable = $true
        PayloadContentVerified = $true
    } | Format-List
}
finally {
    if (-not $KeepRepositories) {
        foreach ($repository in @($createdRepositories) | Select-Object -Unique | Sort-Object -Descending) {
            try {
                Remove-E2eRepository -Repository $repository -Confirm:$false
            }
            catch {
                Write-Warning "Failed to clean up E2E repository '$repository'. $($_.Exception.Message)"
            }
        }
    }
    else {
        Write-Warning "Git LFS E2E repositories were retained because -KeepRepositories was supplied: $(@($createdRepositories) -join ', ')"
    }

    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
