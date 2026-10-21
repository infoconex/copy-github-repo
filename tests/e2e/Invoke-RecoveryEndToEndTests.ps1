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
    [switch] $ReportWriteFailureProbe
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
        $createdRepositories.Add($faultArchive)
        $expectedRepositoryIds[$faultArchive] = $originalId
        $expectedRepositoryIds.Remove($faultDestination) | Out-Null

        $faultReportPath = Join-Path $tempRoot 'blocked-execution-report.json'
        New-Item -ItemType Directory -Path $faultReportPath -ErrorAction Stop | Out-Null
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

    # Missing-LFS planning rejection cannot prove post-archive failure/retry.
    # Those authenticated GitHub boundary checks remain Required and UNVERIFIED.
    $pendingEvidence = [pscustomobject] @{
        Scope = if ($ReportWriteFailureProbe) { 'SafeSubsetOnlyWithReportWriteFailureProbe' } else { 'SafeSubsetOnly' }
        CompleteRequiredLiveQualification = $false
        PendingRequiredLiveScenarios = @('SCN-DEST-PARTIAL-01', 'SCN-RETRY-RESILIENCE-02', 'SCN-SET-PARTIAL-01', 'SCN-RECOVER-RECOVERY-01')
        EvaluatedReportWriteFailureSubcase = [bool] $ReportWriteFailureProbe
        Reason = 'No complete required-live failed Snapshot-transfer or supported settings-failure fixture has been qualified; a local post-mutation report-write error is a narrower boundary. Issue #173 remains open.'
    }
    $pendingEvidence | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $tempRoot 'required-live-evidence-pending.json') -Encoding utf8NoBOM -ErrorAction Stop
    Write-Warning 'SafeSubsetOnly completed; pending Required-live partial, retry, settings and recovery scenarios are NOT qualified.'
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
