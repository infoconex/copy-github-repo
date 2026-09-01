function Test-GitHubRepositoryMigration {
    <#
    .SYNOPSIS
    Verifies a GitHub repository migration.

    .DESCRIPTION
    Performs read-only verification of a completed repository migration. Plain Snapshot
    verification compares the source and destination default-branch Git trees and confirms
    the destination has the expected single-root-commit history shape. Snapshot migrations
    that preserved GitHub Releases are verified from the immutable migration plan reviewed
    before execution: generated checkpoint order and parentage, checkpoint tree equivalence,
    selected release-tag targets, reviewed source HEAD state, recreated GitHub Release
    metadata/assets, and Latest designation are read independently from the destination.

    FullHistory verification compares ordinary branch and tag targets, reachable commit
    counts, branch-tip trees, the default branch, and reachable Git LFS object availability.
    FullHistory release verification retains its existing live source-selection behavior.

    -VerifyPages extends the independent verification boundary using immutable Pages evidence
    from -ApprovedPlan. It reads GitHub-side Pages configuration from the destination and
    compares configured state, build type, exact legacy branch/path, custom domain, and
    deterministic HTTPS-enforcement intent. Replacement verification also proves the reviewed
    production domain is absent from the archive and present on the replacement. External DNS,
    domain-verification, and certificate readiness are reported separately and never treated
    as migrated configuration.

    Snapshot -IncludeReleases requires -ApprovedPlan so verification cannot rerun live release
    selection, filtering, or topology discovery and silently redefine the expected state.
    -VerifyPages likewise requires -ApprovedPlan so mutable live source Pages discovery never
    becomes verification authority. The approved plan can be taken from the Plan property
    returned by Copy-GitHubRepository. Verification never repairs or mutates either repository.

    .PARAMETER SourceRepository
    Specifies the source repository as owner/name. For approved-plan verification this name is
    checked against the reviewed plan while immutable evidence defines the expected state.

    .PARAMETER DestinationRepository
    Specifies the destination repository as owner/name. This is the repository whose migrated
    state is independently read and verified.

    .PARAMETER ContentMode
    Selects the verification contract. Snapshot is the default. FullHistory preserves the
    existing branch/tag/history/LFS verification contract.

    .PARAMETER IncludeReleases
    Adds GitHub Release verification. FullHistory uses the existing live source-selection
    contract. Snapshot requires -ApprovedPlan and verifies exactly its reviewed selection.

    .PARAMETER VerifyPages
    Adds read-only GitHub Pages verification from immutable Pages evidence in -ApprovedPlan.
    This does not query, copy, or mutate DNS, domain-verification, or certificate state.

    .PARAMETER ReleaseTag
    Includes only source GitHub Releases whose tag names match one or more PowerShell wildcard
    patterns for FullHistory verification. Snapshot approved-plan verification does not accept
    live release filters because the reviewed plan is authoritative.

    .PARAMETER ReleaseExcludeTag
    Excludes source GitHub Releases whose tag names match one or more PowerShell wildcard
    patterns for FullHistory release verification.

    .PARAMETER IncludePrerelease
    Includes source prereleases in FullHistory release verification.

    .PARAMETER IncludeDraftReleases
    Includes source draft releases in FullHistory release verification.

    .PARAMETER ReleaseCount
    Limits FullHistory release verification to the newest N selected source releases.

    .PARAMETER ApprovedPlan
    Supplies the immutable reviewed CopyGitHubRepo migration plan for Snapshot release and/or
    GitHub Pages verification. Pages verification consumes Plan.Pages as expected evidence and
    never reruns live source Pages discovery as authority.

    .PARAMETER HostName
    Specifies the GitHub host used for discovery and authentication. The default is github.com.

    .EXAMPLE
    Test-GitHubRepositoryMigration `
        -SourceRepository infoconex/source `
        -DestinationRepository infoconex/destination

    Verifies a plain Snapshot migration.

    .EXAMPLE
    Test-GitHubRepositoryMigration `
        -SourceRepository infoconex/source `
        -DestinationRepository infoconex/destination `
        -ContentMode FullHistory `
        -IncludeReleases `
        -ReleaseTag 'v2.*'

    Verifies FullHistory plus the selected live source releases using the existing contract.

    .EXAMPLE
    Test-GitHubRepositoryMigration `
        -SourceRepository infoconex/source `
        -DestinationRepository infoconex/destination `
        -ContentMode Snapshot `
        -IncludeReleases `
        -ApprovedPlan $migration.Plan

    Independently verifies Snapshot release checkpoints and recreated releases from the exact
    immutable evidence that was reviewed before migration execution.

    .EXAMPLE
    Test-GitHubRepositoryMigration `
        -SourceRepository infoconex/source `
        -DestinationRepository infoconex/destination `
        -ContentMode Snapshot `
        -VerifyPages `
        -ApprovedPlan $migration.Plan

    Independently verifies supported destination GitHub Pages state from reviewed plan evidence.

    .INPUTS
    None. This command does not accept pipeline input.

    .OUTPUTS
    CopyGitHubRepo.MigrationVerificationResult. When Pages verification is requested, the
    result includes PagesVerification and PagesVerified and IsSuccessful reflects both Git
    content and Pages verification. External readiness is evidence only and is not migration
    success criteria.

    .LINK
    https://github.com/infoconex/copy-github-repo

    .LINK
    https://github.com/infoconex/copy-github-repo/blob/main/docs/product/product-contract.md
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
        [string] $SourceRepository,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
        [string] $DestinationRepository,

        [ValidateSet('Snapshot', 'FullHistory')]
        [string] $ContentMode = 'Snapshot',

        [switch] $IncludeReleases,

        [switch] $VerifyPages,

        [string[]] $ReleaseTag,

        [string[]] $ReleaseExcludeTag,

        [switch] $IncludePrerelease,

        [switch] $IncludeDraftReleases,

        [ValidateRange(1, [int]::MaxValue)]
        [int] $ReleaseCount,

        [psobject] $ApprovedPlan,

        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com'
    )

    Assert-CgrSupportedHostName -HostName $HostName

    $releaseFilterWasSpecified = $PSBoundParameters.ContainsKey('ReleaseTag') -or
    $PSBoundParameters.ContainsKey('ReleaseExcludeTag') -or
    $IncludePrerelease -or
    $IncludeDraftReleases -or
    $PSBoundParameters.ContainsKey('ReleaseCount')

    if ($releaseFilterWasSpecified -and -not $IncludeReleases) {
        $message = 'Release verification filter parameters require -IncludeReleases.'
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'ReleaseFilterRequiresIncludeReleases',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            'IncludeReleases'
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $snapshotReleaseVerification = $ContentMode -eq 'Snapshot' -and $IncludeReleases
    if ($ApprovedPlan -and -not ($snapshotReleaseVerification -or $VerifyPages)) {
        $message = '-ApprovedPlan is supported only with -ContentMode Snapshot -IncludeReleases unless -VerifyPages is requested.'
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'ApprovedPlanRequiresSnapshotReleaseVerification',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            'ApprovedPlan'
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    if ($VerifyPages) {
        if (-not $ApprovedPlan) {
            $message = 'GitHub Pages verification requires -ApprovedPlan so expected Pages state comes from immutable reviewed evidence.'
            $exception = [System.InvalidOperationException]::new($message)
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'PagesVerificationPlanRequired',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                'ApprovedPlan'
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $approvedPages = Get-CgrObjectProperty -InputObject $ApprovedPlan -Name 'Pages'
        $approvedRestorePages = [bool] (Get-CgrObjectProperty -InputObject $ApprovedPlan -Name 'RestorePages')
        $approvedContentMode = [string] (Get-CgrObjectProperty -InputObject $ApprovedPlan -Name 'ContentMode')
        $approvedSource = [string] (Get-CgrObjectProperty -InputObject $ApprovedPlan -Name 'SourceRepository')
        $approvedDestination = [string] (Get-CgrObjectProperty -InputObject $ApprovedPlan -Name 'DestinationRepository')
        $approvedHost = [string] (Get-CgrObjectProperty -InputObject $ApprovedPlan -Name 'HostName')
        if (-not $approvedRestorePages -or $null -eq $approvedPages -or
            $approvedContentMode -ne $ContentMode -or
            -not [string]::Equals($approvedSource, $SourceRepository, [System.StringComparison]::OrdinalIgnoreCase) -or
            -not [string]::Equals($approvedDestination, $DestinationRepository, [System.StringComparison]::OrdinalIgnoreCase) -or
            (-not [string]::IsNullOrWhiteSpace($approvedHost) -and -not [string]::Equals($approvedHost, $HostName, [System.StringComparison]::OrdinalIgnoreCase))) {
            $message = 'The supplied approved plan does not contain Pages restoration evidence bound to the requested source, destination, content mode, and GitHub host.'
            $exception = [System.InvalidOperationException]::new($message)
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'PagesVerificationPlanInvalid',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                'ApprovedPlan'
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }

    if ($snapshotReleaseVerification) {
        if (-not $ApprovedPlan) {
            $message = 'Snapshot release verification requires -ApprovedPlan so expected checkpoints and releases come from immutable reviewed evidence.'
            $exception = [System.InvalidOperationException]::new($message)
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'SnapshotReleaseVerificationPlanRequired',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                'ApprovedPlan'
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
        if ($releaseFilterWasSpecified) {
            $message = 'Snapshot release verification cannot use live release filters with -ApprovedPlan. The reviewed release selection is authoritative.'
            $exception = [System.InvalidOperationException]::new($message)
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'SnapshotReleaseVerificationFiltersNotAllowed',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                'ApprovedPlan'
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $approvedContentMode = [string] (Get-CgrObjectProperty -InputObject $ApprovedPlan -Name 'ContentMode')
        $approvedIncludeReleases = [bool] (Get-CgrObjectProperty -InputObject $ApprovedPlan -Name 'IncludeReleases')
        $checkpointPlan = Get-CgrObjectProperty -InputObject $ApprovedPlan -Name 'ReleaseCheckpointPlan'
        $approvedSelection = Get-CgrObjectProperty -InputObject $ApprovedPlan -Name 'ReleaseSelection'
        if ($approvedContentMode -ne 'Snapshot' -or -not $approvedIncludeReleases -or $null -eq $checkpointPlan -or $null -eq $approvedSelection) {
            $message = 'The supplied approved plan does not contain complete Snapshot -IncludeReleases verification evidence.'
            $exception = [System.InvalidOperationException]::new($message)
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'SnapshotReleaseVerificationPlanInvalid',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                'ApprovedPlan'
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }

    $prerequisites = Get-CgrPrerequisiteStatus -HostName $HostName
    if (-not $prerequisites.Git.Found) {
        $exception = [System.InvalidOperationException]::new(
            "Git is required for repository migration verification. Install 'git' from https://git-scm.com/."
        )
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'GitNotFound',
            [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
            'git'
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    if (-not $prerequisites.GitHubCli.Found) {
        $exception = [System.InvalidOperationException]::new(
            "GitHub CLI is required for repository migration verification. Install 'gh' from https://cli.github.com/."
        )
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'GitHubCliNotFound',
            [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
            'gh'
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    if (-not $prerequisites.Authentication.Authenticated) {
        $exception = [System.InvalidOperationException]::new($prerequisites.Authentication.Message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'GitHubCliNotAuthenticated',
            [System.Management.Automation.ErrorCategory]::SecurityError,
            $HostName
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    if ($snapshotReleaseVerification) {
        $destination = Get-CgrRepository -Repository $DestinationRepository -HostName $HostName
        $approvedSourceName = [string] (Get-CgrObjectProperty -InputObject $ApprovedPlan -Name 'SourceRepository')
        $source = [pscustomobject] @{
            FullName = if ([string]::IsNullOrWhiteSpace($approvedSourceName)) { $SourceRepository } else { $approvedSourceName }
            HostName = $HostName
        }

        $result = Invoke-CgrApprovedSnapshotReleaseVerification `
            -SourceRepository $source `
            -DestinationRepository $destination `
            -ReleaseCheckpointPlan $checkpointPlan

        $gitContentSuccessful = [bool] $result.IsSuccessful
        $targetEvidenceComplete = @($result.ReleaseTags).Count -eq @($approvedSelection.Releases).Count -and
        -not @($result.ReleaseTags | Where-Object { [string]::IsNullOrWhiteSpace([string] $_.DestinationCommitSha) })
        $releaseVerification = $null
        if ($targetEvidenceComplete) {
            $releaseVerification = Test-CgrGitHubReleaseMigration `
                -SourceRepository $source `
                -DestinationRepository $destination `
                -ApprovedSelection $approvedSelection `
                -DestinationTagTargets @($result.ReleaseTags) `
                -RequireExactDestinationReleaseSet `
                -HostName $HostName
        }

        $releasesVerified = [bool] ($releaseVerification -and $releaseVerification.IsSuccessful)
        $result | Add-Member -NotePropertyName GitContentSuccessful -NotePropertyValue $gitContentSuccessful -Force
        $result | Add-Member -NotePropertyName ReleaseVerification -NotePropertyValue $releaseVerification -Force
        $result | Add-Member -NotePropertyName ReleasesVerified -NotePropertyValue $releasesVerified -Force
        $result | Add-Member -NotePropertyName IsSuccessful -NotePropertyValue ([bool] ($gitContentSuccessful -and $releasesVerified)) -Force

        if ($VerifyPages) {
            $beforePagesSuccessful = [bool] $result.IsSuccessful
            $pagesVerification = Test-CgrGitHubPagesMigration -Plan $ApprovedPlan -DestinationRepository $destination -HostName $HostName
            $result | Add-Member -NotePropertyName PagesVerification -NotePropertyValue $pagesVerification -Force
            $result | Add-Member -NotePropertyName PagesVerified -NotePropertyValue ([bool] $pagesVerification.IsSuccessful) -Force
            $result | Add-Member -NotePropertyName IsSuccessful -NotePropertyValue ([bool] ($beforePagesSuccessful -and $pagesVerification.IsSuccessful)) -Force
        }
        return $result
    }

    $source = Get-CgrRepository -Repository $SourceRepository -HostName $HostName
    $destination = Get-CgrRepository -Repository $DestinationRepository -HostName $HostName

    if ($ContentMode -eq 'FullHistory') {
        $result = Invoke-CgrRepositoryFullHistoryVerification `
            -SourceRepository $source `
            -DestinationRepository $destination

        if ($IncludeReleases) {
            $releaseVerificationParameters = @{
                SourceRepository = $source
                DestinationRepository = $destination
                ReleaseTag = $ReleaseTag
                ReleaseExcludeTag = $ReleaseExcludeTag
                IncludePrerelease = $IncludePrerelease
                IncludeDraftReleases = $IncludeDraftReleases
                HostName = $HostName
            }
            if ($PSBoundParameters.ContainsKey('ReleaseCount')) {
                $releaseVerificationParameters.ReleaseCount = $ReleaseCount
            }

            $gitContentSuccessful = [bool] $result.IsSuccessful
            $releaseVerification = Test-CgrGitHubReleaseMigration @releaseVerificationParameters
            $result | Add-Member -NotePropertyName GitContentSuccessful -NotePropertyValue $gitContentSuccessful -Force
            $result | Add-Member -NotePropertyName ReleaseVerification -NotePropertyValue $releaseVerification -Force
            $result | Add-Member -NotePropertyName ReleasesVerified -NotePropertyValue ([bool] $releaseVerification.IsSuccessful) -Force
            $result | Add-Member -NotePropertyName IsSuccessful -NotePropertyValue ([bool] ($gitContentSuccessful -and $releaseVerification.IsSuccessful)) -Force
        }

        if ($VerifyPages) {
            $beforePagesSuccessful = [bool] $result.IsSuccessful
            $pagesVerification = Test-CgrGitHubPagesMigration -Plan $ApprovedPlan -DestinationRepository $destination -HostName $HostName
            $result | Add-Member -NotePropertyName PagesVerification -NotePropertyValue $pagesVerification -Force
            $result | Add-Member -NotePropertyName PagesVerified -NotePropertyValue ([bool] $pagesVerification.IsSuccessful) -Force
            $result | Add-Member -NotePropertyName IsSuccessful -NotePropertyValue ([bool] ($beforePagesSuccessful -and $pagesVerification.IsSuccessful)) -Force
        }

        return $result
    }

    $approvedSourceState = if ($VerifyPages) { Get-CgrObjectProperty -InputObject $ApprovedPlan -Name 'SourceState' } else { $null }
    $result = Invoke-CgrRepositorySnapshotVerification `
        -SourceRepository $source `
        -DestinationRepository $destination `
        -ApprovedSourceState $approvedSourceState

    if ($VerifyPages) {
        $gitContentSuccessful = [bool] $result.IsSuccessful
        $pagesVerification = Test-CgrGitHubPagesMigration -Plan $ApprovedPlan -DestinationRepository $destination -HostName $HostName
        $result | Add-Member -NotePropertyName GitContentSuccessful -NotePropertyValue $gitContentSuccessful -Force
        $result | Add-Member -NotePropertyName PagesVerification -NotePropertyValue $pagesVerification -Force
        $result | Add-Member -NotePropertyName PagesVerified -NotePropertyValue ([bool] $pagesVerification.IsSuccessful) -Force
        $result | Add-Member -NotePropertyName IsSuccessful -NotePropertyValue ([bool] ($gitContentSuccessful -and $pagesVerification.IsSuccessful)) -Force
    }

    return $result
}
