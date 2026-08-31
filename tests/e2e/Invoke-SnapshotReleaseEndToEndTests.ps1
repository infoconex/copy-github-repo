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
$repositoryPrefix = "copy-github-repo-snapshot-release-e2e-$runId"
$createdRepositories = [System.Collections.Generic.List[string]]::new()
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) $repositoryPrefix
$scenarioResults = [System.Collections.Generic.List[object]]::new()

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

function Write-E2eMessage {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string] $Message = ''
    )

    Write-Information -MessageData $Message -InformationAction Continue
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
    if (-not $PSCmdlet.ShouldProcess($fullName, 'Create temporary private Snapshot-release E2E repository')) {
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

    if (-not $PSCmdlet.ShouldProcess($Repository, 'Delete temporary Snapshot-release E2E repository')) {
        return
    }

    $output = & gh repo delete $Repository --yes 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = (@($output) | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "Failed to delete E2E repository '$Repository'. $message"
    }
}

function Get-E2eApiJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    $output = @(Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @('api', '--hostname', 'github.com', $Path))
    return (($output -join "`n") | ConvertFrom-Json -Depth 50)
}

function Get-E2eCommitTreeSha {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Repository,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Ref
    )

    $commit = Get-E2eApiJson -Path "repos/$Repository/commits/$Ref"
    return [string] $commit.commit.tree.sha
}

function Get-E2eCommitSha {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Repository,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Ref
    )

    $commit = Get-E2eApiJson -Path "repos/$Repository/commits/$Ref"
    return [string] $commit.sha
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

function Get-E2eReleaseByTag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Repository,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Tag
    )

    return Get-E2eApiJson -Path "repos/$Repository/releases/tags/$Tag"
}

function New-E2eSourceFixture {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [switch] $HeadNewerThanLatestRelease
    )

    $fullName = "$Owner/$Name"
    if (-not $PSCmdlet.ShouldProcess($fullName, 'Create and publish Snapshot-release E2E source fixture')) {
        return $null
    }

    $repository = New-E2eRepository -Name $Name -Confirm:$false
    $localPath = Join-Path $tempRoot $Name
    New-Item -Path $localPath -ItemType Directory -Force | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('init', '-b', 'main') -WorkingDirectory $localPath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('config', 'user.name', 'Copy GitHub Repo Snapshot Release E2E') -WorkingDirectory $localPath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('config', 'user.email', 'copy-github-repo-snapshot-release-e2e@users.noreply.github.com') -WorkingDirectory $localPath | Out-Null

    Set-Content -LiteralPath (Join-Path $localPath 'README.md') -Value '# Snapshot Release E2E Fixture' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $localPath 'version.txt') -Value '1.0.0' -Encoding utf8NoBOM
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('add', '.') -WorkingDirectory $localPath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('commit', '-m', 'Version 1.0 state') -WorkingDirectory $localPath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('tag', 'v1.0.0') -WorkingDirectory $localPath | Out-Null

    Set-Content -LiteralPath (Join-Path $localPath 'version.txt') -Value '1.1.0-rc.1' -Encoding utf8NoBOM
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('add', 'version.txt') -WorkingDirectory $localPath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('commit', '-m', 'Version 1.1 prerelease state') -WorkingDirectory $localPath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('tag', 'v1.1.0-rc.1') -WorkingDirectory $localPath | Out-Null

    Set-Content -LiteralPath (Join-Path $localPath 'version.txt') -Value '1.1.0' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $localPath 'release.txt') -Value 'stable release payload' -Encoding utf8NoBOM
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('add', '.') -WorkingDirectory $localPath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('commit', '-m', 'Version 1.1 state') -WorkingDirectory $localPath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('tag', 'v1.1.0') -WorkingDirectory $localPath | Out-Null

    if ($HeadNewerThanLatestRelease) {
        Set-Content -LiteralPath (Join-Path $localPath 'head.txt') -Value 'current default branch state' -Encoding utf8NoBOM
        Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('add', 'head.txt') -WorkingDirectory $localPath | Out-Null
        Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('commit', '-m', 'Current state after latest release') -WorkingDirectory $localPath | Out-Null
    }

    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('remote', 'add', 'origin', "https://github.com/$repository.git") -WorkingDirectory $localPath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('push', '-u', 'origin', 'main', '--tags') -WorkingDirectory $localPath | Out-Null

    $asset100 = Join-Path $tempRoot "$Name-v1.0.0.txt"
    $asset110 = Join-Path $tempRoot "$Name-v1.1.0.txt"
    $assetRc = Join-Path $tempRoot "$Name-v1.1.0-rc.1.txt"
    Set-Content -LiteralPath $asset100 -Value 'snapshot-release-100-asset' -Encoding utf8NoBOM
    Set-Content -LiteralPath $asset110 -Value 'snapshot-release-110-asset' -Encoding utf8NoBOM
    Set-Content -LiteralPath $assetRc -Value 'snapshot-release-rc-asset' -Encoding utf8NoBOM

    Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @('release', 'create', 'v1.0.0', '--repo', $repository, '--title', 'Release 1.0.0', '--notes', 'Stable release 1.0.0', "$asset100#stable-100") | Out-Null
    Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @('release', 'create', 'v1.1.0-rc.1', '--repo', $repository, '--title', 'Release 1.1.0 RC1', '--notes', 'Prerelease candidate', '--prerelease', "$assetRc#rc-asset") | Out-Null
    Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @('release', 'create', 'v1.1.0', '--repo', $repository, '--title', 'Release 1.1.0', '--notes', 'Stable release 1.1.0', '--latest', "$asset110#stable-110") | Out-Null

    return [pscustomobject] @{
        Repository = $repository
        LocalPath = $localPath
    }
}

function Assert-E2eSnapshotTagTreeEquivalence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $SourceRepository,
        [Parameter(Mandatory)] [string] $DestinationRepository,
        [Parameter(Mandatory)] [string[]] $Tags
    )

    foreach ($tag in $Tags) {
        $sourceCommit = Get-E2eCommitSha -Repository $SourceRepository -Ref $tag
        $destinationCommit = Get-E2eCommitSha -Repository $DestinationRepository -Ref $tag
        $sourceTree = Get-E2eCommitTreeSha -Repository $SourceRepository -Ref $tag
        $destinationTree = Get-E2eCommitTreeSha -Repository $DestinationRepository -Ref $tag
        if ($sourceCommit -eq $destinationCommit) {
            throw "Snapshot tag '$tag' unexpectedly preserved the source commit identity '$sourceCommit'."
        }
        if ($sourceTree -ne $destinationTree) {
            throw "Snapshot tag '$tag' tree mismatch. Source=$sourceTree Destination=$destinationTree"
        }
    }
}

function Assert-E2eReleaseAssetEquivalent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $SourceRepository,
        [Parameter(Mandatory)] [string] $DestinationRepository,
        [Parameter(Mandatory)] [string] $Tag
    )

    $sourceRelease = Get-E2eReleaseByTag -Repository $SourceRepository -Tag $Tag
    $destinationRelease = Get-E2eReleaseByTag -Repository $DestinationRepository -Tag $Tag
    $sourceAssets = @($sourceRelease.assets)
    $destinationAssets = @($destinationRelease.assets)
    if ($sourceAssets.Count -ne 1 -or $destinationAssets.Count -ne 1) {
        throw "Expected one source and destination asset for '$Tag'. Source=$($sourceAssets.Count) Destination=$($destinationAssets.Count)"
    }

    $assetMetadataEquivalent = [string] $sourceAssets[0].name -eq [string] $destinationAssets[0].name -and [long] $sourceAssets[0].size -eq [long] $destinationAssets[0].size -and [string] $sourceAssets[0].label -eq [string] $destinationAssets[0].label
    if (-not $assetMetadataEquivalent) {
        throw "Release asset metadata mismatch for '$Tag'."
    }

    $sourceDigestAvailable = $sourceAssets[0].PSObject.Properties.Name -contains 'digest' -and -not [string]::IsNullOrWhiteSpace([string] $sourceAssets[0].digest)
    $destinationDigestAvailable = $destinationAssets[0].PSObject.Properties.Name -contains 'digest' -and -not [string]::IsNullOrWhiteSpace([string] $destinationAssets[0].digest)
    if ($sourceDigestAvailable -and $destinationDigestAvailable -and [string] $sourceAssets[0].digest -ne [string] $destinationAssets[0].digest) {
        throw "Release asset digest mismatch for '$Tag'."
    }
}

function Invoke-E2eNewDestinationScenario {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Fixture
    )

    $destination = "$Owner/$repositoryPrefix-multiple-destination"
    $createdRepositories.Add($destination)
    Write-E2eMessage -Message 'Scenario: Snapshot with multiple sequential releases, filtering, HEAD newer, assets, Latest, and new destination'
    Write-E2eMessage -Message 'Migration evidence: executing reviewed Snapshot -IncludeReleases plan.'

    $plan = Copy-GitHubRepository -SourceRepository $Fixture.Repository -DestinationRepository $destination -ContentMode Snapshot -IncludeReleases -ReleaseTag 'v1.*' -SkipSettings -PlanOnly
    if ($plan.ReleaseSelection.SelectedReleaseCount -ne 2) {
        throw "Expected two stable selected releases but plan selected $($plan.ReleaseSelection.SelectedReleaseCount)."
    }

    $result = Copy-GitHubRepository -SourceRepository $Fixture.Repository -DestinationRepository $destination -ContentMode Snapshot -IncludeReleases -ReleaseTag 'v1.*' -SkipSettings -NonInteractive -Force
    if (-not $result.IsVerified -or -not $result.ReleasesRestored) {
        throw 'Snapshot release execution did not report verified release restoration.'
    }

    Write-E2eMessage -Message 'Independent verification: running Test-GitHubRepositoryMigration and direct GitHub API tag/tree/release checks.'
    $verification = Test-GitHubRepositoryMigration -SourceRepository $Fixture.Repository -DestinationRepository $destination -ContentMode Snapshot -IncludeReleases -ApprovedPlan $result.Plan
    if (-not $verification.IsSuccessful -or -not $verification.ReleasesVerified) {
        throw 'Independent Snapshot release verification failed.'
    }

    Assert-E2eSnapshotTagTreeEquivalence -SourceRepository $Fixture.Repository -DestinationRepository $destination -Tags @('v1.0.0', 'v1.1.0')
    Assert-E2eReleaseAssetEquivalent -SourceRepository $Fixture.Repository -DestinationRepository $destination -Tag 'v1.1.0'

    $destinationReleases = @(Get-E2eApiJson -Path "repos/$destination/releases?per_page=100")
    if ($destinationReleases.Count -ne 2) {
        throw "Expected exactly two stable destination releases but found $($destinationReleases.Count)."
    }
    if (@($destinationReleases | Where-Object { $_.prerelease }).Count -ne 0) {
        throw 'Filtered prerelease was unexpectedly recreated.'
    }

    $latest = Get-E2eApiJson -Path "repos/$destination/releases/latest"
    if ([string] $latest.tag_name -ne 'v1.1.0') {
        throw "Expected v1.1.0 to remain Latest but found '$($latest.tag_name)'."
    }

    $sourceHeadTree = Get-E2eCommitTreeSha -Repository $Fixture.Repository -Ref 'main'
    $destinationHeadTree = Get-E2eCommitTreeSha -Repository $destination -Ref 'main'
    $latestReleaseTree = Get-E2eCommitTreeSha -Repository $destination -Ref 'v1.1.0'
    if ($sourceHeadTree -ne $destinationHeadTree) {
        throw 'Final destination HEAD tree does not match source HEAD.'
    }
    if ($destinationHeadTree -eq $latestReleaseTree) {
        throw 'HEAD-newer scenario did not produce a distinct final current-state tree.'
    }

    $summary = [pscustomobject] @{
        Scenario = 'Multiple sequential releases; filtering; HEAD newer; assets; Latest; new destination'
        MigrationReportedVerified = $result.IsVerified
        IndependentVerificationSucceeded = $verification.IsSuccessful
        SelectedReleaseCount = $plan.ReleaseSelection.SelectedReleaseCount
        TagTreesEquivalent = $true
        SnapshotCommitIdentitiesAreNew = $true
        ReleaseAssetEquivalent = $true
        LatestReleasePreserved = $latest.tag_name -eq 'v1.1.0'
        PrereleaseExcluded = $true
        FinalHeadMatchesSource = $sourceHeadTree -eq $destinationHeadTree
        FinalHeadDistinctFromLatestRelease = $destinationHeadTree -ne $latestReleaseTree
    }
    $scenarioResults.Add($summary)
}

function Invoke-E2eHeadEqualScenario {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Fixture
    )

    $destination = "$Owner/$repositoryPrefix-head-equal-destination"
    $createdRepositories.Add($destination)
    Write-E2eMessage -Message 'Scenario: Snapshot with one selected release where HEAD equals the latest selected release state'
    Write-E2eMessage -Message 'Migration evidence: selecting exactly v1.1.0.'

    $result = Copy-GitHubRepository -SourceRepository $Fixture.Repository -DestinationRepository $destination -ContentMode Snapshot -IncludeReleases -ReleaseTag 'v1.1.0' -ReleaseCount 1 -SkipSettings -NonInteractive -Force
    if (-not $result.IsVerified) {
        throw 'HEAD-equal Snapshot release execution did not report verification success.'
    }

    Write-E2eMessage -Message 'Independent verification: validating release checkpoint and final HEAD through independent verifier and GitHub API trees.'
    $verification = Test-GitHubRepositoryMigration -SourceRepository $Fixture.Repository -DestinationRepository $destination -ContentMode Snapshot -IncludeReleases -ApprovedPlan $result.Plan
    if (-not $verification.IsSuccessful) {
        throw 'Independent HEAD-equal Snapshot release verification failed.'
    }

    Assert-E2eSnapshotTagTreeEquivalence -SourceRepository $Fixture.Repository -DestinationRepository $destination -Tags @('v1.1.0')
    $destinationHead = Get-E2eCommitSha -Repository $destination -Ref 'main'
    $destinationTag = Get-E2eCommitSha -Repository $destination -Ref 'v1.1.0'
    if ($destinationHead -ne $destinationTag) {
        throw 'HEAD-equal scenario created an unnecessary final Snapshot commit.'
    }

    $summary = [pscustomobject] @{
        Scenario = 'Single selected release; HEAD equals latest release state'
        MigrationReportedVerified = $result.IsVerified
        IndependentVerificationSucceeded = $verification.IsSuccessful
        TagTreeEquivalent = $true
        HeadCommitEqualsSelectedCheckpoint = $destinationHead -eq $destinationTag
    }
    $scenarioResults.Add($summary)
}

function Invoke-E2eSameNameScenario {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Fixture
    )

    $source = $Fixture.Repository
    $archiveName = "$repositoryPrefix-samename-archive"
    $archiveRepository = "$Owner/$archiveName"
    $createdRepositories.Add($archiveRepository)
    $sourceId = Get-E2eRepositoryId -Repository $source
    $confirmation = "SOURCE=$source;ARCHIVE=$archiveRepository;REPLACEMENT=$source"

    Write-E2eMessage -Message 'Scenario: same-name Snapshot replacement with release preservation and explicit destructive confirmation'
    Write-E2eMessage -Message 'Migration evidence: executing with exact SameNameConfirmation; Force does not replace that authority.'
    $result = Copy-GitHubRepository -SourceRepository $source -DestinationRepository $source -ContentMode Snapshot -IncludeReleases -ReleaseTag 'v1.1.0' -ReleaseCount 1 -ArchiveRepositoryName $archiveName -SameNameConfirmation $confirmation -SkipSettings -NonInteractive -Force
    if (-not $result.IsVerified) {
        throw 'Same-name Snapshot release replacement did not report verification success.'
    }

    Write-E2eMessage -Message 'Independent verification: checking archive identity continuity, replacement identity distinction, and recreated checkpoint/release.'
    $archiveId = Get-E2eRepositoryId -Repository $archiveRepository
    $replacementId = Get-E2eRepositoryId -Repository $source
    if ($sourceId -ne $archiveId) {
        throw 'Same-name archive did not preserve the original GitHub repository identity.'
    }
    if ($replacementId -eq $sourceId) {
        throw 'Same-name replacement reused the original GitHub repository identity.'
    }

    $verification = Test-GitHubRepositoryMigration -SourceRepository $archiveRepository -DestinationRepository $source -ContentMode Snapshot -IncludeReleases -ApprovedPlan $result.Plan
    if (-not $verification.IsSuccessful) {
        throw 'Independent same-name Snapshot release verification failed.'
    }

    Assert-E2eSnapshotTagTreeEquivalence -SourceRepository $archiveRepository -DestinationRepository $source -Tags @('v1.1.0')

    $summary = [pscustomobject] @{
        Scenario = 'Same-name Snapshot replacement with selected release'
        MigrationReportedVerified = $result.IsVerified
        IndependentVerificationSucceeded = $verification.IsSuccessful
        ArchiveIdentityPreserved = $sourceId -eq $archiveId
        ReplacementIdentityDistinct = $replacementId -ne $sourceId
        TagTreeEquivalent = $true
        ExactConfirmationUsed = $true
    }
    $scenarioResults.Add($summary)
}

if ($Owner -notmatch '^[A-Za-z0-9_.-]+$') {
    throw "Owner '$Owner' is not valid."
}

Write-E2eMessage -Message 'Snapshot Release Preservation End-to-End Validation'
Write-E2eMessage -Message '---------------------------------------------------'
Write-E2eMessage -Message 'Goal: Prove Snapshot release checkpoints and GitHub Releases across real Git/GitHub boundaries.'
Write-E2eMessage -Message 'Evidence is separated into migration-reported evidence and independent verification evidence.'
Write-E2eMessage

Assert-E2eCleanupCapability
Import-Module $modulePath -Force -ErrorAction Stop
New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

try {
    $newerFixture = New-E2eSourceFixture -Name "$repositoryPrefix-newer-source" -HeadNewerThanLatestRelease -Confirm:$false
    Invoke-E2eNewDestinationScenario -Fixture $newerFixture

    $headEqualFixture = New-E2eSourceFixture -Name "$repositoryPrefix-head-equal-source" -Confirm:$false
    Invoke-E2eHeadEqualScenario -Fixture $headEqualFixture

    $sameNameFixture = New-E2eSourceFixture -Name "$repositoryPrefix-samename-source" -HeadNewerThanLatestRelease -Confirm:$false
    Invoke-E2eSameNameScenario -Fixture $sameNameFixture

    Write-E2eMessage
    Write-E2eMessage -Message 'Independent verification summary'
    Write-E2eMessage -Message '--------------------------------'
    $scenarioResults | Format-List
}
finally {
    if (-not $KeepRepositories) {
        foreach ($repository in @($createdRepositories) | Select-Object -Unique | Sort-Object -Descending) {
            try {
                $exists = & gh repo view $repository --json nameWithOwner --jq '.nameWithOwner' 2>$null
                if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace([string] $exists)) {
                    Remove-E2eRepository -Repository $repository -Confirm:$false
                }
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
