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
$repositoryPrefix = "copy-github-repo-pages-e2e-$runId"
$createdRepositories = [System.Collections.Generic.List[string]]::new()
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) $repositoryPrefix
$scenarioResults = [System.Collections.Generic.List[object]]::new()

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
    param([AllowEmptyString()] [string] $Message = '')
    Write-Information -MessageData $Message -InformationAction Continue
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

function Get-E2eApiJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Path)
    $output = @(Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @('api', '--hostname', 'github.com', $Path))
    return (($output -join "`n") | ConvertFrom-Json -Depth 100)
}

function Get-E2eApiOptionalJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Path)

    $output = & gh api --hostname github.com $Path 2>&1
    if ($LASTEXITCODE -eq 0) {
        return ((@($output) -join "`n") | ConvertFrom-Json -Depth 100)
    }
    if ((@($output) -join "`n") -match '(?i)404|not found') { return $null }
    throw "GitHub API read failed for '$Path'. $(@($output) -join [Environment]::NewLine)"
}

function New-E2eRepository {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Name)

    if ($Name -notlike "$repositoryPrefix-*") {
        throw "Refusing to create an E2E repository outside the protected prefix '$repositoryPrefix-*'."
    }

    $fullName = "$Owner/$Name"
    if (-not $PSCmdlet.ShouldProcess($fullName, 'Create temporary public Pages E2E repository')) { return $null }
    Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @('repo', 'create', $fullName, '--public') | Out-Null
    $createdRepositories.Add($fullName)
    return $fullName
}

function Remove-E2eRepository {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Repository)

    $expectedPrefix = "$Owner/$repositoryPrefix-"
    if (-not $Repository.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to delete repository '$Repository' because it is outside the protected E2E prefix '$expectedPrefix'."
    }
    if (-not $PSCmdlet.ShouldProcess($Repository, 'Delete temporary Pages E2E repository')) { return }
    Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @('repo', 'delete', $Repository, '--yes') | Out-Null
}

function Get-E2eRepositoryId {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Repository)
    return [long] (Get-E2eApiJson -Path "repos/$Repository").id
}

function Set-E2eActionsEnabled {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Repository,
        [Parameter(Mandatory)] [bool] $Enabled
    )

    if (-not $PSCmdlet.ShouldProcess($Repository, "Set GitHub Actions enabled=$Enabled")) { return }
    Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @(
        'api', '--hostname', 'github.com', '--method', 'PUT',
        "repos/$Repository/actions/permissions", '-F', "enabled=$($Enabled.ToString().ToLowerInvariant())"
    ) | Out-Null
}

function New-E2eSourceFixture {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Name,
        [ValidateSet('None', 'Workflow', 'LegacyDocs')] [string] $PagesMode = 'None'
    )

    $fullName = "$Owner/$Name"
    if (-not $PSCmdlet.ShouldProcess($fullName, "Create and configure temporary GitHub Pages E2E source fixture ($PagesMode)")) { return $null }

    $repository = New-E2eRepository -Name $Name -Confirm:$false
    Set-E2eActionsEnabled -Repository $repository -Enabled $false -Confirm:$false

    $localPath = Join-Path $tempRoot $Name
    New-Item -Path $localPath -ItemType Directory -Force | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('init', '-b', 'main') -WorkingDirectory $localPath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('config', 'user.name', 'Copy GitHub Repo Pages E2E') -WorkingDirectory $localPath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('config', 'user.email', 'copy-github-repo-pages-e2e@users.noreply.github.com') -WorkingDirectory $localPath | Out-Null
    Set-Content -LiteralPath (Join-Path $localPath 'README.md') -Value '# GitHub Pages E2E Fixture' -Encoding utf8NoBOM

    if ($PagesMode -eq 'LegacyDocs') {
        New-Item -Path (Join-Path $localPath 'docs') -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $localPath 'docs/index.html') -Value '<!doctype html><title>CopyGitHubRepo Pages E2E</title>' -Encoding utf8NoBOM
    }
    elseif ($PagesMode -eq 'Workflow') {
        $workflowDirectory = Join-Path $localPath '.github/workflows'
        New-Item -Path $workflowDirectory -ItemType Directory -Force | Out-Null
        @'
name: Pages activation guard fixture
on:
  push:
    branches: [main]
permissions:
  contents: read
  pages: write
  id-token: write
jobs:
  configure-pages:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/configure-pages@45bfe0192ca1faeb007ade9deae92b16b8254a0d
        with:
          enablement: true
'@ | Set-Content -LiteralPath (Join-Path $workflowDirectory 'pages.yml') -Encoding utf8NoBOM
    }

    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('add', '.') -WorkingDirectory $localPath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('commit', '-m', 'Create GitHub Pages E2E fixture') -WorkingDirectory $localPath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('remote', 'add', 'origin', "https://github.com/$repository.git") -WorkingDirectory $localPath | Out-Null

    $module = Get-Module CopyGitHubRepo
    $pushResult = & $module {
        param($RepositoryUrl, $LocalPath)
        Invoke-CgrGitCommand -HostName 'github.com' -ArgumentList @('-C', $LocalPath, 'push', '-u', $RepositoryUrl, 'main')
    } "https://github.com/$repository.git" $localPath
    if ($pushResult.ExitCode -ne 0) {
        throw "Failed to publish Pages E2E source '$repository'. $($pushResult.ErrorText)"
    }

    switch ($PagesMode) {
        'Workflow' {
            Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @(
                'api', '--hostname', 'github.com', '--method', 'POST', "repos/$repository/pages", '-f', 'build_type=workflow'
            ) | Out-Null
        }
        'LegacyDocs' {
            Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @(
                'api', '--hostname', 'github.com', '--method', 'POST', "repos/$repository/pages",
                '-f', 'build_type=legacy', '-f', 'source[branch]=main', '-f', 'source[path]=/docs'
            ) | Out-Null
        }
    }

    Set-E2eActionsEnabled -Repository $repository -Enabled $true -Confirm:$false
    return [pscustomobject] @{ Repository = $repository; LocalPath = $localPath; PagesMode = $PagesMode }
}

function Assert-E2ePagesState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Repository,
        [Parameter(Mandatory)] [ValidateSet('NotConfigured', 'workflow', 'legacy')] [string] $BuildType,
        [string] $Branch,
        [string] $Path
    )

    $pages = Get-E2eApiOptionalJson -Path "repos/$Repository/pages"
    if ($BuildType -eq 'NotConfigured') {
        if ($null -ne $pages) { throw "Repository '$Repository' unexpectedly has GitHub Pages configured." }
        return $null
    }
    if ($null -eq $pages) { throw "Repository '$Repository' does not have expected GitHub Pages configuration." }
    if ([string] $pages.build_type -ne $BuildType) {
        throw "Repository '$Repository' Pages build type is '$($pages.build_type)', expected '$BuildType'."
    }
    if ($BuildType -eq 'legacy' -and ([string] $pages.source.branch -ne $Branch -or [string] $pages.source.path -ne $Path)) {
        throw "Repository '$Repository' Pages source is '$($pages.source.branch):$($pages.source.path)', expected '${Branch}:$Path'."
    }
    return $pages
}

function Invoke-E2eActionsSnapshotScenario {
    [CmdletBinding()]
    param()

    Write-E2eMessage -Message 'Scenario: new-destination Snapshot with Actions-based Pages and implicit-activation guard'
    $fixture = New-E2eSourceFixture -Name "$repositoryPrefix-actions-snapshot-source" -PagesMode Workflow
    $destination = "$Owner/$repositoryPrefix-actions-snapshot-destination"
    $createdRepositories.Add($destination)
    $sourcePages = Assert-E2ePagesState -Repository $fixture.Repository -BuildType workflow

    Write-E2eMessage -Message 'Migration evidence: execute Snapshot -RestorePages from the reviewed source Pages state.'
    $result = Copy-GitHubRepository -SourceRepository $fixture.Repository -DestinationRepository $destination -ContentMode Snapshot -RestorePages -SkipSettings -NonInteractive -Force
    if (-not $result.IsVerified) { throw 'Actions-based Snapshot migration did not report verification success.' }

    Write-E2eMessage -Message 'Independent verification: read destination /pages, Actions permissions/runs, then run Test-GitHubRepositoryMigration -VerifyPages.'
    $destinationPages = Assert-E2ePagesState -Repository $destination -BuildType workflow
    $actions = Get-E2eApiJson -Path "repos/$destination/actions/permissions"
    $runs = Get-E2eApiJson -Path "repos/$destination/actions/runs?per_page=100"
    if (-not [bool] $actions.enabled) { throw 'Destination Actions remained disabled after approved Pages restoration.' }
    if ([int] $runs.total_count -ne 0) {
        throw "The copied Pages workflow ran during migration. Expected the Pages activation guard to prevent pre-restoration workflow activation, but found $($runs.total_count) run(s)."
    }
    $verification = Test-GitHubRepositoryMigration -SourceRepository $fixture.Repository -DestinationRepository $destination -ContentMode Snapshot -VerifyPages -ApprovedPlan $result.Plan
    if (-not $verification.IsSuccessful -or -not $verification.PagesVerified) { throw 'Independent Actions-based Pages verification failed.' }

    $summary = [pscustomobject] @{
        Scenario = 'Snapshot Actions-based Pages'
        ReviewedSourceBuildType = $sourcePages.build_type
        MigrationReportedVerified = $result.IsVerified
        DestinationBuildType = $destinationPages.build_type
        IndependentVerificationSucceeded = $verification.IsSuccessful
        PagesVerified = $verification.PagesVerified
        DestinationActionsEnabledAfterRestore = [bool] $actions.enabled
        PreRestorationWorkflowRunsObserved = [int] $runs.total_count
        ImplicitActivationControlled = [int] $runs.total_count -eq 0
    }
    $scenarioResults.Add($summary)
}

function Invoke-E2eLegacyFullHistoryScenario {
    [CmdletBinding()]
    param()

    Write-E2eMessage -Message 'Scenario: new-destination FullHistory with branch/path-based Pages'
    $fixture = New-E2eSourceFixture -Name "$repositoryPrefix-legacy-fullhistory-source" -PagesMode LegacyDocs
    $destination = "$Owner/$repositoryPrefix-legacy-fullhistory-destination"
    $createdRepositories.Add($destination)
    $sourcePages = Assert-E2ePagesState -Repository $fixture.Repository -BuildType legacy -Branch main -Path /docs

    Write-E2eMessage -Message 'Migration evidence: execute FullHistory -RestorePages preserving the exact reviewed main:/docs source.'
    $result = Copy-GitHubRepository -SourceRepository $fixture.Repository -DestinationRepository $destination -ContentMode FullHistory -RestorePages -SkipSettings -NonInteractive -Force
    if (-not $result.IsVerified) { throw 'Legacy FullHistory migration did not report verification success.' }

    Write-E2eMessage -Message 'Independent verification: read destination /pages and run the independent Pages verifier.'
    $destinationPages = Assert-E2ePagesState -Repository $destination -BuildType legacy -Branch main -Path /docs
    $verification = Test-GitHubRepositoryMigration -SourceRepository $fixture.Repository -DestinationRepository $destination -ContentMode FullHistory -VerifyPages -ApprovedPlan $result.Plan
    if (-not $verification.IsSuccessful -or -not $verification.PagesVerified) { throw 'Independent legacy FullHistory Pages verification failed.' }

    $summary = [pscustomobject] @{
        Scenario = 'FullHistory branch/path Pages'
        ReviewedSourceBuildType = $sourcePages.build_type
        ReviewedSource = "$($sourcePages.source.branch):$($sourcePages.source.path)"
        MigrationReportedVerified = $result.IsVerified
        DestinationBuildType = $destinationPages.build_type
        DestinationSource = "$($destinationPages.source.branch):$($destinationPages.source.path)"
        IndependentVerificationSucceeded = $verification.IsSuccessful
        PagesVerified = $verification.PagesVerified
    }
    $scenarioResults.Add($summary)
}

function Invoke-E2eNoPagesScenario {
    [CmdletBinding()]
    param()

    Write-E2eMessage -Message 'Scenario: source with no Pages configured and -RestorePages requested'
    $fixture = New-E2eSourceFixture -Name "$repositoryPrefix-no-pages-source" -PagesMode None
    $destination = "$Owner/$repositoryPrefix-no-pages-destination"
    $createdRepositories.Add($destination)
    Assert-E2ePagesState -Repository $fixture.Repository -BuildType NotConfigured | Out-Null

    Write-E2eMessage -Message 'Migration evidence: execute Snapshot -RestorePages from reviewed NotConfigured Pages evidence.'
    $result = Copy-GitHubRepository -SourceRepository $fixture.Repository -DestinationRepository $destination -RestorePages -SkipSettings -NonInteractive -Force
    if (-not $result.IsVerified) { throw 'No-Pages migration did not report verification success.' }

    Write-E2eMessage -Message 'Independent verification: prove destination Pages remains absent and verify against the approved plan.'
    Assert-E2ePagesState -Repository $destination -BuildType NotConfigured | Out-Null
    $verification = Test-GitHubRepositoryMigration -SourceRepository $fixture.Repository -DestinationRepository $destination -ContentMode Snapshot -VerifyPages -ApprovedPlan $result.Plan
    if (-not $verification.IsSuccessful -or -not $verification.PagesVerified) { throw 'Independent no-Pages verification failed.' }

    $summary = [pscustomobject] @{
        Scenario = 'No Pages configured'
        ReviewedSourcePagesStatus = $result.Plan.Pages.Status
        MigrationReportedVerified = $result.IsVerified
        DestinationPagesConfigured = $false
        IndependentVerificationSucceeded = $verification.IsSuccessful
        PagesVerified = $verification.PagesVerified
    }
    $scenarioResults.Add($summary)
}

function Invoke-E2eRestorePagesOmittedScenario {
    [CmdletBinding()]
    param()

    Write-E2eMessage -Message 'Scenario: Actions-based source with -RestorePages omitted'
    $fixture = New-E2eSourceFixture -Name "$repositoryPrefix-omitted-source" -PagesMode Workflow
    $destination = "$Owner/$repositoryPrefix-omitted-destination"
    $createdRepositories.Add($destination)
    Assert-E2ePagesState -Repository $fixture.Repository -BuildType workflow | Out-Null

    Write-E2eMessage -Message 'Migration evidence: execute ordinary Snapshot without -RestorePages; the #97 contract intentionally does not add an activation guard to this path.'
    $result = Copy-GitHubRepository -SourceRepository $fixture.Repository -DestinationRepository $destination -SkipSettings -NonInteractive -Force
    if (-not $result.IsVerified) { throw 'Pages-omitted migration did not report verification success.' }

    Write-E2eMessage -Message 'Independent verification: observe destination GitHub-side Pages and workflow-run state without claiming an accidental-activation guarantee.'
    $destinationPages = Get-E2eApiOptionalJson -Path "repos/$destination/pages"
    $runs = Get-E2eApiJson -Path "repos/$destination/actions/runs?per_page=100"

    $summary = [pscustomobject] @{
        Scenario = '-RestorePages omitted'
        MigrationReportedVerified = $result.IsVerified
        RestorePagesRequested = $false
        DestinationPagesConfiguredObserved = $null -ne $destinationPages
        DestinationBuildTypeObserved = if ($destinationPages) { $destinationPages.build_type } else { $null }
        DestinationWorkflowRunsObserved = [int] $runs.total_count
        ActivationGuardClaimed = $false
        Contract = 'Without -RestorePages, copied workflow side effects remain outside the Pages restoration guarantee.'
    }
    $scenarioResults.Add($summary)
}

function Invoke-E2ePagesDriftScenario {
    [CmdletBinding()]
    param()

    Write-E2eMessage -Message 'Scenario: reviewed source Pages configuration drifts before destination Pages mutation'
    $fixture = New-E2eSourceFixture -Name "$repositoryPrefix-drift-source" -PagesMode LegacyDocs
    $destination = "$Owner/$repositoryPrefix-drift-destination"
    $createdRepositories.Add($destination)

    Write-E2eMessage -Message 'Migration evidence: capture immutable main:/docs Pages plan, then change live source Pages to main:/ before executing that exact approved plan.'
    $plan = Copy-GitHubRepository -SourceRepository $fixture.Repository -DestinationRepository $destination -RestorePages -SkipSettings -PlanOnly
    Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @(
        'api', '--hostname', 'github.com', '--method', 'PUT', "repos/$($fixture.Repository)/pages",
        '-f', 'source[branch]=main', '-f', 'source[path]=/'
    ) | Out-Null
    Assert-E2ePagesState -Repository $fixture.Repository -BuildType legacy -Branch main -Path / | Out-Null

    $caught = $null
    try {
        $module = Get-Module CopyGitHubRepo
        & $module {
            param($ApprovedPlan)
            $source = Get-CgrRepository -Repository $ApprovedPlan.SourceRepository -HostName $ApprovedPlan.HostName
            Invoke-CgrApprovedMigrationPlan -Plan $ApprovedPlan -SourceRepository $source -HostName $ApprovedPlan.HostName
        } $plan | Out-Null
    }
    catch {
        $caught = $_
    }

    $errorId = if ($caught) { [string] $caught.FullyQualifiedErrorId } else { $null }
    if ([string]::IsNullOrWhiteSpace($errorId) -or $errorId -notmatch '^PagesStateChangedSincePlanning') {
        throw "Expected PagesStateChangedSincePlanning from exact-plan drift validation, received '$errorId'."
    }
    Write-E2eMessage -Message 'Independent verification: destination may contain copied Git state, but GitHub-side Pages must remain unconfigured after the drift failure.'
    Assert-E2ePagesState -Repository $destination -BuildType NotConfigured | Out-Null

    $summary = [pscustomobject] @{
        Scenario = 'Pages drift before Pages mutation'
        ReviewedSource = 'main:/docs'
        ObservedDriftedSource = 'main:/'
        ExpectedErrorObserved = $true
        ErrorId = $errorId
        DestinationPagesConfigured = $false
        MutableRediscoveryBecameAuthority = $false
    }
    $scenarioResults.Add($summary)
}

function Invoke-E2eSameNameScenario {
    [CmdletBinding()]
    param()

    Write-E2eMessage -Message 'Scenario: same-name Snapshot replacement with Pages and exact destructive confirmation'
    $fixture = New-E2eSourceFixture -Name "$repositoryPrefix-samename-source" -PagesMode LegacyDocs
    $source = $fixture.Repository
    $archiveName = "$repositoryPrefix-samename-archive"
    $archive = "$Owner/$archiveName"
    $createdRepositories.Add($archive)
    $sourceId = Get-E2eRepositoryId -Repository $source
    $confirmation = "SOURCE=$source;ARCHIVE=$archive;REPLACEMENT=$source"

    Write-E2eMessage -Message 'Migration evidence: execute same-name replacement with the exact reviewed archive/replacement confirmation.'
    $result = Copy-GitHubRepository -SourceRepository $source -DestinationRepository $source -RestorePages -SkipSettings -ArchiveRepositoryName $archiveName -SameNameConfirmation $confirmation -NonInteractive -Force
    if (-not $result.IsVerified) { throw 'Same-name Pages replacement did not report verification success.' }

    Write-E2eMessage -Message 'Independent verification: prove archive identity continuity, replacement identity distinction, exact Pages state, and independent approved-plan verification.'
    $archiveId = Get-E2eRepositoryId -Repository $archive
    $replacementId = Get-E2eRepositoryId -Repository $source
    if ($archiveId -ne $sourceId) { throw 'Same-name archive did not preserve original repository identity.' }
    if ($replacementId -eq $sourceId) { throw 'Same-name replacement reused original repository identity.' }
    $destinationPages = Assert-E2ePagesState -Repository $source -BuildType legacy -Branch main -Path /docs
    $verification = Test-GitHubRepositoryMigration -SourceRepository $source -DestinationRepository $source -ContentMode Snapshot -VerifyPages -ApprovedPlan $result.Plan
    if (-not $verification.IsSuccessful -or -not $verification.PagesVerified) { throw 'Independent same-name Pages verification failed.' }

    $summary = [pscustomobject] @{
        Scenario = 'Same-name Snapshot replacement with Pages'
        MigrationReportedVerified = $result.IsVerified
        ArchiveRepository = $archive
        ArchiveIdentityPreserved = $archiveId -eq $sourceId
        ReplacementRepository = $source
        ReplacementIdentityDistinct = $replacementId -ne $sourceId
        DestinationBuildType = $destinationPages.build_type
        DestinationSource = "$($destinationPages.source.branch):$($destinationPages.source.path)"
        ExactDestructiveConfirmationUsed = $true
        IndependentVerificationSucceeded = $verification.IsSuccessful
        PagesVerified = $verification.PagesVerified
    }
    $scenarioResults.Add($summary)
}

function Invoke-E2eCustomDomainSafetyBoundary {
    [CmdletBinding()]
    param()

    Write-E2eMessage -Message 'Scenario: custom-domain handoff and external HTTPS/DNS state at the safest practical lower test boundary'
    Write-E2eMessage -Message 'Migration evidence: no live custom-domain or DNS mutation is attempted because the project has no dedicated disposable domain fixture.'
    Write-E2eMessage -Message 'Independent verification: run established handoff/recovery tests proving exact reviewed-domain sequencing, repository identity checks, external-readiness separation, no DNS mutation, and durable partial-handoff evidence.'

    $paths = @(
        (Join-Path $repositoryRoot 'tests/unit/GitHubPagesRestoration.Tests.ps1'),
        (Join-Path $repositoryRoot 'tests/unit/GitHubPagesCustomDomainRecovery.Tests.ps1')
    )
    $pesterResult = Invoke-Pester -Path $paths -PassThru -Output Detailed
    if ($pesterResult.FailedCount -ne 0) {
        throw "Custom-domain lower-boundary tests failed: $($pesterResult.FailedCount) failing test(s)."
    }

    $summary = [pscustomobject] @{
        Scenario = 'Custom-domain handoff safe lower boundary'
        LiveCustomDomainMutationAttempted = $false
        ExternalDnsMutationAttempted = $false
        DedicatedDisposableDomainFixtureAvailable = $false
        GitHubSideHandoffContractProvenBelowE2E = $true
        ExternalHttpsReadinessTreatedAsMigrated = $false
        LowerBoundaryTestsPassed = $true
        LowerBoundaryPassedCount = $pesterResult.PassedCount
        ResidualFixtureLimitation = 'Live GitHub domain ownership, DNS propagation, domain verification, and certificate readiness require a dedicated disposable external domain fixture and are intentionally not automated.'
    }
    $scenarioResults.Add($summary)
}

if ($Owner -notmatch '^[A-Za-z0-9_.-]+$') { throw "Owner '$Owner' is not valid." }

Write-E2eMessage -Message 'GitHub Pages Migration End-to-End Validation'
Write-E2eMessage -Message '--------------------------------------------'
Write-E2eMessage -Message 'Goal: Prove supported GitHub Pages migration across real Git/GitHub boundaries without treating repository files or migration output as independent Pages evidence.'
Write-E2eMessage -Message 'Evidence is separated into migration-reported evidence and independent GitHub verification evidence.'
Write-E2eMessage -Message 'External DNS, domain-verification, and certificate state are outside deterministic repository migration and are never mutated by this harness.'
Write-E2eMessage

Assert-E2eCleanupCapability
Import-Module $modulePath -Force -ErrorAction Stop
Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

try {
    Invoke-E2eActionsSnapshotScenario
    Invoke-E2eLegacyFullHistoryScenario
    Invoke-E2eNoPagesScenario
    Invoke-E2eRestorePagesOmittedScenario
    Invoke-E2ePagesDriftScenario
    Invoke-E2eSameNameScenario
    Invoke-E2eCustomDomainSafetyBoundary

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
                Write-Warning "Failed to clean up Pages E2E repository '$repository'. $($_.Exception.Message)"
            }
        }
    }
    else {
        Write-Warning "Pages E2E repositories were retained because -KeepRepositories was supplied: $(@($createdRepositories) -join ', ')"
    }

    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
