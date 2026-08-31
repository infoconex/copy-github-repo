#requires -Version 7.4

[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string] $Owner = 'infoconex',

    [switch] $KeepRepositories,

    [switch] $SkipLfs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
$runId = [guid]::NewGuid().ToString('N').Substring(0, 10)
$prefix = "copy-github-repo-demo-$runId"
$sourceRepository = "$Owner/$prefix-source"
$destinationRepository = "$Owner/$prefix-destination"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) $prefix
$sourcePath = Join-Path $tempRoot 'source'
$destinationPath = Join-Path $tempRoot 'destination'
$reportPath = Join-Path $tempRoot 'publication-report.json'
$createdRepositories = [System.Collections.Generic.List[string]]::new()

function Invoke-DemoNativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $FilePath,
        [Parameter(Mandatory)] [string[]] $ArgumentList,
        [string] $WorkingDirectory
    )

    $original = Get-Location
    try {
        if ($WorkingDirectory) { Set-Location -LiteralPath $WorkingDirectory }
        $output = & $FilePath @ArgumentList 2>&1
        $exitCode = if ($null -ne $global:LASTEXITCODE) { $global:LASTEXITCODE } else { 0 }
        if ($exitCode -ne 0) {
            throw "$FilePath failed with exit code $exitCode. $((@($output) | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)"
        }
        return @($output)
    }
    finally { Set-Location -LiteralPath $original }
}

function Assert-DemoCleanupCapability {
    if ($KeepRepositories) { return }
    $headers = & gh api --include user 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect GitHub token scopes before creating demonstration repositories.' }
    $scopeLine = @($headers | ForEach-Object { $_.ToString() }) | Where-Object { $_ -match '^(?i)x-oauth-scopes:\s*' } | Select-Object -First 1
    if (-not $scopeLine) { throw 'Unable to prove delete_repo capability. Use -KeepRepositories only when deliberate manual cleanup is acceptable.' }
    $scopes = ($scopeLine -replace '^(?i)x-oauth-scopes:\s*', '').Split(',') | ForEach-Object { $_.Trim() }
    if ($scopes -notcontains 'delete_repo') { throw 'The GitHub token does not advertise delete_repo. Refresh auth with delete_repo or rerun with -KeepRepositories.' }
}

function New-DemoRepository {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'This test-only helper is guarded by a run-specific repository prefix and is called only by the explicit live demonstration script.'
    )]
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Repository)

    if (-not $Repository.StartsWith("$Owner/$prefix-", [System.StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to create repository outside protected prefix '$Owner/$prefix-*'." }
    Invoke-DemoNativeCommand -FilePath gh -ArgumentList @('repo', 'create', $Repository, '--public') | Out-Null
    $createdRepositories.Add($Repository)
}

function Remove-DemoRepository {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'This test-only cleanup helper deletes only repositories created under the run-specific protected prefix.'
    )]
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Repository)

    if (-not $Repository.StartsWith("$Owner/$prefix-", [System.StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to delete repository outside protected prefix '$Owner/$prefix-*'." }
    Invoke-DemoNativeCommand -FilePath gh -ArgumentList @('repo', 'delete', $Repository, '--yes') | Out-Null
}

function Push-DemoRepository {
    param([Parameter(Mandatory)] [string] $Repository, [Parameter(Mandatory)] [string] $Path)
    $module = Get-Module CopyGitHubRepo
    $result = & $module {
        param($Url, $Path)
        Invoke-CgrGitCommand -HostName github.com -ArgumentList @('-C', $Path, 'push', '--all', $Url)
    } "https://github.com/$Repository.git" $Path
    if ($result.ExitCode -ne 0) { throw "Failed to push branches to '$Repository'. $($result.ErrorText)" }
    $tagResult = & $module {
        param($Url, $Path)
        Invoke-CgrGitCommand -HostName github.com -ArgumentList @('-C', $Path, 'push', '--tags', $Url)
    } "https://github.com/$Repository.git" $Path
    if ($tagResult.ExitCode -ne 0) { throw "Failed to push tags to '$Repository'. $($tagResult.ErrorText)" }
}

if ($Owner -notmatch '^[A-Za-z0-9_.-]+$') { throw "Owner '$Owner' is not valid." }

Assert-DemoCleanupCapability
Import-Module $modulePath -Force -ErrorAction Stop
New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

try {
    New-DemoRepository -Repository $sourceRepository

    New-Item -Path $sourcePath -ItemType Directory -Force | Out-Null
    Invoke-DemoNativeCommand -FilePath git -ArgumentList @('init', '-b', 'main') -WorkingDirectory $sourcePath | Out-Null
    Invoke-DemoNativeCommand -FilePath git -ArgumentList @('config', 'user.name', 'Copy GitHub Repo Demo') -WorkingDirectory $sourcePath | Out-Null
    Invoke-DemoNativeCommand -FilePath git -ArgumentList @('config', 'user.email', 'copy-github-repo-demo@users.noreply.github.com') -WorkingDirectory $sourcePath | Out-Null

    Set-Content (Join-Path $sourcePath 'README.md') "# Clean Snapshot Demonstration`n" -Encoding utf8NoBOM
    Invoke-DemoNativeCommand -FilePath git -ArgumentList @('add', 'README.md') -WorkingDirectory $sourcePath | Out-Null
    Invoke-DemoNativeCommand -FilePath git -ArgumentList @('commit', '-m', 'Start development history') -WorkingDirectory $sourcePath | Out-Null

    New-Item -Path (Join-Path $sourcePath 'src') -ItemType Directory -Force | Out-Null
    Set-Content (Join-Path $sourcePath 'src/app.txt') 'version 1' -Encoding utf8NoBOM
    Invoke-DemoNativeCommand -FilePath git -ArgumentList @('add', 'src/app.txt') -WorkingDirectory $sourcePath | Out-Null
    Invoke-DemoNativeCommand -FilePath git -ArgumentList @('commit', '-m', 'Add application') -WorkingDirectory $sourcePath | Out-Null
    Invoke-DemoNativeCommand -FilePath git -ArgumentList @('tag', 'v0.0.1') -WorkingDirectory $sourcePath | Out-Null

    Invoke-DemoNativeCommand -FilePath git -ArgumentList @('switch', '-c', 'feature/history-only') -WorkingDirectory $sourcePath | Out-Null
    Set-Content (Join-Path $sourcePath 'feature.txt') 'This branch must not appear in the Snapshot destination.' -Encoding utf8NoBOM
    Invoke-DemoNativeCommand -FilePath git -ArgumentList @('add', 'feature.txt') -WorkingDirectory $sourcePath | Out-Null
    Invoke-DemoNativeCommand -FilePath git -ArgumentList @('commit', '-m', 'Add feature branch history') -WorkingDirectory $sourcePath | Out-Null
    Invoke-DemoNativeCommand -FilePath git -ArgumentList @('switch', 'main') -WorkingDirectory $sourcePath | Out-Null

    Add-Content (Join-Path $sourcePath 'README.md') 'Current release-ready state.' -Encoding utf8NoBOM
    Invoke-DemoNativeCommand -FilePath git -ArgumentList @('add', 'README.md') -WorkingDirectory $sourcePath | Out-Null
    Invoke-DemoNativeCommand -FilePath git -ArgumentList @('commit', '-m', 'Prepare release-ready state') -WorkingDirectory $sourcePath | Out-Null

    $lfsIncluded = $false
    if (-not $SkipLfs) {
        & git lfs version *> $null
        if ($LASTEXITCODE -eq 0) {
            Invoke-DemoNativeCommand -FilePath git -ArgumentList @('lfs', 'install', '--local') -WorkingDirectory $sourcePath | Out-Null
            Invoke-DemoNativeCommand -FilePath git -ArgumentList @('lfs', 'track', '*.bin') -WorkingDirectory $sourcePath | Out-Null
            Set-Content (Join-Path $sourcePath 'fixture.bin') 'CopyGitHubRepo demonstration LFS payload' -Encoding utf8NoBOM
            Invoke-DemoNativeCommand -FilePath git -ArgumentList @('add', '.gitattributes', 'fixture.bin') -WorkingDirectory $sourcePath | Out-Null
            Invoke-DemoNativeCommand -FilePath git -ArgumentList @('commit', '-m', 'Add LFS fixture') -WorkingDirectory $sourcePath | Out-Null
            $lfsIncluded = $true
        }
    }

    Push-DemoRepository -Repository $sourceRepository -Path $sourcePath

    Invoke-DemoNativeCommand -FilePath gh -ArgumentList @('repo', 'edit', $sourceRepository, '--description', 'Clean Snapshot demonstration source', '--homepage', 'https://example.invalid/copy-github-repo-demo', '--enable-issues', '--enable-wiki') | Out-Null
    $topics = @{ names = @('powershell', 'github', 'snapshot-demo') } | ConvertTo-Json -Compress
    $topicsFile = Join-Path $tempRoot 'topics.json'
    Set-Content -LiteralPath $topicsFile -Value $topics -Encoding utf8NoBOM
    Invoke-DemoNativeCommand -FilePath gh -ArgumentList @('api', '-X', 'PUT', "repos/$sourceRepository/topics", '--input', $topicsFile) | Out-Null

    $milestoneJson = @{ title = 'Demo milestone'; description = 'Historical record that must not migrate.' } | ConvertTo-Json -Compress
    $milestoneFile = Join-Path $tempRoot 'milestone.json'
    Set-Content -LiteralPath $milestoneFile -Value $milestoneJson -Encoding utf8NoBOM
    Invoke-DemoNativeCommand -FilePath gh -ArgumentList @('api', '-X', 'POST', "repos/$sourceRepository/milestones", '--input', $milestoneFile) | Out-Null

    Invoke-DemoNativeCommand -FilePath gh -ArgumentList @('issue', 'create', '--repo', $sourceRepository, '--title', 'Historical development issue', '--body', 'This issue must not appear in the Snapshot destination.', '--milestone', 'Demo milestone') | Out-Null
    Invoke-DemoNativeCommand -FilePath gh -ArgumentList @('pr', 'create', '--repo', $sourceRepository, '--head', 'feature/history-only', '--base', 'main', '--title', 'Historical development pull request', '--body', 'This pull request must not appear in the Snapshot destination.') | Out-Null

    $sourceCommitCount = [int](Invoke-DemoNativeCommand -FilePath git -ArgumentList @('rev-list', '--count', 'main') -WorkingDirectory $sourcePath | Select-Object -First 1)
    $sourceTree = [string](Invoke-DemoNativeCommand -FilePath git -ArgumentList @('rev-parse', 'main^{tree}') -WorkingDirectory $sourcePath | Select-Object -First 1)
    $sourceBranches = @(Invoke-DemoNativeCommand -FilePath git -ArgumentList @('for-each-ref', '--format=%(refname:short)', 'refs/heads') -WorkingDirectory $sourcePath)
    $sourceTags = @(Invoke-DemoNativeCommand -FilePath git -ArgumentList @('tag', '--list') -WorkingDirectory $sourcePath)

    $createdRepositories.Add($destinationRepository)
    $result = Copy-GitHubRepository -SourceRepository $sourceRepository -DestinationRepository $destinationRepository -ReportPath $reportPath -NonInteractive -Force
    if (-not $result.IsVerified) { throw 'Clean Snapshot migration verification failed.' }

    $module = Get-Module CopyGitHubRepo
    $cloneResult = & $module {
        param($Url, $Path)
        Invoke-CgrGitCommand -HostName github.com -ArgumentList @('clone', $Url, $Path)
    } "https://github.com/$destinationRepository.git" $destinationPath
    if ($cloneResult.ExitCode -ne 0) { throw "Failed to clone destination. $($cloneResult.ErrorText)" }

    $destinationCommitCount = [int](Invoke-DemoNativeCommand -FilePath git -ArgumentList @('rev-list', '--count', 'main') -WorkingDirectory $destinationPath | Select-Object -First 1)
    $destinationTree = [string](Invoke-DemoNativeCommand -FilePath git -ArgumentList @('rev-parse', 'main^{tree}') -WorkingDirectory $destinationPath | Select-Object -First 1)
    $destinationBranches = @(Invoke-DemoNativeCommand -FilePath git -ArgumentList @('for-each-ref', '--format=%(refname:short)', 'refs/heads') -WorkingDirectory $destinationPath)
    $destinationTags = @(Invoke-DemoNativeCommand -FilePath git -ArgumentList @('tag', '--list') -WorkingDirectory $destinationPath)

    $destinationIssues = @(gh issue list --repo $destinationRepository --state all --json number | ConvertFrom-Json)
    $destinationPrs = @(gh pr list --repo $destinationRepository --state all --json number | ConvertFrom-Json)
    $destinationMilestones = @((gh api "repos/$destinationRepository/milestones?state=all" | ConvertFrom-Json))

    if ($sourceCommitCount -le 1) { throw 'Demonstration source did not contain meaningful history.' }
    if ($destinationCommitCount -ne 1) { throw "Expected one destination commit but found $destinationCommitCount." }
    if ($sourceTree -ne $destinationTree) { throw 'Source and destination tree SHAs differ.' }
    if ($destinationBranches -contains 'feature/history-only') { throw 'Historical feature branch was copied unexpectedly.' }
    if (@($destinationTags).Count -ne 0) { throw 'Historical tags were copied unexpectedly.' }
    if (@($destinationIssues).Count -ne 0 -or @($destinationPrs).Count -ne 0 -or @($destinationMilestones).Count -ne 0) { throw 'Historical GitHub records were copied unexpectedly.' }

    [pscustomobject] @{
        SourceRepository = $sourceRepository
        DestinationRepository = $destinationRepository
        SourceCommitCount = $sourceCommitCount
        DestinationCommitCount = $destinationCommitCount
        SourceTreeSha = $sourceTree
        DestinationTreeSha = $destinationTree
        SourceBranches = $sourceBranches
        DestinationBranches = $destinationBranches
        SourceTags = $sourceTags
        DestinationTags = $destinationTags
        DestinationIssueCount = @($destinationIssues).Count
        DestinationPullRequestCount = @($destinationPrs).Count
        DestinationMilestoneCount = @($destinationMilestones).Count
        LfsIncluded = $lfsIncluded
        SettingsVerified = $result.SettingsRestored
        ProtectionVerified = $result.ProtectionRestored
        ProvenanceRecorded = $null -ne $result.Provenance
        ReportPath = $reportPath
    } | Format-List
}
finally {
    if (-not $KeepRepositories) {
        foreach ($repository in @($createdRepositories) | Select-Object -Unique | Sort-Object -Descending) {
            try { Remove-DemoRepository -Repository $repository }
            catch { Write-Warning "Failed to clean up demonstration repository '$repository'. $($_.Exception.Message)" }
        }
    }
    else { Write-Warning "Demonstration repositories retained: $(@($createdRepositories) -join ', ')" }

    if (-not $KeepRepositories) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
