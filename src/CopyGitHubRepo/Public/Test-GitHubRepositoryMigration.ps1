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

    Snapshot -IncludeReleases requires -ApprovedPlan so verification cannot rerun live release
    selection, filtering, or topology discovery and silently redefine the expected state.
    The approved plan can be taken from the Plan property returned by Copy-GitHubRepository.
    Verification never repairs or mutates either repository.

    .PARAMETER SourceRepository
    Specifies the source repository as owner/name. For Snapshot -IncludeReleases this name is
    retained for result identity while immutable approved evidence defines expected state.

    .PARAMETER DestinationRepository
    Specifies the destination repository as owner/name. This is the repository whose migrated
    content and releases are independently read and verified.

    .PARAMETER ContentMode
    Selects the verification contract. Snapshot is the default. FullHistory preserves the
    existing branch/tag/history/LFS verification contract.

    .PARAMETER IncludeReleases
    Adds GitHub Release verification. FullHistory uses the existing live source-selection
    contract. Snapshot requires -ApprovedPlan and verifies exactly its reviewed selection.

    .PARAMETER ReleaseTag
    Includes only source GitHub Releases whose tag names match one or more PowerShell wildcard
    patterns for FullHistory verification. Snapshot approved-plan verification does not accept
    live release filters because the reviewed plan is authoritative.

    .PARAMETER ReleaseExcludeTag
    Excludes source GitHub Releases whose tag names match one or more PowerShell wildcard
    patterns for FullHistory verification.

    .PARAMETER IncludePrerelease
    Includes source prereleases in FullHistory release verification.

    .PARAMETER IncludeDraftReleases
    Includes source draft releases in FullHistory release verification.

    .PARAMETER ReleaseCount
    Limits FullHistory release verification to the newest N selected source releases.

    .PARAMETER ApprovedPlan
    Supplies the immutable reviewed CopyGitHubRepo migration plan for Snapshot -IncludeReleases
    verification. ReleaseCheckpointPlan and ReleaseSelection from this object are consumed as
    expected evidence; verification does not rerun live source release selection or ordering.

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

    .INPUTS
    None. This command does not accept pipeline input.

    .OUTPUTS
    CopyGitHubRepo.MigrationVerificationResult. When release verification is requested, the
    result includes ReleaseVerification and ReleasesVerified and IsSuccessful reflects both
    Git content and GitHub Release verification.

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

    if ($ApprovedPlan -and -not ($ContentMode -eq 'Snapshot' -and $IncludeReleases)) {
        $message = '-ApprovedPlan is supported only with -ContentMode Snapshot -IncludeReleases.'
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'ApprovedPlanRequiresSnapshotReleaseVerification',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            'ApprovedPlan'
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    if ($ContentMode -eq 'Snapshot' -and $IncludeReleases) {
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

    if ($ContentMode -eq 'Snapshot' -and $IncludeReleases) {
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

        return $result
    }

    Invoke-CgrRepositorySnapshotVerification `
        -SourceRepository $source `
        -DestinationRepository $destination
}
