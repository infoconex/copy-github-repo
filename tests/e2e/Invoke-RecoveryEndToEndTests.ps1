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
$repositoryPrefix = "copy-github-repo-recovery-e2e-$runId"
$createdRepositories = [System.Collections.Generic.List[string]]::new()
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) $repositoryPrefix
$sourcePath = Join-Path $tempRoot 'source'
$reportPath = Join-Path $tempRoot 'migration-report.json'

function Invoke-RecoveryE2eNativeCommand {
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

function Assert-RecoveryE2eCleanupCapability {
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

function New-RecoveryE2eRepository {
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
    if (-not $PSCmdlet.ShouldProcess($fullName, 'Create temporary private recovery E2E repository')) {
        return $null
    }

    Invoke-RecoveryE2eNativeCommand -FilePath 'gh' -ArgumentList @('repo', 'create', $fullName, '--private') | Out-Null
    $createdRepositories.Add($fullName)
    return $fullName
}

function Remove-RecoveryE2eRepository {
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

    if (-not $PSCmdlet.ShouldProcess($Repository, 'Delete temporary recovery E2E repository')) {
        return
    }

    $output = & gh repo delete $Repository --yes 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = (@($output) | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "Failed to delete recovery E2E repository '$Repository'. $message"
    }
}

function Publish-RecoveryE2eSourceRepository {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Repository
    )

    New-Item -Path $sourcePath -ItemType Directory -Force | Out-Null
    Invoke-RecoveryE2eNativeCommand -FilePath 'git' -ArgumentList @('init', '-b', 'main') -WorkingDirectory $sourcePath | Out-Null
    Invoke-RecoveryE2eNativeCommand -FilePath 'git' -ArgumentList @('config', 'user.name', 'Copy GitHub Repo Recovery E2E') -WorkingDirectory $sourcePath | Out-Null
    Invoke-RecoveryE2eNativeCommand -FilePath 'git' -ArgumentList @('config', 'user.email', 'copy-github-repo-recovery-e2e@users.noreply.github.com') -WorkingDirectory $sourcePath | Out-Null

    Set-Content -LiteralPath (Join-Path $sourcePath '.gitattributes') -Value '*.bin filter=lfs diff=lfs merge=lfs -text' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $sourcePath 'README.md') -Value '# Recovery E2E Fixture' -Encoding utf8NoBOM
    Invoke-RecoveryE2eNativeCommand -FilePath 'git' -ArgumentList @('add', '.gitattributes', 'README.md') -WorkingDirectory $sourcePath | Out-Null

    $missingOid = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    $pointerText = "version https://git-lfs.github.com/spec/v1`noid sha256:$missingOid`nsize 123`n"
    $pointerBlob = $pointerText | & git -C $sourcePath hash-object -w --stdin
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string] $pointerBlob)) {
        throw 'Failed to create the missing-object Git LFS pointer fixture.'
    }

    Invoke-RecoveryE2eNativeCommand `
        -FilePath 'git' `
        -ArgumentList @('update-index', '--add', '--cacheinfo', "100644,$pointerBlob,payload.bin") `
        -WorkingDirectory $sourcePath | Out-Null
    Invoke-RecoveryE2eNativeCommand -FilePath 'git' -ArgumentList @('commit', '-m', 'Create missing LFS object fixture') -WorkingDirectory $sourcePath | Out-Null
    Invoke-RecoveryE2eNativeCommand -FilePath 'git' -ArgumentList @('remote', 'add', 'origin', "https://github.com/$Repository.git") -WorkingDirectory $sourcePath | Out-Null

    $module = Get-Module CopyGitHubRepo
    if (-not $module) {
        throw 'CopyGitHubRepo module is not loaded.'
    }

    $pushResult = & $module {
        param($RepositoryUrl, $LocalPath)
        Invoke-CgrGitCommand -HostName 'github.com' -ArgumentList @('-C', $LocalPath, 'push', '-u', $RepositoryUrl, 'main')
    } "https://github.com/$Repository.git" $sourcePath

    if ($pushResult.ExitCode -ne 0) {
        throw "Failed to publish recovery E2E source '$Repository'. $($pushResult.ErrorText)"
    }
}

if ($Owner -notmatch '^[A-Za-z0-9_.-]+$') {
    throw "Owner '$Owner' is not valid."
}

Assert-RecoveryE2eCleanupCapability
Import-Module $modulePath -Force -ErrorAction Stop
New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

$sourceRepository = "$Owner/$repositoryPrefix-source"
$destinationRepository = "$Owner/$repositoryPrefix-destination"

try {
    New-RecoveryE2eRepository -Name "$repositoryPrefix-source" -Confirm:$false | Out-Null
    Publish-RecoveryE2eSourceRepository -Repository $sourceRepository
    $createdRepositories.Add($destinationRepository)

    $caughtError = $null
    try {
        Copy-GitHubRepository `
            -SourceRepository $sourceRepository `
            -DestinationRepository $destinationRepository `
            -SkipSettings `
            -NonInteractive `
            -Force `
            -ReportPath $reportPath | Out-Null
    }
    catch {
        $caughtError = $_
    }

    if ($null -eq $caughtError) {
        throw 'Recovery E2E expected snapshot migration to fail because the source Git LFS object is intentionally missing.'
    }

    $recoveryReportPath = "$reportPath.recovery.json"
    if (-not (Test-Path -LiteralPath $recoveryReportPath)) {
        throw "Recovery E2E did not create the expected recovery report '$recoveryReportPath'."
    }

    $recovery = Get-Content -LiteralPath $recoveryReportPath -Raw | ConvertFrom-Json
    if ($recovery.Status -ne 'FailedAfterDestinationCreation') {
        throw "Unexpected recovery status '$($recovery.Status)'."
    }
    if ($recovery.FailureStage -ne 'CopySnapshot') {
        throw "Unexpected recovery failure stage '$($recovery.FailureStage)'."
    }
    if ($recovery.ErrorId -notmatch 'SourceGitLfsFetchFailed') {
        throw "Unexpected recovery error ID '$($recovery.ErrorId)'."
    }
    if (-not $recovery.Recovery.DestinationWasCreated) {
        throw 'Recovery report did not record that the destination repository was created.'
    }
    if ($recovery.Recovery.AutomaticDeletionAttempted) {
        throw 'Recovery report incorrectly indicates that automatic deletion was attempted.'
    }
    if ($recovery.Recovery.SourceRepositoryMutated) {
        throw 'Recovery report incorrectly indicates that the source repository was mutated.'
    }
    if (@($recovery.CompletedSteps).Count -ne 1 -or @($recovery.CompletedSteps)[0].Name -ne 'CreateDestinationRepository') {
        throw 'Recovery report did not record the expected completed-step boundary.'
    }

    [pscustomobject] @{
        Scenario = 'Missing Git LFS object recovery'
        SourceRepository = $sourceRepository
        DestinationRepository = $destinationRepository
        ExpectedFailureObserved = $true
        ErrorId = $recovery.ErrorId
        FailureStage = $recovery.FailureStage
        RecoveryReport = $recoveryReportPath
        DestinationWasCreated = $recovery.Recovery.DestinationWasCreated
        AutomaticDeletionAttempted = $recovery.Recovery.AutomaticDeletionAttempted
    } | Format-List
}
finally {
    if (-not $KeepRepositories) {
        foreach ($repository in @($createdRepositories) | Select-Object -Unique | Sort-Object -Descending) {
            try {
                Remove-RecoveryE2eRepository -Repository $repository -Confirm:$false
            }
            catch {
                Write-Warning "Failed to clean up recovery E2E repository '$repository'. $($_.Exception.Message)"
            }
        }
    }
    else {
        Write-Warning "Recovery E2E repositories were retained because -KeepRepositories was supplied: $(@($createdRepositories) -join ', ')"
    }

    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
