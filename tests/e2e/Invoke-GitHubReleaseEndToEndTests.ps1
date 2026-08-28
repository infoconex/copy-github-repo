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
$repositoryPrefix = "copy-github-repo-release-e2e-$runId"
$sourceRepository = "$Owner/$repositoryPrefix-source"
$destinationRepository = "$Owner/$repositoryPrefix-destination"
$createdRepositories = [System.Collections.Generic.List[string]]::new()
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) $repositoryPrefix

function Invoke-E2eNativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $FilePath,
        [Parameter(Mandatory)] [string[]] $ArgumentList,
        [string] $WorkingDirectory
    )

    $originalLocation = Get-Location
    try {
        if ($WorkingDirectory) { Set-Location -LiteralPath $WorkingDirectory }
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

    if ($KeepRepositories) { return }

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

    $scopes = ($scopeLine -replace '^(?i)x-oauth-scopes:\s*', '').Split(',') | ForEach-Object { $_.Trim() }
    if ($scopes -notcontains 'delete_repo') {
        throw "The authenticated GitHub token does not advertise the 'delete_repo' scope required for automatic E2E cleanup. No E2E repositories were created."
    }
}

function Remove-E2eRepository {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Repository)

    $expectedPrefix = "$Owner/$repositoryPrefix-"
    if (-not $Repository.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to delete repository '$Repository' because it is outside the protected E2E prefix '$expectedPrefix'."
    }

    $output = & gh repo delete $Repository --yes 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = (@($output) | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "Failed to delete E2E repository '$Repository'. $message"
    }
}

if ($Owner -notmatch '^[A-Za-z0-9_.-]+$') { throw "Owner '$Owner' is not valid." }

Assert-E2eCleanupCapability
Import-Module $modulePath -Force -ErrorAction Stop
New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

try {
    Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @('repo', 'create', $sourceRepository, '--private') | Out-Null
    $createdRepositories.Add($sourceRepository)
    $createdRepositories.Add($destinationRepository)

    $sourcePath = Join-Path $tempRoot 'source'
    New-Item -Path $sourcePath -ItemType Directory -Force | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('init', '-b', 'main') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('config', 'user.name', 'Copy GitHub Repo Release E2E') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('config', 'user.email', 'copy-github-repo-release-e2e@users.noreply.github.com') -WorkingDirectory $sourcePath | Out-Null

    Set-Content -LiteralPath (Join-Path $sourcePath 'README.md') -Value '# GitHub Release E2E Fixture' -Encoding utf8NoBOM
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('add', 'README.md') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('commit', '-m', 'Version 1.0 content') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('tag', 'v1.0.0') -WorkingDirectory $sourcePath | Out-Null

    Set-Content -LiteralPath (Join-Path $sourcePath 'version.txt') -Value '1.1.0' -Encoding utf8NoBOM
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('add', 'version.txt') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('commit', '-m', 'Version 1.1 content') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('tag', 'v1.1.0-rc.1') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('tag', 'v1.1.0') -WorkingDirectory $sourcePath | Out-Null

    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('remote', 'add', 'origin', "https://github.com/$sourceRepository.git") -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('push', '-u', 'origin', 'main', '--tags') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @('api', '--hostname', 'github.com', '-X', 'PATCH', "repos/$sourceRepository", '-f', 'default_branch=main') | Out-Null

    $asset100 = Join-Path $tempRoot 'v1.0.0.txt'
    $asset110 = Join-Path $tempRoot 'v1.1.0.txt'
    $assetRc = Join-Path $tempRoot 'v1.1.0-rc.1.txt'
    Set-Content -LiteralPath $asset100 -Value 'stable-100-asset' -Encoding utf8NoBOM
    Set-Content -LiteralPath $asset110 -Value 'stable-110-asset' -Encoding utf8NoBOM
    Set-Content -LiteralPath $assetRc -Value 'prerelease-asset' -Encoding utf8NoBOM

    Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @('release', 'create', 'v1.0.0', '--repo', $sourceRepository, '--title', 'Release 1.0.0', '--notes', 'Stable release 1.0.0', "$asset100#stable-100") | Out-Null
    Start-Sleep -Seconds 1
    Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @('release', 'create', 'v1.1.0-rc.1', '--repo', $sourceRepository, '--title', 'Release 1.1.0 RC1', '--notes', 'Prerelease candidate', '--prerelease', "$assetRc#rc-asset") | Out-Null
    Start-Sleep -Seconds 1
    Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @('release', 'create', 'v1.1.0', '--repo', $sourceRepository, '--title', 'Release 1.1.0', '--notes', 'Stable release 1.1.0', '--latest', "$asset110#stable-110") | Out-Null

    $plan = Copy-GitHubRepository `
        -SourceRepository $sourceRepository `
        -DestinationRepository $destinationRepository `
        -ContentMode FullHistory `
        -IncludeReleases `
        -ReleaseTag 'v1.*' `
        -ReleaseCount 1 `
        -SkipSettings `
        -PlanOnly

    if ($plan.ReleaseSelection.AvailableReleaseCount -ne 3) {
        throw "Expected 3 available source releases but found $($plan.ReleaseSelection.AvailableReleaseCount)."
    }
    if ($plan.ReleaseSelection.SelectedReleaseCount -ne 1 -or $plan.ReleaseSelection.Releases[0].TagName -ne 'v1.1.0') {
        throw 'Release selection did not choose only the newest stable matching release v1.1.0.'
    }
    if ($plan.ReleaseSelection.SourceLatestTag -ne 'v1.1.0' -or -not $plan.ReleaseSelection.SourceLatestSelected -or -not $plan.ReleaseSelection.Releases[0].IsLatest) {
        throw 'Planning did not capture v1.1.0 as the selected source Latest release.'
    }

    $result = Copy-GitHubRepository `
        -SourceRepository $sourceRepository `
        -DestinationRepository $destinationRepository `
        -ContentMode FullHistory `
        -IncludeReleases `
        -ReleaseTag 'v1.*' `
        -ReleaseCount 1 `
        -SkipSettings `
        -NonInteractive `
        -Force

    if (-not $result.IsVerified -or -not $result.ReleasesRestored) {
        throw 'FullHistory release migration did not report verified release restoration.'
    }
    if ($result.Releases.DestinationReleaseCount -ne 1) {
        throw "Expected one destination release but result reported $($result.Releases.DestinationReleaseCount)."
    }
    if (-not $result.Releases.LatestReleasePreserved -or $result.Releases.LatestReleaseTag -ne 'v1.1.0') {
        throw 'Execution did not report preservation of the selected source Latest release designation.'
    }

    $destinationReleaseList = @(Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @('api', '--hostname', 'github.com', "repos/$destinationRepository/releases?per_page=100"))
    $destinationReleases = (($destinationReleaseList -join "`n") | ConvertFrom-Json -Depth 50)
    if (@($destinationReleases).Count -ne 1) {
        throw "Expected exactly one GitHub Release at destination but found $(@($destinationReleases).Count)."
    }

    $destinationRelease = @($destinationReleases)[0]
    if ([string] $destinationRelease.tag_name -ne 'v1.1.0') { throw "Unexpected destination release tag '$($destinationRelease.tag_name)'." }
    if ([string] $destinationRelease.name -ne 'Release 1.1.0') { throw 'Destination release title was not preserved.' }
    if ([string] $destinationRelease.body -ne 'Stable release 1.1.0') { throw 'Destination release notes were not preserved.' }
    if ([bool] $destinationRelease.prerelease) { throw 'Destination release was unexpectedly marked prerelease.' }
    if (@($destinationRelease.assets).Count -ne 1) { throw 'Destination release asset count was not preserved.' }
    if ([string] $destinationRelease.assets[0].name -ne 'v1.1.0.txt') { throw 'Destination release asset name was not preserved.' }
    if ([string] $destinationRelease.assets[0].label -ne 'stable-110') { throw 'Destination release asset label was not preserved.' }

    $destinationLatestJson = @(Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @('api', '--hostname', 'github.com', "repos/$destinationRepository/releases/latest")) -join "`n"
    $destinationLatest = $destinationLatestJson | ConvertFrom-Json -Depth 50
    if ([string] $destinationLatest.tag_name -ne 'v1.1.0') {
        throw "Destination Latest release mismatch. Expected 'v1.1.0' but found '$($destinationLatest.tag_name)'."
    }

    foreach ($tag in @('v1.0.0', 'v1.1.0-rc.1', 'v1.1.0')) {
        $sourceSha = ([string] @(Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @('api', '--hostname', 'github.com', "repos/$sourceRepository/commits/$tag", '--jq', '.sha'))[0]).Trim()
        $destinationSha = ([string] @(Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @('api', '--hostname', 'github.com', "repos/$destinationRepository/commits/$tag", '--jq', '.sha'))[0]).Trim()
        if ($sourceSha -ne $destinationSha) {
            throw "FullHistory tag target mismatch for '$tag'. Source=$sourceSha Destination=$destinationSha"
        }
    }

    [pscustomobject] @{
        Scenario = 'Filtered FullHistory GitHub Release migration'
        SourceRepository = $sourceRepository
        DestinationRepository = $destinationRepository
        AvailableSourceReleases = $plan.ReleaseSelection.AvailableReleaseCount
        SelectedSourceReleases = $plan.ReleaseSelection.SelectedReleaseCount
        SelectedTag = $plan.ReleaseSelection.Releases[0].TagName
        DestinationReleaseCount = @($destinationReleases).Count
        AssetPreserved = $destinationRelease.assets[0].name -eq 'v1.1.0.txt'
        ReleaseMetadataPreserved = $destinationRelease.name -eq 'Release 1.1.0'
        LatestReleasePreserved = $destinationLatest.tag_name -eq 'v1.1.0'
        FullHistoryTagTargetsPreserved = $true
        PrereleaseExcluded = $null -eq (@($destinationReleases | Where-Object prerelease)[0])
        Verified = $result.IsVerified
    } | Format-List
}
finally {
    if (-not $KeepRepositories) {
        foreach ($repository in @($createdRepositories) | Select-Object -Unique) {
            $exists = & gh repo view $repository --json nameWithOwner --jq '.nameWithOwner' 2>$null
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace([string] $exists)) {
                Remove-E2eRepository -Repository $repository
            }
        }
    }
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
