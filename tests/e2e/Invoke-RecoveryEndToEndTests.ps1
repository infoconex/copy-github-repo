#requires -Version 7.4

[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string] $Owner = 'infoconex',

    [switch] $KeepRepositories,

    [ValidateNotNullOrEmpty()]
    [string] $EvidenceDirectory,

    [switch] $SafeSubsetOnly,

    # Optional fault after real verified GitHub archive/replace, before final
    # success report. Not a simulation of failed Snapshot transfer or settings.
    [switch] $ReportWriteFailureProbe,

    # Explicit opt-in: native Git commit-tree failure after real archive
    # and replacement creation, with NO simulated GitHub API outage.
    [switch] $LocalGitCommitFailureProbe
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
$runId = [guid]::NewGuid().ToString('N').Substring(0, 10)
$repositoryPrefix = "copy-github-repo-recovery-e2e-$runId"
$createdRepositories = [System.Collections.Generic.List[string]]::new()
$expectedRepositoryIds = @{}
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) $repositoryPrefix
$sourcePath = Join-Path $tempRoot 'source'
$reportPath = Join-Path $tempRoot 'migration-report.json'
$evidenceRunPath = $null
if ($PSBoundParameters.ContainsKey('EvidenceDirectory')) {
    $evidenceRunPath = [System.IO.Path]::GetFullPath((Join-Path $EvidenceDirectory $repositoryPrefix))
    $temporaryPath = [System.IO.Path]::GetFullPath($tempRoot)
    if ($evidenceRunPath.Equals($temporaryPath, [System.StringComparison]::OrdinalIgnoreCase) -or
        $evidenceRunPath.StartsWith("$temporaryPath$([System.IO.Path]::DirectorySeparatorChar)", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'EvidenceDirectory must keep recovery evidence outside the temporary fixture directory that cleanup deletes.'
    }
    if (Test-Path -LiteralPath $evidenceRunPath) {
        throw "Refusing to overwrite existing recovery E2E evidence directory '$evidenceRunPath'."
    }
}

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
    # Record immutable identity immediately; if readback fails, keep the name
    # registered but never delete a repository without a known exact ID.
    $createdRepositories.Add($fullName)
    $createdRemote = Get-RecoveryE2eRemoteRepository -Repository $fullName
    $expectedRepositoryIds[$fullName] = [string] $createdRemote.id
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

    if (-not $expectedRepositoryIds.ContainsKey($Repository) -or
        [string]::IsNullOrWhiteSpace([string] $expectedRepositoryIds[$Repository])) {
        throw "Refusing to delete '$Repository' without a recorded immutable test-created repository ID."
    }
    $expectedId = [string] $expectedRepositoryIds[$Repository]
    $liveRepository = Get-RecoveryE2eRemoteRepository -Repository $Repository
    if ([string] $liveRepository.id -ne $expectedId) {
        throw "Refusing to delete '$Repository': current GitHub repository ID differs from the exact test fixture ID."
    }

    if (-not $PSCmdlet.ShouldProcess($Repository, 'Delete exact-identity temporary recovery E2E repository')) {
        return
    }

    $output = & gh repo delete $Repository --yes 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = (@($output) | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "Failed to delete recovery E2E repository '$Repository'. $message"
    }
}

function Assert-RecoveryE2eRepositoryAbsent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Repository
    )

    $expectedPrefix = "$Owner/$repositoryPrefix-"
    if (-not $Repository.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to verify cleanup outside the protected E2E prefix '$expectedPrefix'."
    }

    # A nonzero gh exit is not proof of deletion: 401, 403, 429 and transient
    # network failures must never count as independent repository absence.
    $response = @(& gh api --include "repos/$Repository" 2>&1 |
            ForEach-Object { $_.ToString() })
    $statusCodes = @($response | ForEach-Object {
            if ($_ -match '^HTTP/\S+\s+(\d{3})(?:\s|$)') {
                [int] $Matches[1]
            }
        })
    if ($statusCodes.Count -ne 1) {
        throw "Unable to independently verify GitHub HTTP status after cleanup of '$Repository'."
    }
    if ($statusCodes[0] -ne 404) {
        throw "Repository '$Repository' is not verified absent after cleanup (HTTP $($statusCodes[0]))."
    }

    # HTTP 404 is only trustworthy here when the GitHub CLI response confirms
    # the same fully scoped authenticated API access used for fixture creation.
    $scopeLines = @($response | Where-Object { $_ -match '^(?i)x-oauth-scopes:\s*' })
    if ($scopeLines.Count -ne 1) {
        throw "Unable to prove authenticated repository visibility when checking absence of '$Repository'."
    }
    $scopes = ($scopeLines[0] -replace '^(?i)x-oauth-scopes:\s*', '').Split(',') |
        ForEach-Object { $_.Trim() }
    if ($scopes -notcontains 'repo' -or $scopes -notcontains 'delete_repo') {
        throw "Missing authenticated repository visibility or cleanup scope when checking absence of '$Repository'."
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

function Get-RecoveryE2eRemoteRepository {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Repository)

    $json = @(Invoke-RecoveryE2eNativeCommand -FilePath 'gh' -ArgumentList @('api', "repos/$Repository")) -join [Environment]::NewLine
    $remote = $json | ConvertFrom-Json
    if ($remote.full_name -ine $Repository -or $null -eq $remote.id) {
        throw "Remote repository identity readback did not resolve to '$Repository'."
    }
    return $remote
}

function Get-RecoveryE2eRemoteCommit {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Repository)

    $json = @(Invoke-RecoveryE2eNativeCommand -FilePath 'gh' -ArgumentList @('api', "repos/$Repository/commits/main")) -join [Environment]::NewLine
    $commit = $json | ConvertFrom-Json
    if (-not $commit.sha -or -not $commit.commit.tree.sha) {
        throw "Unable to independently read a main branch commit/tree from '$Repository'."
    }
    return $commit
}

function Publish-RecoveryE2ePlainRepository {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Repository,
        [Parameter(Mandatory)][string] $LocalPath,
        [Parameter(Mandatory)][string] $Marker
    )

    New-Item -Path $LocalPath -ItemType Directory -Force | Out-Null
    Invoke-RecoveryE2eNativeCommand -FilePath 'git' -ArgumentList @('init', '-b', 'main') -WorkingDirectory $LocalPath | Out-Null
    Invoke-RecoveryE2eNativeCommand -FilePath 'git' -ArgumentList @('config', 'user.name', 'Copy GitHub Repo Recovery E2E') -WorkingDirectory $LocalPath | Out-Null
    Invoke-RecoveryE2eNativeCommand -FilePath 'git' -ArgumentList @('config', 'user.email', 'copy-github-repo-recovery-e2e@users.noreply.github.com') -WorkingDirectory $LocalPath | Out-Null
    Set-Content -LiteralPath (Join-Path $LocalPath 'README.md') -Value "# $Marker" -Encoding utf8NoBOM
    Invoke-RecoveryE2eNativeCommand -FilePath 'git' -ArgumentList @('add', 'README.md') -WorkingDirectory $LocalPath | Out-Null
    Invoke-RecoveryE2eNativeCommand -FilePath 'git' -ArgumentList @('commit', '-m', 'Prepare isolated E2E fixture') -WorkingDirectory $LocalPath | Out-Null
    Invoke-RecoveryE2eNativeCommand -FilePath 'git' -ArgumentList @('remote', 'add', 'origin', "https://github.com/$Repository.git") -WorkingDirectory $LocalPath | Out-Null

    $module = Get-Module CopyGitHubRepo
    if (-not $module) { throw 'CopyGitHubRepo module is not loaded.' }
    $pushResult = & $module {
        param($RepositoryUrl, $WorkingPath)
        Invoke-CgrGitCommand -HostName 'github.com' -ArgumentList @('-C', $WorkingPath, 'push', '-u', $RepositoryUrl, 'main')
    } "https://github.com/$Repository.git" $LocalPath
    if ($pushResult.ExitCode -ne 0) {
        throw "Failed to push disposable fixture '$Repository'. $($pushResult.ErrorText)"
    }
}

if ($Owner -notmatch '^[A-Za-z0-9_.-]+$') {
    throw "Owner '$Owner' is not valid."
}
if (-not $SafeSubsetOnly) {
    throw 'Full recovery E2E cannot be claimed without a safely reviewed post-mutation fault fixture. Use -SafeSubsetOnly to run only the missing-LFS planning guard and existing-destination happy path; Required-live partial, retry, settings and recovery scenarios remain UNVERIFIED.'
}

Assert-RecoveryE2eCleanupCapability
Import-Module $modulePath -Force -ErrorAction Stop
New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

$sourceRepository = "$Owner/$repositoryPrefix-source"
$destinationRepository = "$Owner/$repositoryPrefix-destination"

try {
    if ($evidenceRunPath) {
        New-Item -Path $evidenceRunPath -ItemType Directory -ErrorAction Stop | Out-Null
    }
    if ($LocalGitCommitFailureProbe) {
        # Fail closed BEFORE creating ANY remote test fixture if this host
        # cannot reliably reproduce the exact native Git failure.
        $dateProbePath = Join-Path $tempRoot 'date-preflight'
        New-Item -ItemType Directory -Path $dateProbePath -ErrorAction Stop | Out-Null
        Invoke-RecoveryE2eNativeCommand -FilePath 'git' -ArgumentList @('init', '-b', 'main') -WorkingDirectory $dateProbePath | Out-Null
        Set-Content -LiteralPath (Join-Path $dateProbePath 'probe.txt') -Value 'Local-only Git date probe' -Encoding utf8NoBOM
        Invoke-RecoveryE2eNativeCommand -FilePath 'git' -ArgumentList @('add', 'probe.txt') -WorkingDirectory $dateProbePath | Out-Null
        $dateProbeTree = @(Invoke-RecoveryE2eNativeCommand -FilePath 'git' -ArgumentList @('write-tree') -WorkingDirectory $dateProbePath)[0]
        $priorAuthor = [Environment]::GetEnvironmentVariable('GIT_AUTHOR_DATE', 'Process')
        $priorCommitter = [Environment]::GetEnvironmentVariable('GIT_COMMITTER_DATE', 'Process')
        $dateProbeError = $null
        try {
            [Environment]::SetEnvironmentVariable('GIT_AUTHOR_DATE', 'not-a-valid-date', 'Process')
            [Environment]::SetEnvironmentVariable('GIT_COMMITTER_DATE', 'not-a-valid-date', 'Process')
            try {
                Invoke-RecoveryE2eNativeCommand -FilePath 'git' -ArgumentList @('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit-tree', $dateProbeTree, '-m', 'Expected native Git failure') -WorkingDirectory $dateProbePath | Out-Null
            }
            catch { $dateProbeError = $_ }
        }
        finally {
            [Environment]::SetEnvironmentVariable('GIT_AUTHOR_DATE', $priorAuthor, 'Process')
            [Environment]::SetEnvironmentVariable('GIT_COMMITTER_DATE', $priorCommitter, 'Process')
        }
        if ($null -eq $dateProbeError -or $dateProbeError.Exception.Message -notmatch 'invalid date format') {
            throw 'The scoped Git date failure was not reproducible on this host. No GitHub fixture was created.'
        }
    }
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
        Write-Warning "Initial recovery E2E migration error (before cleanup): $($caughtError.Exception.Message)"
        try {
            [pscustomobject] @{
                Scenario = 'InitialMissingLfsMigration'
                ErrorId = $caughtError.FullyQualifiedErrorId
                Message = $caughtError.Exception.Message
                ScriptStackTrace = $caughtError.ScriptStackTrace
            } | ConvertTo-Json -Depth 5 |
                Set-Content -LiteralPath (Join-Path $tempRoot 'initial-migration-failure.json') -Encoding utf8NoBOM -ErrorAction Stop
        }
        catch {
            Write-Warning "Unable to persist initial migration failure diagnostic: $($_.Exception.Message)"
        }
    }

    if ($null -eq $caughtError) {
        throw 'Recovery E2E expected snapshot migration to fail because the source Git LFS object is intentionally missing.'
    }

    # Missing LFS content is rejected during immutable source planning, BEFORE
    # destination creation. Post-mutation recovery must never be claimed here.
    if ($caughtError.FullyQualifiedErrorId -ne 'SnapshotPlanningGitLfsFetchFailed,Get-CgrRepositoryDefaultBranchTree') {
        throw "Missing LFS fixture failed at unexpected boundary: $($caughtError.FullyQualifiedErrorId)"
    }
    if ((Test-Path -LiteralPath $reportPath) -or (Test-Path -LiteralPath "$reportPath.recovery.json")) {
        throw 'Pre-mutation LFS planning rejection unexpectedly produced an execution or recovery report.'
    }
    Assert-RecoveryE2eRepositoryAbsent -Repository $destinationRepository
    $preflightEvidence = [pscustomobject] @{
        ScenarioId = 'SCN-LFS-VALIDATION-01'
        ExpectedPlanningFailureObserved = $true
        ErrorId = $caughtError.FullyQualifiedErrorId
        FailureBoundary = 'SnapshotPlanning'
        DestinationCreated = $false
        IndependentDestinationAbsenceVerified = $true
        PostMutationRecoveryExpected = $false
    }
    $preflightEvidence | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $tempRoot 'lfs-planning-validation.json') -Encoding utf8NoBOM -ErrorAction Stop
    $preflightEvidence | Format-List

    # SCN-DEST-HAPPY-01: run-unique disposable different-destination archive/replace.
    Write-Information -MessageData 'Scenario: SCN-DEST-HAPPY-01 existing destination archive and verified replacement' -InformationAction Continue
    $happySource = "$Owner/$repositoryPrefix-existing-source"
    $happyDestination = "$Owner/$repositoryPrefix-existing-destination"
    $happyArchiveName = "$repositoryPrefix-existing-archive"
    $happyArchive = "$Owner/$happyArchiveName"
    New-RecoveryE2eRepository -Name "$repositoryPrefix-existing-source" -Confirm:$false | Out-Null
    New-RecoveryE2eRepository -Name "$repositoryPrefix-existing-destination" -Confirm:$false | Out-Null
    Publish-RecoveryE2ePlainRepository -Repository $happySource -LocalPath (Join-Path $tempRoot 'existing-source') -Marker 'New approved source'
    Publish-RecoveryE2ePlainRepository -Repository $happyDestination -LocalPath (Join-Path $tempRoot 'existing-destination') -Marker 'Prior destination to preserve'
    $oldIdentity = Get-RecoveryE2eRemoteRepository -Repository $happyDestination
    $oldTree = (Get-RecoveryE2eRemoteCommit -Repository $happyDestination).commit.tree.sha
    $sourceTree = (Get-RecoveryE2eRemoteCommit -Repository $happySource).commit.tree.sha
    if ($oldTree -eq $sourceTree) { throw 'Fixture source/destination trees must differ.' }
    $confirmation = "DESTINATION=$happyDestination;ARCHIVE=$happyArchive;REPLACEMENT=$happyDestination"
    $plan = Copy-GitHubRepository -SourceRepository $happySource -DestinationRepository $happyDestination -ExistingDestinationArchiveName $happyArchiveName -SkipSettings -PlanOnly
    if ($plan.Mode -ne 'ExistingDestinationReplacement' -or $plan.ArchiveRepository -ne $happyArchive) {
        throw 'Existing-destination plan does not match exact reviewed archive/replace identity.'
    }
    $createdRepositories.Add($happyArchive)
    $expectedRepositoryIds[$happyArchive] = [string] $oldIdentity.id
    $happyResult = Copy-GitHubRepository -SourceRepository $happySource -DestinationRepository $happyDestination -ExistingDestinationArchiveName $happyArchiveName -ExistingDestinationConfirmation $confirmation -SkipSettings -NonInteractive -Force -ReportPath (Join-Path $tempRoot 'existing-happy.json')
    $replacementId = [string] $happyResult.ReplacementDestinationRepositoryId
    if ([string]::IsNullOrWhiteSpace($replacementId) -or $replacementId -eq [string] $oldIdentity.id) {
        throw 'Migration did not return a distinct immutable replacement ID needed for guarded cleanup.'
    }
    $expectedRepositoryIds[$happyDestination] = $replacementId
    if (-not $happyResult.IsVerified -or -not $happyResult.ArchivedOriginalIdentityPreserved -or -not $happyResult.ReplacementHasDistinctIdentity) {
        throw 'Migration-reported existing-destination replacement was not verified.'
    }
    $archivedRemote = Get-RecoveryE2eRemoteRepository -Repository $happyArchive
    $replacementRemote = Get-RecoveryE2eRemoteRepository -Repository $happyDestination
    $archivedTree = (Get-RecoveryE2eRemoteCommit -Repository $happyArchive).commit.tree.sha
    $replacementCommit = Get-RecoveryE2eRemoteCommit -Repository $happyDestination
    $verification = Test-GitHubRepositoryMigration -SourceRepository $happySource -DestinationRepository $happyDestination -ContentMode Snapshot
    if ($archivedRemote.id -ne $oldIdentity.id -or $replacementRemote.id -eq $oldIdentity.id -or
        $archivedTree -ne $oldTree -or $replacementCommit.commit.tree.sha -ne $sourceTree -or
        @($replacementCommit.parents).Count -ne 0 -or -not $verification.IsSuccessful) {
        throw 'Independent remote archive identity, original tree or Snapshot replacement validation failed.'
    }
    $stages = @($happyResult.CompletedSteps | ForEach-Object { $_.Name })
    if ($stages.Count -lt 4 -or
        ($stages[0..3] -join ',') -ne 'PreserveDestinationAsArchive,VerifyArchivedDestinationIdentity,CreateReplacementRepository,VerifyReplacementRepositoryIdentity') {
        throw 'Archive identity must be verified before replacement creation.'
    }
    $happyEvidence = [pscustomobject] @{
        ScenarioId = 'SCN-DEST-HAPPY-01'
        MigrationReportedVerified = $happyResult.IsVerified
        IndependentVerificationSucceeded = $verification.IsSuccessful
        ArchiveIdentityPreserved = ($archivedRemote.id -eq $oldIdentity.id)
        ReplacementIdentityDistinct = ($replacementRemote.id -ne $oldIdentity.id)
        ArchiveTreeUnchanged = ($archivedTree -eq $oldTree)
        ReplacementTreeEqualsSource = ($replacementCommit.commit.tree.sha -eq $sourceTree)
        OneUnrelatedRootCommit = (@($replacementCommit.parents).Count -eq 0)
    }
    $happyEvidence | ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath (Join-Path $tempRoot 'existing-destination-happy-result.json') -Encoding utf8NoBOM -ErrorAction Stop
    $happyEvidence | Format-List

    if ($ReportWriteFailureProbe) {
        # This opt-in subcase uses only test-created private repositories and
        # a local output-path error AFTER a real verified GitHub replacement.
        Write-Information -MessageData 'Subcase: post-mutation completion-report I/O failure and fail-closed retry' -InformationAction Continue
        $faultDestination = "$Owner/$repositoryPrefix-reportfault-destination"
        $faultArchiveName = "$repositoryPrefix-reportfault-archive"
        $faultArchive = "$Owner/$faultArchiveName"
        New-RecoveryE2eRepository -Name "$repositoryPrefix-reportfault-destination" -Confirm:$false | Out-Null
        Publish-RecoveryE2ePlainRepository -Repository $faultDestination -LocalPath (Join-Path $tempRoot 'reportfault-destination') -Marker 'Prior destination for report-write failure'
        $original = Get-RecoveryE2eRemoteRepository -Repository $faultDestination
        $originalId = [string] $original.id
        $originalTree = (Get-RecoveryE2eRemoteCommit -Repository $faultDestination).commit.tree.sha
        $faultSourceTree = (Get-RecoveryE2eRemoteCommit -Repository $happySource).commit.tree.sha
        if ($originalTree -eq $faultSourceTree) { throw 'Report-fault fixture source and old destination trees must differ.' }

        $faultConfirmation = "DESTINATION=$faultDestination;ARCHIVE=$faultArchive;REPLACEMENT=$faultDestination"
        $faultPlan = Copy-GitHubRepository -SourceRepository $happySource -DestinationRepository $faultDestination -ExistingDestinationArchiveName $faultArchiveName -SkipSettings -PlanOnly
        if ($faultPlan.Mode -ne 'ExistingDestinationReplacement' -or $faultPlan.ArchiveRepository -ne $faultArchive) {
            throw 'Report-fault plan does not match exact reviewed archive/replacement names.'
        }

        # PRE-MUTATION OWNERSHIP HANDOFF: the old immutable ID can move from
        # the destination name to the archive name. Do not retain that ID
        # against the reused destination name; it may become a NEW repository.
        # Prepare the local report fault before transferring repository-ID
        # ownership. A local setup failure must not complicate safe cleanup.
        $faultReportPath = Join-Path $tempRoot 'blocked-execution-report.json'
        New-Item -ItemType Directory -Path $faultReportPath -ErrorAction Stop | Out-Null

        $createdRepositories.Add($faultArchive)
        $expectedRepositoryIds[$faultArchive] = $originalId
        $expectedRepositoryIds.Remove($faultDestination) | Out-Null
        $faultError = $null
        try {
            Copy-GitHubRepository -SourceRepository $happySource -DestinationRepository $faultDestination -ExistingDestinationArchiveName $faultArchiveName -ExistingDestinationConfirmation $faultConfirmation -SkipSettings -NonInteractive -Force -ReportPath $faultReportPath -ErrorAction Stop | Out-Null
        }
        catch { $faultError = $_ }
        if ($null -eq $faultError) {
            throw 'Report-fault fixture unexpectedly completed successfully; manual identity reconciliation is required before cleanup.'
        }

        $faultRecoveryPath = "$faultReportPath.recovery.json"
        if (-not (Test-Path -LiteralPath $faultRecoveryPath -PathType Leaf)) {
            throw 'Report-fault fixture did not persist its separate recovery JSON; identity-guarded cleanup will fail closed.'
        }
        $faultRecovery = Get-Content -LiteralPath $faultRecoveryPath -Raw -ErrorAction Stop | ConvertFrom-Json

        # Independently read both real GitHub identities and compare them to
        # immutable originals and the actual recovery report BEFORE binding
        # the new destination name to its replacement identity for cleanup.
        $faultArchiveRemote = Get-RecoveryE2eRemoteRepository -Repository $faultArchive
        $faultReplacementRemote = Get-RecoveryE2eRemoteRepository -Repository $faultDestination
        $replacementId = [string] $faultReplacementRemote.id
        if ([string] $faultArchiveRemote.id -ne $originalId -or
            $replacementId -eq $originalId -or
            [string] $faultRecovery.OriginalDestinationRepositoryId -ne $originalId -or
            [string] $faultRecovery.ArchiveRepositoryId -ne $originalId -or
            [string] $faultRecovery.ReplacementRepositoryId -ne $replacementId) {
            throw 'Report-fault recovery/remote immutable identities disagree; refusing to bind reused destination for automatic deletion.'
        }
        $expectedRepositoryIds[$faultDestination] = $replacementId

        $faultArchiveTree = (Get-RecoveryE2eRemoteCommit -Repository $faultArchive).commit.tree.sha
        $faultReplacementCommit = Get-RecoveryE2eRemoteCommit -Repository $faultDestination
        $faultVerification = Test-GitHubRepositoryMigration -SourceRepository $happySource -DestinationRepository $faultDestination -ContentMode Snapshot
        $faultStages = @($faultRecovery.CompletedSteps | ForEach-Object { $_.Name })
        if ($faultRecovery.Status -ne 'ExistingDestinationReplacementFailed' -or
            $faultRecovery.FailureStage -ne 'WriteCompletionReport' -or
            $faultRecovery.ErrorId -ne $faultError.FullyQualifiedErrorId -or
            -not $faultRecovery.Recovery.ExistingDestinationPreservedAsArchive -or
            $faultRecovery.Recovery.AutomaticDeletionAttempted -or
            $faultRecovery.Recovery.AutomaticRollbackAttempted -or
            $faultStages.Count -lt 6 -or
            ($faultStages[0..3] -join ',') -ne 'PreserveDestinationAsArchive,VerifyArchivedDestinationIdentity,CreateReplacementRepository,VerifyReplacementRepositoryIdentity' -or
            $faultStages -notcontains 'CopySnapshot' -or
            $faultStages -notcontains 'VerifySnapshot' -or
            $faultArchiveTree -ne $originalTree -or
            $faultReplacementCommit.commit.tree.sha -ne $faultSourceTree -or
            @($faultReplacementCommit.parents).Count -ne 0 -or
            -not $faultVerification.IsSuccessful) {
            throw 'Actual post-mutation report-failure boundary, archived content, verified Snapshot, or durable recovery evidence did not match.'
        }

        # Retry the same approved archive name. It must fail during planning,
        # before a second archive rename or accidental overwrite.
        $retryFault = $null
        try {
            Copy-GitHubRepository -SourceRepository $happySource -DestinationRepository $faultDestination -ExistingDestinationArchiveName $faultArchiveName -ExistingDestinationConfirmation $faultConfirmation -SkipSettings -NonInteractive -Force -ErrorAction Stop | Out-Null
        }
        catch { $retryFault = $_ }
        if ($null -eq $retryFault -or $retryFault.FullyQualifiedErrorId -notmatch 'ExistingDestinationArchiveAlreadyExists') {
            throw 'Report-fault retry did not reject the occupied archive before mutation.'
        }

        $faultArchiveAfterRetry = Get-RecoveryE2eRemoteRepository -Repository $faultArchive
        $faultDestinationAfterRetry = Get-RecoveryE2eRemoteRepository -Repository $faultDestination
        $archiveTreeAfterRetry = (Get-RecoveryE2eRemoteCommit -Repository $faultArchive).commit.tree.sha
        $replacementCommitAfterRetry = Get-RecoveryE2eRemoteCommit -Repository $faultDestination
        if ([string] $faultArchiveAfterRetry.id -ne $originalId -or
            [string] $faultDestinationAfterRetry.id -ne $replacementId -or
            $archiveTreeAfterRetry -ne $originalTree -or
            $replacementCommitAfterRetry.sha -ne $faultReplacementCommit.sha) {
            throw 'Report-fault retry changed archive/replacement identities, archived tree or replacement commit.'
        }

        $faultEvidence = [pscustomobject] @{
            ScenarioId = 'SCN-RETRY-RESILIENCE-02'
            Subcase = 'PostMutationCompletionReportWriteFailure'
            RelatedRequiredLiveScenarios = @('SCN-DEST-PARTIAL-01', 'SCN-RETRY-RESILIENCE-02', 'SCN-RECOVER-RECOVERY-01')
            QualifiesFailedSnapshotTransfer = $false
            QualifiesSettingsRestoreFailure = $false
            FailureStage = $faultRecovery.FailureStage
            OriginalErrorId = $faultError.FullyQualifiedErrorId
            RecoveryErrorId = $faultRecovery.ErrorId
            RecoveryReport = $faultRecoveryPath
            CompletedSteps = $faultStages
            OriginalDestinationRepositoryId = $originalId
            ArchiveRepositoryId = [string] $faultArchiveRemote.id
            ReplacementRepositoryId = $replacementId
            OriginalTree = $originalTree
            ArchiveTree = $faultArchiveTree
            SourceTree = $faultSourceTree
            ReplacementTree = $faultReplacementCommit.commit.tree.sha
            ArchiveIdentityAndTreePreserved = $true
            ReplacementContentVerified = $faultVerification.IsSuccessful
            SingleUnrelatedSnapshotRoot = (@($faultReplacementCommit.parents).Count -eq 0)
            NoAutomaticDeletionOrRollback = (-not $faultRecovery.Recovery.AutomaticDeletionAttempted -and -not $faultRecovery.Recovery.AutomaticRollbackAttempted)
            RetryRejectedBeforeMutation = $true
            RetryErrorId = $retryFault.FullyQualifiedErrorId
            IndependentRemoteStateUnchangedAfterRetry = $true
        }
        $faultEvidence | ConvertTo-Json -Depth 12 |
            Set-Content -LiteralPath (Join-Path $tempRoot 'post-mutation-report-failure-probe.json') -Encoding utf8NoBOM -ErrorAction Stop
        $faultEvidence | Format-List
    }

    if ($LocalGitCommitFailureProbe) {
        # Test-only process environment, restored even on error. Native git
        # commit-tree rejects this date before any remote Snapshot push.
        Write-Information -MessageData 'Subcase: SCN-DEST-PARTIAL-01 native Git commit failure after archive' -InformationAction Continue
        $copyFaultDestination = "$Owner/$repositoryPrefix-copyfault-destination"
        $copyFaultArchiveName = "$repositoryPrefix-copyfault-archive"
        $copyFaultArchive = "$Owner/$copyFaultArchiveName"
        New-RecoveryE2eRepository -Name "$repositoryPrefix-copyfault-destination" -Confirm:$false | Out-Null
        Publish-RecoveryE2ePlainRepository -Repository $copyFaultDestination -LocalPath (Join-Path $tempRoot 'copyfault-original') -Marker 'Prior destination to preserve after copy failure'
        $copyFaultOriginal = Get-RecoveryE2eRemoteRepository -Repository $copyFaultDestination
        $copyFaultOriginalId = [string] $copyFaultOriginal.id
        $copyFaultOriginalTree = (Get-RecoveryE2eRemoteCommit -Repository $copyFaultDestination).commit.tree.sha
        $copyFaultSource = Get-RecoveryE2eRemoteCommit -Repository $happySource
        if ($copyFaultOriginalTree -eq $copyFaultSource.commit.tree.sha) { throw 'Copy-fault fixture trees unexpectedly match.' }
        $copyFaultConfirmation = "DESTINATION=$copyFaultDestination;ARCHIVE=$copyFaultArchive;REPLACEMENT=$copyFaultDestination"
        $copyFaultPlan = Copy-GitHubRepository -SourceRepository $happySource -DestinationRepository $copyFaultDestination -ExistingDestinationArchiveName $copyFaultArchiveName -SkipSettings -PlanOnly
        if ($copyFaultPlan.Mode -ne 'ExistingDestinationReplacement' -or $copyFaultPlan.ArchiveRepository -ne $copyFaultArchive) {
            throw 'Copy-fault reviewed plan did not match the exact disposable archive/replacement names.'
        }

        # Old immutable ID must move to archive; destination ownership is
        # re-established only after independent GitHub readback of the NEW ID.
        $createdRepositories.Add($copyFaultArchive)
        $expectedRepositoryIds[$copyFaultArchive] = $copyFaultOriginalId
        $expectedRepositoryIds.Remove($copyFaultDestination) | Out-Null
        $copyFaultReportPath = Join-Path $tempRoot 'copyfault-execution-report.json'
        # Intercept only the Snapshot commit-tree command inside the loaded
        # test module. Source-state discovery, source clone, GitHub API and
        # archive operations continue through the unmodified native executor.
        # Never change the process-wide Git date environment.
        $copyFaultError = $null
        $copyFaultCommitTreeCalls = 0
        $module = Get-Module CopyGitHubRepo -ErrorAction Stop
        if (-not $module) { throw 'Copy-fault probe requires the loaded CopyGitHubRepo module.' }
        try {
            & $module {
                $script:RecoveryE2eOriginalNativeCommand = (Get-Item Function:Invoke-CgrNativeCommand -ErrorAction Stop).ScriptBlock
                $script:RecoveryE2eCommitTreeCalls = 0
                Set-Item -Path Function:script:Invoke-CgrNativeCommand -Value {
                    [CmdletBinding()]
                    param(
                        [Parameter(Mandatory)][string] $FilePath,
                        [string[]] $ArgumentList = @(),
                        [string[]] $PrefixArgumentList = @(),
                        [hashtable] $Environment = @{},
                        [TimeSpan] $Timeout = [System.Threading.Timeout]::InfiniteTimeSpan,
                        [System.Threading.CancellationToken] $CancellationToken = [System.Threading.CancellationToken]::None
                    )
                    $isCommitTree = $FilePath -eq 'git' -and @($ArgumentList) -contains 'commit-tree'
                    if ($isCommitTree) {
                        $script:RecoveryE2eCommitTreeCalls++
                        if ($script:RecoveryE2eCommitTreeCalls -ne 1) {
                            throw 'Copy-fault probe encountered more than one native Git commit-tree invocation.'
                        }
                        $nativeArgs = @{} + $PSBoundParameters
                        $scopedEnvironment = @{} + $Environment
                        $scopedEnvironment['GIT_AUTHOR_DATE'] = 'not-a-valid-date'
                        $scopedEnvironment['GIT_COMMITTER_DATE'] = 'not-a-valid-date'
                        $nativeArgs['Environment'] = $scopedEnvironment
                        return & $script:RecoveryE2eOriginalNativeCommand @nativeArgs
                    }
                    return & $script:RecoveryE2eOriginalNativeCommand @PSBoundParameters
                }
            }
            try {
                Copy-GitHubRepository -SourceRepository $happySource -DestinationRepository $copyFaultDestination -ExistingDestinationArchiveName $copyFaultArchiveName -ExistingDestinationConfirmation $copyFaultConfirmation -SkipSettings -NonInteractive -Force -ReportPath $copyFaultReportPath -ErrorAction Stop | Out-Null
            }
            catch { $copyFaultError = $_ }
        }
        finally {
            $copyFaultCommitTreeCalls = & $module {
                try { $script:RecoveryE2eCommitTreeCalls }
                finally {
                    if ($script:RecoveryE2eOriginalNativeCommand) {
                        Set-Item -Path Function:script:Invoke-CgrNativeCommand -Value $script:RecoveryE2eOriginalNativeCommand
                    }
                    Remove-Variable -Name RecoveryE2eOriginalNativeCommand -Scope Script -ErrorAction SilentlyContinue
                    Remove-Variable -Name RecoveryE2eCommitTreeCalls -Scope Script -ErrorAction SilentlyContinue
                }
            }
        }
        # Always persist the ORIGINAL migration exception before asserting the
        # expected native Git error. The previous generic assertion hid an
        # unexpected pre-mutation failure and complicated cleanup diagnosis.
        $copyFaultErrorId = if ($copyFaultError) { [string] $copyFaultError.FullyQualifiedErrorId } else { $null }
        $copyFaultErrorMessage = if ($copyFaultError) { [string] $copyFaultError.Exception.Message } else { $null }
        try {
            [pscustomobject] @{
                Scenario = 'PostArchiveNativeGitCommitFailureAttempt'
                OriginalErrorId = $copyFaultErrorId
                OriginalMessage = $copyFaultErrorMessage
                OriginalScriptStackTrace = if ($copyFaultError) { [string] $copyFaultError.ScriptStackTrace } else { $null }
                ExpectedErrorId = 'DestinationRepositorySnapshotCommitFailed'
                OriginalDestinationRepository = $copyFaultDestination
                OriginalDestinationRepositoryId = $copyFaultOriginalId
                IntendedArchive = $copyFaultArchive
                FaultEnvironmentRestored = $true
                ScopedNativeCommitTreeCalls = $copyFaultCommitTreeCalls
            } | ConvertTo-Json -Depth 6 |
                Set-Content -LiteralPath (Join-Path $tempRoot 'copyfault-primary-migration-error.json') -Encoding utf8NoBOM -ErrorAction Stop
        }
        catch {
            Write-Warning "Unable to preserve the primary copy-fault diagnostic: $($_.Exception.Message)"
        }

        if ($copyFaultCommitTreeCalls -ne 1 -or $null -eq $copyFaultError -or $copyFaultErrorId -notmatch 'DestinationRepositorySnapshotCommitFailed' -or
            $copyFaultErrorMessage -notmatch 'invalid date format') {
            Write-Warning "Copy-fault occurred outside expected native Git commit-tree boundary. Original error: $copyFaultErrorId; message: $copyFaultErrorMessage"

            # The old ID has been provisionally assigned to the archive name.
            # Restore its ownership to the ORIGINAL destination name only if
            # authenticated GitHub readback proves the archive never appeared
            # AND the original private, test-owned repository and tree remain
            # byte-identical. Otherwise leave IDs unbound and fail closed.
            try {
                Assert-RecoveryE2eRepositoryAbsent -Repository $copyFaultArchive
                $originalNameReadback = Get-RecoveryE2eRemoteRepository -Repository $copyFaultDestination
                $originalTreeReadback = (Get-RecoveryE2eRemoteCommit -Repository $copyFaultDestination).commit.tree.sha
                if ([string] $originalNameReadback.id -eq $copyFaultOriginalId -and
                    [string] $originalNameReadback.full_name -ceq $copyFaultDestination -and
                    $originalNameReadback.private -eq $true -and
                    [string] $originalNameReadback.default_branch -eq 'main' -and
                    $originalTreeReadback -eq $copyFaultOriginalTree) {
                    $expectedRepositoryIds.Remove($copyFaultArchive) | Out-Null
                    $expectedRepositoryIds[$copyFaultDestination] = $copyFaultOriginalId
                    Write-Warning 'No archive mutation observed; verified old identity/tree restored to original name for existing guarded fixture cleanup.'
                }
                else {
                    Write-Warning 'Copy-fault repository state differs from original fixture; no automatic ID reassignment or unverified deletion.'
                }
            }
            catch {
                Write-Warning "Unable to prove exact pre-mutation remote state for safe cleanup: $($_.Exception.Message)"
            }

            if ($copyFaultError) { throw $copyFaultError }
            throw 'Copy-fault migration unexpectedly completed. Refusing scenario qualification or unverified cleanup.'
        }
        $copyFaultRecoveryPath = "$copyFaultReportPath.recovery.json"
        if (-not (Test-Path -LiteralPath $copyFaultRecoveryPath -PathType Leaf)) {
            throw 'Copy-fault migration did not create the required sibling recovery JSON.'
        }
        $copyFaultRecovery = Get-Content -LiteralPath $copyFaultRecoveryPath -Raw -ErrorAction Stop | ConvertFrom-Json
        $copyFaultArchiveRemote = Get-RecoveryE2eRemoteRepository -Repository $copyFaultArchive
        $copyFaultReplacementRemote = Get-RecoveryE2eRemoteRepository -Repository $copyFaultDestination
        $copyFaultReplacementId = [string] $copyFaultReplacementRemote.id
        if ([string] $copyFaultArchiveRemote.id -ne $copyFaultOriginalId -or
            $copyFaultReplacementId -eq $copyFaultOriginalId -or
            [string] $copyFaultRecovery.OriginalDestinationRepositoryId -ne $copyFaultOriginalId -or
            [string] $copyFaultRecovery.ArchiveRepositoryId -ne $copyFaultOriginalId -or
            [string] $copyFaultRecovery.ReplacementRepositoryId -ne $copyFaultReplacementId) {
            throw 'Copy-fault migration/remote immutable identity mismatch; cleanup fails closed.'
        }
        $expectedRepositoryIds[$copyFaultDestination] = $copyFaultReplacementId
        $copyFaultArchiveTree = (Get-RecoveryE2eRemoteCommit -Repository $copyFaultArchive).commit.tree.sha
        $copyFaultBranchCount = @(Invoke-RecoveryE2eNativeCommand -FilePath 'gh' -ArgumentList @('api', "repos/$copyFaultDestination/branches", '--jq', 'length')) -join ''
        $copyFaultStages = @($copyFaultRecovery.CompletedSteps | ForEach-Object { $_.Name })
        if ($copyFaultArchiveTree -ne $copyFaultOriginalTree -or $copyFaultBranchCount.Trim() -ne '0' -or
            $copyFaultRecovery.FailureStage -ne 'CopySnapshot' -or
            $copyFaultRecovery.Status -ne 'ExistingDestinationReplacementFailed' -or
            $copyFaultRecovery.ErrorId -ne $copyFaultError.FullyQualifiedErrorId -or
            ($copyFaultStages -join ',') -ne 'PreserveDestinationAsArchive,VerifyArchivedDestinationIdentity,CreateReplacementRepository,VerifyReplacementRepositoryIdentity' -or
            $copyFaultRecovery.Recovery.AutomaticDeletionAttempted -or
            $copyFaultRecovery.Recovery.AutomaticRollbackAttempted -or
            $copyFaultRecovery.Provenance.PlannedSourceState.CommitSha -ne $copyFaultSource.sha -or
            $copyFaultRecovery.Provenance.PlannedSourceState.TreeSha -ne $copyFaultSource.commit.tree.sha -or
            $null -ne $copyFaultRecovery.Provenance.CopiedSourceCommitSha -or
            $null -ne $copyFaultRecovery.Provenance.CopiedSourceTreeSha -or
            $null -ne $copyFaultRecovery.Provenance.DestinationRootCommitSha -or
            $null -ne $copyFaultRecovery.Provenance.DestinationTreeSha -or
            $null -ne $copyFaultRecovery.Provenance.VerificationSuccessful -or
            $copyFaultRecovery.Provenance.ActualEvidenceAvailable -ne $false) {
            throw 'Copy-fault remote archive/empty replacement or migration-authored unknown-state recovery did not verify.'
        }
        $copyFaultEvidence = [pscustomobject] @{
            ScenarioId = 'SCN-DEST-PARTIAL-01'
            Subcase = 'LocalGitCommitFailureAfterArchive'
            FailureStage = $copyFaultRecovery.FailureStage
            OriginalErrorId = $copyFaultError.FullyQualifiedErrorId
            RecoveryErrorId = $copyFaultRecovery.ErrorId
            RecoveryReport = $copyFaultRecoveryPath
            OriginalDestinationRepositoryId = $copyFaultOriginalId
            ArchiveRepositoryId = [string] $copyFaultArchiveRemote.id
            ReplacementRepositoryId = $copyFaultReplacementId
            OriginalTree = $copyFaultOriginalTree
            ArchiveTree = $copyFaultArchiveTree
            ApprovedSourceCommit = $copyFaultSource.sha
            ApprovedSourceTree = $copyFaultSource.commit.tree.sha
            ReplacementBranchCount = [int] $copyFaultBranchCount.Trim()
            CompletedSteps = $copyFaultStages
            NoAutomaticDeletionOrRollback = $true
            ActualCopyEvidenceUnknown = $true
            QualifiesLocalGitCommitFailure = $true
            QualifiesFailedRemotePush = $false
            QualifiesSettingsRestoreFailure = $false
            QualifiesBroaderRecovery = $false
        }
        $copyFaultEvidence | ConvertTo-Json -Depth 12 |
            Set-Content -LiteralPath (Join-Path $tempRoot 'post-archive-git-commit-failure-probe.json') -Encoding utf8NoBOM -ErrorAction Stop
        $copyFaultEvidence | Format-List
    }

    # Only the *opt-in successful real-GitHub retry* can prove this scenario.
    # Without that opt-in, the earlier missing-LFS planning failure does not.
    $pendingRequiredLiveScenarios = @('SCN-SET-PARTIAL-01', 'SCN-RECOVER-RECOVERY-01')
    $verifiedRequiredLiveScenarios = @()
    if ($LocalGitCommitFailureProbe) {
        $verifiedRequiredLiveScenarios += 'SCN-DEST-PARTIAL-01'
    }
    else {
        $pendingRequiredLiveScenarios += 'SCN-DEST-PARTIAL-01'
    }
    if ($ReportWriteFailureProbe) {
        $verifiedRequiredLiveScenarios += 'SCN-RETRY-RESILIENCE-02'
    }
    else {
        $pendingRequiredLiveScenarios += 'SCN-RETRY-RESILIENCE-02'
    }
    $pendingEvidence = [pscustomobject] @{
        Scope = if ($ReportWriteFailureProbe -and $LocalGitCommitFailureProbe) { 'SafeSubsetOnlyWithBothOptInProbes' } elseif ($ReportWriteFailureProbe) { 'SafeSubsetOnlyWithReportWriteFailureProbe' } elseif ($LocalGitCommitFailureProbe) { 'SafeSubsetOnlyWithLocalGitCommitFailureProbe' } else { 'SafeSubsetOnly' }
        CompleteRequiredLiveQualification = $false
        PendingRequiredLiveScenarios = @($pendingRequiredLiveScenarios)
        VerifiedRequiredLiveScenarios = @($verifiedRequiredLiveScenarios)
        EvaluatedReportWriteFailureSubcase = [bool] $ReportWriteFailureProbe
        EvaluatedLocalGitCommitFailureSubcase = [bool] $LocalGitCommitFailureProbe
        Reason = 'The opt-in local Git commit-tree fault proves a failed post-archive Snapshot-copy stage before any remote push, not failed remote transfer. The separate report-write fault proves scoped retry; settings failure and broader recovery remain unqualified. No full Required-live suite claim.'
    }
    $pendingEvidence | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $tempRoot 'required-live-evidence-pending.json') -Encoding utf8NoBOM -ErrorAction Stop
    if ($ReportWriteFailureProbe) {
        Write-Warning 'Scoped live retry verified; Required-live failed replacement, settings failure and broader recovery scenarios remain UNQUALIFIED.'
    }
    else {
        Write-Warning 'SafeSubsetOnly completed; Required-live partial, retry, settings and recovery scenarios remain UNQUALIFIED.'
    }
}
catch {
    # Preserve the first meaningful failure before cleanup can throw a second
    # error. Diagnostic failures must not override the actual test error.
    $primaryFailure = $_
    Write-Warning "Recovery E2E primary failure before cleanup: $($primaryFailure.Exception.Message)"
    try {
        [pscustomobject] @{
            ErrorId = $primaryFailure.FullyQualifiedErrorId
            Message = $primaryFailure.Exception.Message
            ScriptStackTrace = $primaryFailure.ScriptStackTrace
        } | ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath (Join-Path $tempRoot 'primary-failure.json') -Encoding utf8NoBOM -ErrorAction Stop
    }
    catch {
        Write-Warning "Unable to persist primary E2E failure diagnostic: $($_.Exception.Message)"
    }
    throw
}
finally {
    $cleanupResults = [System.Collections.Generic.List[object]]::new()
    $cleanupFailures = [System.Collections.Generic.List[string]]::new()
    if (-not $KeepRepositories) {
        foreach ($repository in @($createdRepositories) | Select-Object -Unique | Sort-Object -Descending) {
            try {
                if (-not $expectedRepositoryIds.ContainsKey($repository) -or
                    [string]::IsNullOrWhiteSpace([string] $expectedRepositoryIds[$repository])) {
                    # Pre-registered names may never have been created. Never
                    # delete without an ID; require an authenticated HTTP 404.
                    Assert-RecoveryE2eRepositoryAbsent -Repository $repository
                    $cleanupResults.Add([pscustomobject] @{
                            Repository = $repository
                            ExpectedId = $null
                            DeletionAttempted = $false
                            VerifiedAbsent = $true
                            Disposition = 'RegisteredNameWithoutIdentityVerifiedAbsent'
                        })
                    continue
                }
                Remove-RecoveryE2eRepository -Repository $repository -Confirm:$false
                Assert-RecoveryE2eRepositoryAbsent -Repository $repository
                $cleanupResults.Add([pscustomobject] @{
                        Repository = $repository
                        ExpectedId = [string] $expectedRepositoryIds[$repository]
                        DeletionAttempted = $true
                        VerifiedAbsent = $true
                    })
            }
            catch {
                $failure = "Cleanup or independent absence verification failed for '$repository': $($_.Exception.Message)"
                $cleanupFailures.Add($failure)
                $cleanupResults.Add([pscustomobject] @{
                        Repository = $repository
                        ExpectedId = if ($expectedRepositoryIds.ContainsKey($repository)) { [string] $expectedRepositoryIds[$repository] } else { $null }
                        VerifiedAbsent = $false
                        Error = $_.Exception.Message
                    })
                Write-Warning $failure
            }
        }
    }
    else {
        Write-Warning "Recovery E2E repositories were retained because -KeepRepositories was supplied: $(@($createdRepositories) -join ', ')"
    }

    $cleanupRecordWritten = $true
    try {
        [pscustomobject] @{
            RunId = $runId
            CheckedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
            KeepRepositories = [bool] $KeepRepositories
            CleanupAttempted = -not $KeepRepositories
            CleanupVerified = -not $KeepRepositories -and $cleanupFailures.Count -eq 0
            Results = @($cleanupResults)
            Failures = @($cleanupFailures)
            RegisteredRepositories = @($createdRepositories | Select-Object -Unique)
            ExpectedRepositoryIds = $expectedRepositoryIds
        } | ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath (Join-Path $tempRoot 'cleanup-verification.json') -Encoding utf8NoBOM -ErrorAction Stop
    }
    catch {
        $cleanupRecordWritten = $false
        Write-Warning "Unable to record independent cleanup verification: $($_.Exception.Message)"
    }

    $evidenceCopySucceeded = $true
    if ($evidenceRunPath) {
        try {
            foreach ($report in @(Get-ChildItem -LiteralPath $tempRoot -File -Filter '*.json' -ErrorAction Stop)) {
                Copy-Item -LiteralPath $report.FullName -Destination $evidenceRunPath -ErrorAction Stop
            }
            Write-Information -MessageData "Recovery E2E JSON evidence directory: $evidenceRunPath" -InformationAction Continue
        }
        catch {
            $evidenceCopySucceeded = $false
            Write-Warning "Failed to copy recovery E2E evidence to '$evidenceRunPath': $($_.Exception.Message)"
        }
    }

    if ($cleanupFailures.Count -eq 0 -and $cleanupRecordWritten -and $evidenceCopySucceeded) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    else {
        Write-Warning "Temporary fixture/report directory retained for manual cleanup or evidence recovery: $tempRoot"
    }
    if ($cleanupFailures.Count -gt 0) {
        throw "Recovery E2E cleanup was not independently verified for $($cleanupFailures.Count) registered repository operation(s). Review the retained evidence and reconcile test-owned repositories."
    }
    if (-not $cleanupRecordWritten -or -not $evidenceCopySucceeded) {
        throw 'Recovery E2E cleanup or evidence reporting is incomplete. Review the retained temporary fixture/report directory.'
    }
}
