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
$repositoryPrefix = "copy-github-repo-samename-e2e-$runId"
$createdRepositories = [System.Collections.Generic.List[string]]::new()
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) $repositoryPrefix

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
        throw 'Unable to prove repository-delete capability from the authenticated GitHub token. No E2E repositories were created.'
    }

    $scopes = ($scopeLine -replace '^(?i)x-oauth-scopes:\s*', '').Split(',') |
        ForEach-Object { $_.Trim() }
    if ($scopes -notcontains 'delete_repo') {
        throw "The authenticated GitHub token does not advertise the 'delete_repo' scope required for automatic E2E cleanup. No E2E repositories were created."
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
    if (-not $PSCmdlet.ShouldProcess($fullName, 'Create temporary private same-name E2E repository')) {
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

    if (-not $PSCmdlet.ShouldProcess($Repository, 'Delete temporary same-name E2E repository')) {
        return
    }

    $output = & gh repo delete $Repository --yes 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = (@($output) | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "Failed to delete E2E repository '$Repository'. $message"
    }
}

function Get-E2eTreeSha {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Repository
    )

    $tempPath = Join-Path $tempRoot ([guid]::NewGuid().ToString('N'))
    try {
        $module = Get-Module CopyGitHubRepo
        $cloneResult = & $module {
            param($RepositoryUrl, $TempPath)
            Invoke-CgrGitCommand -HostName 'github.com' -ArgumentList @('clone', '--depth', '1', $RepositoryUrl, $TempPath)
        } "https://github.com/$Repository.git" $tempPath

        if ($cloneResult.ExitCode -ne 0) {
            throw "Failed to clone '$Repository'. $($cloneResult.ErrorText)"
        }

        $tree = Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('rev-parse', 'HEAD^{tree}') -WorkingDirectory $tempPath
        return [string] @($tree)[-1]
    }
    finally {
        Remove-Item -LiteralPath $tempPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-E2eRepositoryId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Repository
    )

    $id = Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @('api', "repos/$Repository", '--jq', '.id')
    return [long] @($id)[-1]
}

if ($Owner -notmatch '^[A-Za-z0-9_.-]+$') {
    throw "Owner '$Owner' is not valid."
}

Assert-E2eCleanupCapability
Import-Module $modulePath -Force -ErrorAction Stop
New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

$sourceName = "$repositoryPrefix-source"
$archiveName = "$repositoryPrefix-archive"
$sourceRepository = "$Owner/$sourceName"
$archiveRepository = "$Owner/$archiveName"
$sourcePath = Join-Path $tempRoot 'source'

try {
    New-E2eRepository -Name $sourceName -Confirm:$false | Out-Null
    $createdRepositories.Add($archiveRepository)

    New-Item -Path $sourcePath -ItemType Directory -Force | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('init', '-b', 'main') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('config', 'user.name', 'Copy GitHub Repo Same Name E2E') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('config', 'user.email', 'copy-github-repo-e2e@users.noreply.github.com') -WorkingDirectory $sourcePath | Out-Null
    Set-Content -LiteralPath (Join-Path $sourcePath 'README.md') -Value '# Same-name replacement E2E fixture' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $sourcePath 'payload.txt') -Value 'same-name-e2e-payload' -Encoding utf8NoBOM
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('add', 'README.md', 'payload.txt') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('commit', '-m', 'Create same-name E2E fixture') -WorkingDirectory $sourcePath | Out-Null

    $module = Get-Module CopyGitHubRepo
    $pushResult = & $module {
        param($RepositoryUrl, $LocalPath)
        Invoke-CgrGitCommand -HostName 'github.com' -ArgumentList @('-C', $LocalPath, 'push', '-u', $RepositoryUrl, 'main')
    } "https://github.com/$sourceRepository.git" $sourcePath
    if ($pushResult.ExitCode -ne 0) {
        throw "Failed to publish same-name E2E source '$sourceRepository'. $($pushResult.ErrorText)"
    }

    $sourceIdBefore = Get-E2eRepositoryId -Repository $sourceRepository
    $sourceTreeBefore = Get-E2eTreeSha -Repository $sourceRepository
    $confirmation = "SOURCE=$sourceRepository;ARCHIVE=$archiveRepository;REPLACEMENT=$sourceRepository"

    $result = Copy-GitHubRepository `
        -SourceRepository $sourceRepository `
        -DestinationRepository $sourceRepository `
        -ArchiveRepositoryName $archiveName `
        -SameNameConfirmation $confirmation `
        -SkipSettings `
        -NonInteractive `
        -Force

    $archiveIdAfter = Get-E2eRepositoryId -Repository $archiveRepository
    $replacementIdAfter = Get-E2eRepositoryId -Repository $sourceRepository
    $archiveTreeAfter = Get-E2eTreeSha -Repository $archiveRepository
    $replacementTreeAfter = Get-E2eTreeSha -Repository $sourceRepository

    if (-not $result.IsVerified) {
        throw 'Same-name replacement result was not verified.'
    }
    if ($result.ArchiveRepository -ne $archiveRepository) {
        throw "Unexpected archive repository '$($result.ArchiveRepository)'."
    }
    if ($sourceIdBefore -ne $archiveIdAfter) {
        throw 'Archived repository did not preserve the original immutable GitHub repository ID.'
    }
    if ($replacementIdAfter -eq $sourceIdBefore) {
        throw 'Replacement repository reused the original immutable GitHub repository ID.'
    }
    if ($result.SourceRepositoryId -ne $sourceIdBefore -or $result.ArchiveRepositoryId -ne $archiveIdAfter -or $result.DestinationRepositoryId -ne $replacementIdAfter) {
        throw 'Execution evidence did not preserve the observed GitHub repository IDs.'
    }
    if ($sourceTreeBefore -ne $archiveTreeAfter) {
        throw 'Archived source tree does not match the original source tree.'
    }
    if ($sourceTreeBefore -ne $replacementTreeAfter) {
        throw 'Replacement snapshot tree does not match the original source tree.'
    }

    [pscustomobject] @{
        Scenario = 'Successful same-name snapshot replacement'
        SourceRepository = $sourceRepository
        ArchiveRepository = $archiveRepository
        ReplacementRepository = $sourceRepository
        SourceRepositoryId = $sourceIdBefore
        ArchiveRepositoryId = $archiveIdAfter
        ReplacementRepositoryId = $replacementIdAfter
        ArchiveIdentityPreserved = $sourceIdBefore -eq $archiveIdAfter
        ReplacementIdentityDistinct = $replacementIdAfter -ne $sourceIdBefore
        SnapshotCommitSha = $result.SnapshotCommitSha
        Verified = $result.IsVerified
        ArchiveTreePreserved = $sourceTreeBefore -eq $archiveTreeAfter
        ReplacementTreeMatches = $sourceTreeBefore -eq $replacementTreeAfter
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
        Write-Warning "E2E repositories were retained because -KeepRepositories was supplied: $(@($createdRepositories) -join ', ')"
    }

    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
