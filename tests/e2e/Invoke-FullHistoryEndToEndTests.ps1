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
$repositoryPrefix = "copy-github-repo-fullhistory-e2e-$runId"
$createdRepositories = [System.Collections.Generic.List[string]]::new()
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) $repositoryPrefix
$expectedPayload = "fullhistory-lfs-$runId"

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
        throw "Git LFS is required for this FullHistory E2E harness. $message"
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
    if (-not $PSCmdlet.ShouldProcess($fullName, 'Create temporary private FullHistory E2E repository')) {
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

    if (-not $PSCmdlet.ShouldProcess($Repository, 'Delete temporary FullHistory E2E repository')) {
        return
    }

    $output = & gh repo delete $Repository --yes 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = (@($output) | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "Failed to delete E2E repository '$Repository'. $message"
    }
}

function Get-E2eRemoteRef {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Repository
    )

    $module = Get-Module CopyGitHubRepo
    $url = "https://github.com/$Repository.git"
    $result = & $module {
        param($Url)
        Invoke-CgrGitCommand -HostName 'github.com' -ArgumentList @('ls-remote', '--heads', '--tags', $Url)
    } $url

    if ($result.ExitCode -ne 0) {
        throw "Failed to read refs from '$Repository'. $($result.ErrorText)"
    }

    return @($result.Output | ForEach-Object { $_.ToString() } | Sort-Object)
}

function Get-E2eReachableCommitCount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Repository,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ClonePath
    )

    $module = Get-Module CopyGitHubRepo
    $cloneResult = & $module {
        param($Url, $ClonePath)
        Invoke-CgrGitCommand -HostName 'github.com' -ArgumentList @('clone', '--bare', $Url, $ClonePath)
    } "https://github.com/$Repository.git" $ClonePath

    if ($cloneResult.ExitCode -ne 0) {
        throw "Failed to clone '$Repository' for commit-count verification. $($cloneResult.ErrorText)"
    }

    $count = Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('-C', $ClonePath, 'rev-list', '--all', '--count')
    return [int] ([string] @($count)[0])
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
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('config', 'user.name', 'Copy GitHub Repo FullHistory E2E') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('config', 'user.email', 'copy-github-repo-fullhistory-e2e@users.noreply.github.com') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('lfs', 'install', '--local') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('lfs', 'track', '*.bin') -WorkingDirectory $sourcePath | Out-Null

    Set-Content -LiteralPath (Join-Path $sourcePath 'README.md') -Value '# FullHistory E2E Fixture' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $sourcePath 'payload.bin') -Value $expectedPayload -Encoding utf8NoBOM
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('add', '.gitattributes', 'README.md', 'payload.bin') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('commit', '-m', 'Initial FullHistory fixture') -WorkingDirectory $sourcePath | Out-Null

    Set-Content -LiteralPath (Join-Path $sourcePath 'second.txt') -Value 'second-main-commit' -Encoding utf8NoBOM
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('add', 'second.txt') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('commit', '-m', 'Second main commit') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('tag', '-a', 'v1.0.0', '-m', 'FullHistory E2E annotated tag') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('switch', '-c', 'feature/history-check') -WorkingDirectory $sourcePath | Out-Null
    Set-Content -LiteralPath (Join-Path $sourcePath 'feature.txt') -Value 'feature-branch-commit' -Encoding utf8NoBOM
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('add', 'feature.txt') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('commit', '-m', 'Feature branch commit') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('switch', 'main') -WorkingDirectory $sourcePath | Out-Null

    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('remote', 'add', 'origin', "https://github.com/$sourceRepository.git") -WorkingDirectory $sourcePath | Out-Null

    $module = Get-Module CopyGitHubRepo
    $pushBranches = & $module {
        param($LocalPath, $Url)
        Invoke-CgrGitCommand -HostName 'github.com' -ArgumentList @('-C', $LocalPath, 'push', '-u', $Url, '--all')
    } $sourcePath "https://github.com/$sourceRepository.git"
    if ($pushBranches.ExitCode -ne 0) {
        throw "Failed to push source branches. $($pushBranches.ErrorText)"
    }

    $pushTags = & $module {
        param($LocalPath, $Url)
        Invoke-CgrGitCommand -HostName 'github.com' -ArgumentList @('-C', $LocalPath, 'push', $Url, '--tags')
    } $sourcePath "https://github.com/$sourceRepository.git"
    if ($pushTags.ExitCode -ne 0) {
        throw "Failed to push source tags. $($pushTags.ErrorText)"
    }

    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('lfs', 'push', '--all', 'origin') -WorkingDirectory $sourcePath | Out-Null

    $setSourceDefaultBranch = & gh api --hostname github.com -X PATCH "repos/$sourceRepository" -f 'default_branch=main' 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = (@($setSourceDefaultBranch) | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "Failed to establish source default branch 'main'. $message"
    }

    $sourceDefaultBranch = (& gh repo view $sourceRepository --json defaultBranchRef --jq '.defaultBranchRef.name').Trim()
    if ($LASTEXITCODE -ne 0 -or $sourceDefaultBranch -ne 'main') {
        throw "Source default branch fixture mismatch. Expected 'main' but found '$sourceDefaultBranch'."
    }

    $sourceRefsBefore = Get-E2eRemoteRef -Repository $sourceRepository
    $sourceCommitCount = Get-E2eReachableCommitCount -Repository $sourceRepository -ClonePath (Join-Path $tempRoot 'source-count.git')

    $result = Copy-GitHubRepository `
        -SourceRepository $sourceRepository `
        -DestinationRepository $destinationRepository `
        -ContentMode FullHistory `
        -SkipSettings `
        -NonInteractive `
        -Force

    if (-not $result.IsVerified) {
        throw 'FullHistory execution did not report successful verification.'
    }

    $verification = Test-GitHubRepositoryMigration `
        -SourceRepository $sourceRepository `
        -DestinationRepository $destinationRepository `
        -ContentMode FullHistory

    if (-not $verification.IsSuccessful) {
        throw 'Independent FullHistory verification did not report success.'
    }

    $destinationRefs = Get-E2eRemoteRef -Repository $destinationRepository
    if (($sourceRefsBefore -join "`n") -ne ($destinationRefs -join "`n")) {
        throw 'Source and destination branch/tag refs do not match after FullHistory migration.'
    }

    $destinationCommitCount = Get-E2eReachableCommitCount -Repository $destinationRepository -ClonePath (Join-Path $tempRoot 'destination-count.git')
    if ($destinationCommitCount -ne $sourceCommitCount) {
        throw "Reachable commit count mismatch. Source=$sourceCommitCount Destination=$destinationCommitCount"
    }

    $destinationDefaultBranch = (& gh repo view $destinationRepository --json defaultBranchRef --jq '.defaultBranchRef.name').Trim()
    if ($LASTEXITCODE -ne 0 -or $destinationDefaultBranch -ne $sourceDefaultBranch) {
        throw "Destination default branch mismatch. Expected '$sourceDefaultBranch' but found '$destinationDefaultBranch'."
    }

    $destinationClonePath = Join-Path $tempRoot 'destination-worktree'
    $cloneDestination = & $module {
        param($Url, $ClonePath)
        Invoke-CgrGitCommand -HostName 'github.com' -ArgumentList @('clone', $Url, $ClonePath)
    } "https://github.com/$destinationRepository.git" $destinationClonePath
    if ($cloneDestination.ExitCode -ne 0) {
        throw "Failed to clone destination for LFS verification. $($cloneDestination.ErrorText)"
    }

    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('lfs', 'pull') -WorkingDirectory $destinationClonePath | Out-Null
    $actualPayload = [System.IO.File]::ReadAllText((Join-Path $destinationClonePath 'payload.bin')).TrimEnd("`r", "`n")
    if ($actualPayload -ne $expectedPayload) {
        throw "Destination LFS payload mismatch. Expected '$expectedPayload' but found '$actualPayload'."
    }

    [pscustomobject] @{
        Scenario = 'Successful FullHistory migration'
        SourceRepository = $sourceRepository
        DestinationRepository = $destinationRepository
        Verified = $result.IsVerified
        IndependentVerification = $verification.IsSuccessful
        RefSetPreserved = $true
        ReachableCommitCount = $sourceCommitCount
        DefaultBranchPreserved = $destinationDefaultBranch -eq $sourceDefaultBranch
        AnnotatedTagPreserved = $null -ne ($destinationRefs -match 'refs/tags/v1.0.0')
        FeatureBranchPreserved = $null -ne ($destinationRefs -match 'refs/heads/feature/history-check')
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
        Write-Warning "FullHistory E2E repositories were retained because -KeepRepositories was supplied: $(@($createdRepositories) -join ', ')"
    }

    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}