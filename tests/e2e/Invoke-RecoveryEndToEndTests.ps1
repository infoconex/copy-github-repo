#requires -Version 7.4

[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string] $Owner = 'infoconex',

    [switch] $KeepRepositories,

    [ValidateNotNullOrEmpty()]
    [string] $EvidenceDirectory
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
    $happyResult = Copy-GitHubRepository -SourceRepository $happySource -DestinationRepository $happyDestination -ExistingDestinationArchiveName $happyArchiveName -ExistingDestinationConfirmation $confirmation -SkipSettings -NonInteractive -Force -ReportPath (Join-Path $tempRoot 'existing-happy.json')
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
    [pscustomobject] @{
        ScenarioId = 'SCN-DEST-HAPPY-01'
        MigrationReportedVerified = $happyResult.IsVerified
        IndependentVerificationSucceeded = $verification.IsSuccessful
        ArchiveIdentityPreserved = ($archivedRemote.id -eq $oldIdentity.id)
        ReplacementIdentityDistinct = ($replacementRemote.id -ne $oldIdentity.id)
        ArchiveTreeUnchanged = ($archivedTree -eq $oldTree)
        ReplacementTreeEqualsSource = ($replacementCommit.commit.tree.sha -eq $sourceTree)
        OneUnrelatedRootCommit = (@($replacementCommit.parents).Count -eq 0)
    } | Format-List

    # SCN-DEST-PARTIAL-01: after the exact archive rename, a deliberately missing LFS
    # source object fails Snapshot copy; archived remote identity/tree must survive.
    Write-Information -MessageData 'Scenario: SCN-DEST-PARTIAL-01 preserve original archive after copy failure' -InformationAction Continue
    $partialDestination = "$Owner/$repositoryPrefix-partial-destination"
    $partialArchiveName = "$repositoryPrefix-partial-archive"
    $partialArchive = "$Owner/$partialArchiveName"
    New-RecoveryE2eRepository -Name "$repositoryPrefix-partial-destination" -Confirm:$false | Out-Null
    Publish-RecoveryE2ePlainRepository -Repository $partialDestination -LocalPath (Join-Path $tempRoot 'partial-destination') -Marker 'Original destination preserved after failure'
    $priorIdentity = Get-RecoveryE2eRemoteRepository -Repository $partialDestination
    $priorTree = (Get-RecoveryE2eRemoteCommit -Repository $partialDestination).commit.tree.sha
    $partialConfirmation = "DESTINATION=$partialDestination;ARCHIVE=$partialArchive;REPLACEMENT=$partialDestination"
    $partialReport = Join-Path $tempRoot 'existing-partial.json'
    $createdRepositories.Add($partialArchive)
    $partialError = $null
    try {
        Copy-GitHubRepository -SourceRepository $sourceRepository -DestinationRepository $partialDestination -ExistingDestinationArchiveName $partialArchiveName -ExistingDestinationConfirmation $partialConfirmation -SkipSettings -NonInteractive -Force -ReportPath $partialReport | Out-Null
    }
    catch { $partialError = $_ }
    if ($null -eq $partialError) { throw 'Expected a missing-LFS failure after archival of the disposable existing destination.' }
    $partialRecoveryPath = "$partialReport.recovery.json"
    if (-not (Test-Path -LiteralPath $partialRecoveryPath)) { throw 'Existing-destination recovery report was not produced.' }
    $partialRecovery = Get-Content -LiteralPath $partialRecoveryPath -Raw | ConvertFrom-Json
    $archiveState = Get-RecoveryE2eRemoteRepository -Repository $partialArchive
    $partialReplacement = Get-RecoveryE2eRemoteRepository -Repository $partialDestination
    $archiveTree = (Get-RecoveryE2eRemoteCommit -Repository $partialArchive).commit.tree.sha
    if ($partialRecovery.Status -ne 'ExistingDestinationReplacementFailed' -or
        $partialRecovery.FailureStage -ne 'CopySnapshot' -or
        $partialRecovery.ErrorId -notmatch 'SourceGitLfsFetchFailed' -or
        $partialRecovery.OriginalDestinationRepositoryId -ne $priorIdentity.id -or
        $partialRecovery.ArchiveRepositoryId -ne $priorIdentity.id -or
        $partialRecovery.ReplacementRepositoryId -ne $partialReplacement.id -or
        -not $partialRecovery.Recovery.ExistingDestinationPreservedAsArchive -or
        $partialRecovery.Recovery.AutomaticDeletionAttempted -or
        $partialRecovery.Recovery.AutomaticRollbackAttempted -or
        $archiveState.id -ne $priorIdentity.id -or
        $partialReplacement.id -eq $priorIdentity.id -or
        $archiveTree -ne $priorTree) {
        throw 'Remote identity, preserved archive tree or durable partial-failure evidence did not match.'
    }
    $completed = @($partialRecovery.CompletedSteps | ForEach-Object { $_.Name })
    if (($completed -join ',') -ne 'PreserveDestinationAsArchive,VerifyArchivedDestinationIdentity,CreateReplacementRepository,VerifyReplacementRepositoryIdentity') {
        throw 'Partial recovery completed-step timeline was not the expected archive/copy boundary.'
    }
    [pscustomobject] @{
        ScenarioId = 'SCN-DEST-PARTIAL-01'
        ExpectedFailureObserved = $true
        FailureStage = $partialRecovery.FailureStage
        IndependentArchiveIdentityPreserved = ($archiveState.id -eq $priorIdentity.id)
        IndependentArchiveTreePreserved = ($archiveTree -eq $priorTree)
        ReplacementIdentityDistinct = ($partialReplacement.id -ne $priorIdentity.id)
        RecoveryReport = $partialRecoveryPath
    } | Format-List

    # SCN-RETRY-RESILIENCE-02: do not blindly replay an ambiguous post-archive
    # mutation; the approved archive name already exists and must block a new plan.
    Write-Information -MessageData 'Scenario: SCN-RETRY-RESILIENCE-02 reject retry using preserved archive' -InformationAction Continue
    $retryError = $null
    try {
        Copy-GitHubRepository -SourceRepository $sourceRepository -DestinationRepository $partialDestination -ExistingDestinationArchiveName $partialArchiveName -ExistingDestinationConfirmation $partialConfirmation -SkipSettings -NonInteractive -Force | Out-Null
    }
    catch { $retryError = $_ }
    if ($null -eq $retryError -or $retryError.FullyQualifiedErrorId -notmatch 'ExistingDestinationArchiveAlreadyExists') {
        throw 'Retry after partial mutation did not reject the unchanged occupied archive.'
    }
    $retryArchive = Get-RecoveryE2eRemoteRepository -Repository $partialArchive
    $retryReplacement = Get-RecoveryE2eRemoteRepository -Repository $partialDestination
    if ($retryArchive.id -ne $archiveState.id -or
        $retryReplacement.id -ne $partialReplacement.id -or
        (Get-RecoveryE2eRemoteCommit -Repository $partialArchive).commit.tree.sha -ne $priorTree) {
        throw 'Retry changed the archived original, replacement identity or preserved tree.'
    }
    [pscustomobject] @{
        ScenarioId = 'SCN-RETRY-RESILIENCE-02'
        RetryRejectedBeforeMutation = $true
        ErrorId = $retryError.FullyQualifiedErrorId
        IndependentArchiveIdentityUnchanged = ($retryArchive.id -eq $archiveState.id)
        IndependentReplacementIdentityUnchanged = ($retryReplacement.id -eq $partialReplacement.id)
    } | Format-List
}
finally {
    $cleanupResults = [System.Collections.Generic.List[object]]::new()
    $cleanupFailures = [System.Collections.Generic.List[string]]::new()
    if (-not $KeepRepositories) {
        foreach ($repository in @($createdRepositories) | Select-Object -Unique | Sort-Object -Descending) {
            try {
                Remove-RecoveryE2eRepository -Repository $repository -Confirm:$false
                Assert-RecoveryE2eRepositoryAbsent -Repository $repository
                $cleanupResults.Add([pscustomobject] @{
                        Repository = $repository
                        VerifiedAbsent = $true
                    })
            }
            catch {
                $failure = "Cleanup or independent absence verification failed for '$repository': $($_.Exception.Message)"
                $cleanupFailures.Add($failure)
                $cleanupResults.Add([pscustomobject] @{
                        Repository = $repository
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
