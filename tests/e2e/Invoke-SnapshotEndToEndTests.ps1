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
$repositoryPrefix = "copy-github-repo-e2e-$runId"
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
        throw 'Unable to prove repository-delete capability from the authenticated GitHub token. No E2E repositories were created. Use -KeepRepositories only when deliberate manual cleanup is acceptable.'
    }

    $scopes = ($scopeLine -replace '^(?i)x-oauth-scopes:\s*', '').Split(',') |
        ForEach-Object { $_.Trim() }
    if ($scopes -notcontains 'delete_repo') {
        throw "The authenticated GitHub token does not advertise the 'delete_repo' scope required for automatic E2E cleanup. No E2E repositories were created. Run 'gh auth refresh --hostname github.com --scopes delete_repo' before retrying, or use -KeepRepositories for deliberate manual cleanup."
    }
}

function New-E2eRepository {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory)]
        [ValidateSet('public', 'private')]
        [string] $Visibility
    )

    if ($Name -notlike "$repositoryPrefix-*") {
        throw "Refusing to create an E2E repository outside the protected prefix '$repositoryPrefix-*'."
    }

    $fullName = "$Owner/$Name"
    if (-not $PSCmdlet.ShouldProcess($fullName, "Create temporary $Visibility E2E repository")) {
        return $null
    }

    Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @('repo', 'create', $fullName, "--$Visibility") | Out-Null
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

    if (-not $PSCmdlet.ShouldProcess($Repository, 'Delete temporary E2E repository')) {
        return
    }

    $output = & gh repo delete $Repository --yes 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = (@($output) | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "Failed to delete E2E repository '$Repository'. $message"
    }
}

function Invoke-E2eTreeFixture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LocalPath
    )

    $linkBlob = 'target.txt' | & git -C $LocalPath hash-object -w --stdin
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string] $linkBlob)) {
        throw 'Failed to create symbolic-link blob for E2E fixture.'
    }

    Invoke-E2eNativeCommand `
        -FilePath 'git' `
        -ArgumentList @('update-index', '--add', '--cacheinfo', "120000,$linkBlob,linked-target") `
        -WorkingDirectory $LocalPath | Out-Null

    $gitlinkSha = '1111111111111111111111111111111111111111'
    Invoke-E2eNativeCommand `
        -FilePath 'git' `
        -ArgumentList @('update-index', '--add', '--cacheinfo', "160000,$gitlinkSha,example-submodule") `
        -WorkingDirectory $LocalPath | Out-Null
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

    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('commit', '-m', 'Create E2E fixture') -WorkingDirectory $LocalPath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('remote', 'add', 'origin', "https://github.com/$Repository.git") -WorkingDirectory $LocalPath | Out-Null

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

function Assert-E2eTreeMode {
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
            throw "Failed to clone E2E destination '$Repository'. $($cloneResult.ErrorText)"
        }

        $tree = Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('ls-tree', 'HEAD') -WorkingDirectory $tempPath
        $treeText = $tree -join [Environment]::NewLine
        if ($treeText -notmatch '100755 blob .*\trun\.sh') {
            throw "Executable mode was not preserved in '$Repository'."
        }
        if ($treeText -notmatch '120000 blob .*\tlinked-target') {
            throw "Symbolic-link mode was not preserved in '$Repository'."
        }
        if ($treeText -notmatch '160000 commit 1111111111111111111111111111111111111111\texample-submodule') {
            throw "Gitlink mode was not preserved in '$Repository'."
        }
    }
    finally {
        Remove-Item -LiteralPath $tempPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-E2eScenario {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('public', 'private')]
        [string] $Visibility
    )

    $sourceName = "$repositoryPrefix-$Visibility-source"
    $destinationName = "$repositoryPrefix-$Visibility-destination"
    $sourceRepository = New-E2eRepository -Name $sourceName -Visibility $Visibility -Confirm:$false
    $sourcePath = Join-Path $tempRoot "$Visibility-source"

    New-Item -Path $sourcePath -ItemType Directory -Force | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('init', '-b', 'main') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('config', 'user.name', 'Copy GitHub Repo E2E') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('config', 'user.email', 'copy-github-repo-e2e@users.noreply.github.com') -WorkingDirectory $sourcePath | Out-Null
    Set-Content -LiteralPath (Join-Path $sourcePath 'README.md') -Value '# Snapshot E2E Fixture' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $sourcePath 'run.sh') -Value "#!/usr/bin/env sh`necho snapshot-e2e" -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $sourcePath 'target.txt') -Value 'symbolic-link-target' -Encoding utf8NoBOM
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('add', 'README.md', 'run.sh', 'target.txt') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('update-index', '--chmod=+x', 'run.sh') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eTreeFixture -LocalPath $sourcePath
    Publish-E2eSourceRepository -Repository $sourceRepository -LocalPath $sourcePath

    $destinationRepository = "$Owner/$destinationName"
    $createdRepositories.Add($destinationRepository)
    $result = Copy-GitHubRepository `
        -SourceRepository $sourceRepository `
        -DestinationRepository $destinationRepository `
        -SkipSettings `
        -NonInteractive `
        -Force

    if (-not $result.IsVerified) {
        throw "Snapshot verification failed for '$Visibility' E2E scenario."
    }
    if ($result.SourceVisibility -ne $Visibility -or $result.DestinationVisibility -ne $Visibility) {
        throw "Visibility preservation failed for '$Visibility' E2E scenario."
    }

    Assert-E2eTreeMode -Repository $destinationRepository

    [pscustomobject] @{
        Scenario = "$Visibility snapshot"
        SourceRepository = $sourceRepository
        DestinationRepository = $destinationRepository
        SnapshotCommitSha = $result.SnapshotCommitSha
        Verified = $result.IsVerified
        VisibilityPreserved = $result.DestinationVisibility -eq $Visibility
        ExecutableModePreserved = $true
        SymbolicLinkModePreserved = $true
        GitlinkModePreserved = $true
    }
}

if ($Owner -notmatch '^[A-Za-z0-9_.-]+$') {
    throw "Owner '$Owner' is not valid."
}

Assert-E2eCleanupCapability
Import-Module $modulePath -Force -ErrorAction Stop
New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

try {
    $results = @(
        Invoke-E2eScenario -Visibility public
        Invoke-E2eScenario -Visibility private
    )

    $results | Format-Table -AutoSize
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