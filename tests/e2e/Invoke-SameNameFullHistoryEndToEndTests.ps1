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
$repositoryPrefix = "copy-github-repo-samename-fullhistory-e2e-$runId"
$sourceName = "$repositoryPrefix-source"
$archiveName = "$sourceName-archive"
$sourceRepository = "$Owner/$sourceName"
$archiveRepository = "$Owner/$archiveName"
$createdRepositories = [System.Collections.Generic.List[string]]::new()
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) $repositoryPrefix
$expectedPayload = "same-name-fullhistory-lfs-$runId"

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
        throw "The authenticated GitHub token does not advertise the 'delete_repo' scope required for automatic E2E cleanup."
    }
}

function Assert-GitLfsAvailable {
    [CmdletBinding()]
    param()

    $result = & git lfs version 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = (@($result) | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "Git LFS is required for this same-name FullHistory E2E harness. $message"
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
    if (-not $PSCmdlet.ShouldProcess($fullName, 'Create temporary private same-name FullHistory E2E repository')) {
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

    if (-not $PSCmdlet.ShouldProcess($Repository, 'Delete temporary same-name FullHistory E2E repository')) {
        return
    }

    $output = & gh repo delete $Repository --yes 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = (@($output) | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        if ($message -match '(?i)not found|could not resolve') {
            return
        }
        throw "Failed to delete E2E repository '$Repository'. $message"
    }
}

function Get-E2eFullHistoryIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Repository
    )

    $module = Get-Module CopyGitHubRepo
    if (-not $module) {
        throw 'CopyGitHubRepo module is not loaded.'
    }

    return & $module {
        param($Repository)
        $repositoryObject = Get-CgrRepository -Repository $Repository -HostName 'github.com'
        Get-CgrRepositoryFullHistoryIdentity -Repository $repositoryObject
    } $Repository
}

function Assert-E2eIdentityMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Expected,

        [Parameter(Mandatory)]
        [psobject] $Actual,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Label
    )

    if ($Actual.DefaultBranch -cne $Expected.DefaultBranch) {
        throw "$Label default branch mismatch. Expected '$($Expected.DefaultBranch)' but found '$($Actual.DefaultBranch)'."
    }
    if (($Actual.Refs -join "`n") -cne ($Expected.Refs -join "`n")) {
        throw "$Label branch/tag ref identity mismatch."
    }
    if ($Actual.ReachableCommitCount -ne $Expected.ReachableCommitCount) {
        throw "$Label reachable commit count mismatch. Expected $($Expected.ReachableCommitCount) but found $($Actual.ReachableCommitCount)."
    }
    if (($Actual.BranchTrees -join "`n") -cne ($Expected.BranchTrees -join "`n")) {
        throw "$Label branch-tip tree identity mismatch."
    }
    if (-not $Actual.GitLfsObjectsAvailable) {
        throw "$Label Git LFS objects were not available."
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
    New-E2eRepository -Name $sourceName -Confirm:$false | Out-Null
    $createdRepositories.Add($archiveRepository)

    $sourcePath = Join-Path $tempRoot 'source'
    New-Item -Path $sourcePath -ItemType Directory -Force | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('init', '-b', 'main') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('config', 'user.name', 'Copy GitHub Repo Same-Name FullHistory E2E') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('config', 'user.email', 'copy-github-repo-samename-fullhistory-e2e@users.noreply.github.com') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('lfs', 'install', '--local') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('lfs', 'track', '*.bin') -WorkingDirectory $sourcePath | Out-Null

    Set-Content -LiteralPath (Join-Path $sourcePath 'README.md') -Value '# Same-Name FullHistory E2E Fixture' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $sourcePath 'payload.bin') -Value $expectedPayload -Encoding utf8NoBOM
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('add', '.gitattributes', 'README.md', 'payload.bin') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('commit', '-m', 'Initial same-name FullHistory fixture') -WorkingDirectory $sourcePath | Out-Null

    Set-Content -LiteralPath (Join-Path $sourcePath 'second.txt') -Value 'second-main-commit' -Encoding utf8NoBOM
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('add', 'second.txt') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('commit', '-m', 'Second main commit') -WorkingDirectory $sourcePath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('tag', '-a', 'v1.0.0', '-m', 'Same-name FullHistory annotated tag') -WorkingDirectory $sourcePath | Out-Null

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
    Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @('api', '-X', 'PATCH', "repos/$sourceRepository", '-f', 'default_branch=main') | Out-Null

    $sourceDefaultBranch = (& gh repo view $sourceRepository --json defaultBranchRef --jq '.defaultBranchRef.name').Trim()
    if ($LASTEXITCODE -ne 0 -or $sourceDefaultBranch -cne 'main') {
        throw "Source default branch setup failed. Expected 'main' but found '$sourceDefaultBranch'."
    }

    $sourceIdentity = Get-E2eFullHistoryIdentity -Repository $sourceRepository
    $exactConfirmation = "SOURCE=$sourceRepository;ARCHIVE=$archiveRepository;REPLACEMENT=$sourceRepository"

    $result = Copy-GitHubRepository `
        -SourceRepository $sourceRepository `
        -DestinationRepository $sourceRepository `
        -ArchiveRepositoryName $archiveName `
        -ContentMode FullHistory `
        -SameNameConfirmation $exactConfirmation `
        -SkipSettings `
        -NonInteractive `
        -Force

    if (-not $result.IsVerified) {
        throw 'Same-name FullHistory execution did not report successful verification.'
    }
    if ($result.ArchiveRepository -cne $archiveRepository) {
        throw "Same-name FullHistory result archive '$($result.ArchiveRepository)' did not match '$archiveRepository'."
    }

    $archiveIdentity = Get-E2eFullHistoryIdentity -Repository $archiveRepository
    $replacementIdentity = Get-E2eFullHistoryIdentity -Repository $sourceRepository
    Assert-E2eIdentityMatch -Expected $sourceIdentity -Actual $archiveIdentity -Label 'Archive'
    Assert-E2eIdentityMatch -Expected $sourceIdentity -Actual $replacementIdentity -Label 'Replacement'

    $verification = Test-GitHubRepositoryMigration `
        -SourceRepository $archiveRepository `
        -DestinationRepository $sourceRepository `
        -ContentMode FullHistory
    if (-not $verification.IsSuccessful) {
        throw 'Independent archive-to-replacement FullHistory verification did not report success.'
    }

    $destinationClonePath = Join-Path $tempRoot 'replacement-worktree'
    $cloneDestination = & $module {
        param($Url, $ClonePath)
        Invoke-CgrGitCommand -HostName 'github.com' -ArgumentList @('clone', $Url, $ClonePath)
    } "https://github.com/$sourceRepository.git" $destinationClonePath
    if ($cloneDestination.ExitCode -ne 0) {
        throw "Failed to clone same-name FullHistory replacement. $($cloneDestination.ErrorText)"
    }

    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('lfs', 'pull') -WorkingDirectory $destinationClonePath | Out-Null
    $actualPayload = [System.IO.File]::ReadAllText((Join-Path $destinationClonePath 'payload.bin')).TrimEnd("`r", "`n")
    if ($actualPayload -cne $expectedPayload) {
        throw "Replacement LFS payload mismatch. Expected '$expectedPayload' but found '$actualPayload'."
    }

    [pscustomobject] @{
        Scenario = 'Successful same-name FullHistory replacement'
        SourceRepository = $sourceRepository
        ArchiveRepository = $archiveRepository
        ReplacementRepository = $sourceRepository
        Verified = $result.IsVerified
        IndependentVerification = $verification.IsSuccessful
        ArchiveIdentityPreserved = $true
        ReplacementIdentityMatches = $true
        ReachableCommitCount = $sourceIdentity.ReachableCommitCount
        DefaultBranchPreserved = $true
        AnnotatedTagPreserved = [bool] ($replacementIdentity.Refs -match 'refs/tags/v1.0.0')
        FeatureBranchPreserved = [bool] ($replacementIdentity.Refs -match 'refs/heads/feature/history-check')
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
        Write-Warning "Same-name FullHistory E2E repositories were retained because -KeepRepositories was supplied: $(@($createdRepositories) -join ', ')"
    }

    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}