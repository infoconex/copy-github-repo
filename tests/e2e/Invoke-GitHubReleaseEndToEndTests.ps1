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
$evidence = [System.Collections.Generic.List[object]]::new()

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

function Write-E2eMessage {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string] $Message = ''
    )

    Write-Information -MessageData $Message -InformationAction Continue
}

function Assert-E2eEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [bool] $Condition,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Check,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $FailureMessage,
        [string] $Actual
    )

    if (-not $Condition) {
        throw $FailureMessage
    }

    $record = [pscustomobject] @{
        Status = 'PASS'
        Check = $Check
        Actual = $Actual
    }
    $script:evidence.Add($record)
    $actualSuffix = if ([string]::IsNullOrWhiteSpace($Actual)) { '' } else { " [$Actual]" }
    Write-E2eMessage -Message ('PASS  {0}{1}' -f $Check, $actualSuffix)
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'This protected E2E cleanup helper deletes only repositories created under the current randomized harness prefix after cleanup capability has been verified.'
    )]
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

Write-E2eMessage -Message 'GitHub Release End-to-End Validation'
Write-E2eMessage -Message '------------------------------------'
Write-E2eMessage -Message 'Use Case : UC-HIST-REL'
Write-E2eMessage -Message 'Scenarios: SCN-GHREL-HAPPY-01, SCN-GHREL-VERIFY-01'
Write-E2eMessage -Message 'Goal     : Preserve an approved filtered GitHub Release and asset during FullHistory migration.'
Write-E2eMessage -Message 'Expected : Select the newest stable matching release, exclude the prerelease, preserve release'
Write-E2eMessage -Message '           metadata/assets/Latest designation and FullHistory tag targets, then pass independent verification.'
Write-E2eMessage

Assert-E2eCleanupCapability
Import-Module $modulePath -Force -ErrorAction Stop
New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

try {
    Write-E2eMessage -Message 'Evidence'
    Write-E2eMessage -Message '--------'

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

    $selectedReleases = @($plan.ReleaseSelection.Releases)
    Assert-E2eEvidence -Condition ($plan.ReleaseSelection.AvailableReleaseCount -eq 3) -Check 'Source fixture exposes all three GitHub Releases' -FailureMessage "Expected 3 available source releases but found $($plan.ReleaseSelection.AvailableReleaseCount)." -Actual "$($plan.ReleaseSelection.AvailableReleaseCount) releases"
    Assert-E2eEvidence -Condition ($plan.ReleaseSelection.SelectedReleaseCount -eq 1 -and $selectedReleases.Count -eq 1) -Check 'ReleaseCount limits selection to one release' -FailureMessage 'Release selection did not select exactly one release.' -Actual "$($plan.ReleaseSelection.SelectedReleaseCount) selected"
    Assert-E2eEvidence -Condition ($selectedReleases[0].TagName -eq 'v1.1.0') -Check 'Filtering selects the newest stable matching release' -FailureMessage 'Release selection did not choose only the newest stable matching release v1.1.0.' -Actual $selectedReleases[0].TagName
    Assert-E2eEvidence -Condition ($plan.ReleaseSelection.SourceLatestTag -eq 'v1.1.0' -and $plan.ReleaseSelection.SourceLatestSelected -and $selectedReleases[0].IsLatest) -Check 'Plan captures the selected source Latest release' -FailureMessage 'Planning did not capture v1.1.0 as the selected source Latest release.' -Actual $plan.ReleaseSelection.SourceLatestTag

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

    Assert-E2eEvidence -Condition ($result.IsVerified -and $result.ReleasesRestored) -Check 'FullHistory execution reports verified release restoration' -FailureMessage 'FullHistory release migration did not report verified release restoration.'
    Assert-E2eEvidence -Condition ($result.Releases.DestinationReleaseCount -eq 1) -Check 'Execution restores exactly the approved release count' -FailureMessage "Expected one destination release but result reported $($result.Releases.DestinationReleaseCount)." -Actual "$($result.Releases.DestinationReleaseCount) release"
    Assert-E2eEvidence -Condition ($result.Releases.LatestReleasePreserved -and $result.Releases.LatestReleaseTag -eq 'v1.1.0') -Check 'Execution reports preservation of Latest designation' -FailureMessage 'Execution did not report preservation of the selected source Latest release designation.' -Actual $result.Releases.LatestReleaseTag

    $independentVerification = Test-GitHubRepositoryMigration `
        -SourceRepository $sourceRepository `
        -DestinationRepository $destinationRepository `
        -ContentMode FullHistory `
        -IncludeReleases `
        -ReleaseTag 'v1.*' `
        -ReleaseCount 1

    Assert-E2eEvidence -Condition ($independentVerification.IsSuccessful -and $independentVerification.ReleasesVerified) -Check 'Independent FullHistory and release verification succeeds' -FailureMessage 'Independent FullHistory plus GitHub Release verification did not succeed.'
    Assert-E2eEvidence -Condition ($independentVerification.ReleaseVerification.VerifiedReleaseCount -eq 1) -Check 'Independent verifier confirms the selected release count' -FailureMessage 'Independent release verification did not verify the expected release count.' -Actual "$($independentVerification.ReleaseVerification.VerifiedReleaseCount) release"
    Assert-E2eEvidence -Condition ($independentVerification.ReleaseVerification.DestinationLatestTag -eq 'v1.1.0') -Check 'Independent verifier confirms Latest designation' -FailureMessage 'Independent release verification did not verify the expected Latest designation.' -Actual $independentVerification.ReleaseVerification.DestinationLatestTag

    $destinationReleaseList = @(Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @('api', '--hostname', 'github.com', "repos/$destinationRepository/releases?per_page=100"))
    $destinationReleases = @(($destinationReleaseList -join "`n") | ConvertFrom-Json -Depth 50)
    Assert-E2eEvidence -Condition ($destinationReleases.Count -eq 1) -Check 'GitHub API shows exactly one destination Release' -FailureMessage "Expected exactly one GitHub Release at destination but found $($destinationReleases.Count)." -Actual "$($destinationReleases.Count) release"

    $destinationRelease = $destinationReleases[0]
    Assert-E2eEvidence -Condition ([string] $destinationRelease.tag_name -eq 'v1.1.0') -Check 'Destination release tag is preserved' -FailureMessage "Unexpected destination release tag '$($destinationRelease.tag_name)'." -Actual ([string] $destinationRelease.tag_name)
    Assert-E2eEvidence -Condition ([string] $destinationRelease.name -eq 'Release 1.1.0') -Check 'Destination release title is preserved' -FailureMessage 'Destination release title was not preserved.' -Actual ([string] $destinationRelease.name)
    Assert-E2eEvidence -Condition ([string] $destinationRelease.body -eq 'Stable release 1.1.0') -Check 'Destination release notes are preserved' -FailureMessage 'Destination release notes were not preserved.'
    Assert-E2eEvidence -Condition (-not [bool] $destinationRelease.prerelease) -Check 'Prerelease state remains false for selected stable release' -FailureMessage 'Destination release was unexpectedly marked prerelease.'

    $destinationAssets = @($destinationRelease.assets)
    Assert-E2eEvidence -Condition ($destinationAssets.Count -eq 1) -Check 'Destination release asset count is preserved' -FailureMessage 'Destination release asset count was not preserved.' -Actual "$($destinationAssets.Count) asset"
    Assert-E2eEvidence -Condition ([string] $destinationAssets[0].name -eq 'v1.1.0.txt') -Check 'Destination release asset name is preserved' -FailureMessage 'Destination release asset name was not preserved.' -Actual ([string] $destinationAssets[0].name)
    Assert-E2eEvidence -Condition ([string] $destinationAssets[0].label -eq 'stable-110') -Check 'Destination release asset label is preserved' -FailureMessage 'Destination release asset label was not preserved.' -Actual ([string] $destinationAssets[0].label)

    $destinationLatestJson = @(Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @('api', '--hostname', 'github.com', "repos/$destinationRepository/releases/latest")) -join "`n"
    $destinationLatest = $destinationLatestJson | ConvertFrom-Json -Depth 50
    Assert-E2eEvidence -Condition ([string] $destinationLatest.tag_name -eq 'v1.1.0') -Check 'GitHub API confirms destination Latest release' -FailureMessage "Destination Latest release mismatch. Expected 'v1.1.0' but found '$($destinationLatest.tag_name)'." -Actual ([string] $destinationLatest.tag_name)

    foreach ($tag in @('v1.0.0', 'v1.1.0-rc.1', 'v1.1.0')) {
        $sourceShaOutput = @(Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @('api', '--hostname', 'github.com', "repos/$sourceRepository/commits/$tag", '--jq', '.sha'))
        $destinationShaOutput = @(Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @('api', '--hostname', 'github.com', "repos/$destinationRepository/commits/$tag", '--jq', '.sha'))
        Assert-E2eEvidence -Condition ($sourceShaOutput.Count -eq 1 -and $destinationShaOutput.Count -eq 1) -Check "GitHub API resolves one source and destination SHA for $tag" -FailureMessage "Expected one commit SHA response for tag '$tag' from both source and destination."
        $sourceSha = ([string] $sourceShaOutput[0]).Trim()
        $destinationSha = ([string] $destinationShaOutput[0]).Trim()
        Assert-E2eEvidence -Condition ($sourceSha -eq $destinationSha) -Check "FullHistory tag target is preserved for $tag" -FailureMessage "FullHistory tag target mismatch for '$tag'. Source=$sourceSha Destination=$destinationSha" -Actual $sourceSha
    }

    Assert-E2eEvidence -Condition (@($destinationReleases | Where-Object prerelease).Count -eq 0) -Check 'Filtered prerelease is not recreated at destination' -FailureMessage 'A prerelease was unexpectedly recreated at the destination.'

    Write-E2eMessage
    Write-E2eMessage -Message ('E2E evidence: {0} checks passed.' -f $evidence.Count)
    Write-E2eMessage

    [pscustomobject] @{
        Scenario = 'Filtered FullHistory GitHub Release migration'
        SourceRepository = $sourceRepository
        DestinationRepository = $destinationRepository
        EvidenceChecksPassed = $evidence.Count
        AvailableSourceReleases = $plan.ReleaseSelection.AvailableReleaseCount
        SelectedSourceReleases = $plan.ReleaseSelection.SelectedReleaseCount
        SelectedTag = $selectedReleases[0].TagName
        DestinationReleaseCount = $destinationReleases.Count
        AssetPreserved = $destinationAssets[0].name -eq 'v1.1.0.txt'
        ReleaseMetadataPreserved = $destinationRelease.name -eq 'Release 1.1.0'
        LatestReleasePreserved = $destinationLatest.tag_name -eq 'v1.1.0'
        FullHistoryTagTargetsPreserved = $true
        PrereleaseExcluded = @($destinationReleases | Where-Object prerelease).Count -eq 0
        ExecutionVerified = $result.IsVerified
        IndependentVerificationSucceeded = $independentVerification.IsSuccessful
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
