function Test-GitHubRepositoryMigration {
    <#
    .SYNOPSIS
    Verifies a GitHub repository migration.

    .DESCRIPTION
    Performs read-only verification of a completed repository migration. Snapshot
    verification compares the source and destination default-branch Git trees
    and confirms the destination has the expected single-root-commit history
    shape. FullHistory verification compares ordinary branch and tag targets,
    reachable commit counts, branch-tip trees, the default branch, and reachable
    Git LFS object availability.

    FullHistory verification can additionally compare selected GitHub Releases and
    release assets by using -IncludeReleases. The release-selection parameters use
    the same semantics as Copy-GitHubRepository: stable non-draft releases are the
    default, tag include/exclude wildcard patterns can narrow the set, prereleases
    and drafts require explicit opt-in, and -ReleaseCount limits the newest matches.

    Release verification is read-only and compares the currently selected source
    release state with destination releases. It verifies tag commit identity,
    supported release metadata, asset metadata, and the Latest designation when the
    source Latest release is part of the selected set. Extra destination releases
    outside the selected source set do not cause verification failure.

    The default content mode is Snapshot. Use the same content mode that was used
    for the migration. The command does not repair a failed verification and does
    not mutate either repository. The current release line supports github.com only.

    .PARAMETER SourceRepository
    Specifies the source repository as owner/name. The repository must exist and
    be visible to the authenticated GitHub account.

    .PARAMETER DestinationRepository
    Specifies the destination repository as owner/name. This is the repository
    whose migrated content is verified against the source.

    .PARAMETER ContentMode
    Selects the verification contract. Snapshot is the default and verifies the
    default-branch tree plus the destination's single-root-commit history shape.
    FullHistory verifies branches, tags, reachable commit counts, branch-tip
    trees, the default branch, and reachable Git LFS object availability.

    .PARAMETER IncludeReleases
    Adds read-only GitHub Release verification to FullHistory verification. Stable,
    non-draft source releases are selected by default. Snapshot does not support
    GitHub Release verification.

    .PARAMETER ReleaseTag
    Includes only source GitHub Releases whose tag names match one or more
    PowerShell wildcard patterns. Exact tag names are valid patterns.

    .PARAMETER ReleaseExcludeTag
    Excludes source GitHub Releases whose tag names match one or more PowerShell
    wildcard patterns after include filtering.

    .PARAMETER IncludePrerelease
    Includes GitHub Releases marked as prereleases. Prereleases are excluded by
    default.

    .PARAMETER IncludeDraftReleases
    Includes draft GitHub Releases. Draft releases are excluded by default.

    .PARAMETER ReleaseCount
    Limits release verification to the newest N releases remaining after the other
    release filters are applied. Ordering uses publication time and then creation
    time.

    .PARAMETER HostName
    Specifies the GitHub host used for discovery and authentication. The default
    is github.com. The current release line supports github.com only.

    .EXAMPLE
    Test-GitHubRepositoryMigration `
        -SourceRepository infoconex/source `
        -DestinationRepository infoconex/destination

    Verifies a Snapshot migration, which is the default content mode.

    .EXAMPLE
    Test-GitHubRepositoryMigration `
        -SourceRepository infoconex/source `
        -DestinationRepository infoconex/destination `
        -ContentMode FullHistory

    Verifies a FullHistory migration including ordinary branches, tags, reachable
    history, branch-tip trees, default branch, and reachable Git LFS objects.

    .EXAMPLE
    Test-GitHubRepositoryMigration `
        -SourceRepository infoconex/source `
        -DestinationRepository infoconex/destination `
        -ContentMode FullHistory `
        -IncludeReleases `
        -ReleaseTag 'v2.*' `
        -ReleaseCount 3

    Verifies FullHistory plus the three newest stable, non-draft source GitHub
    Releases whose tags match v2.*.

    .INPUTS
    None. This command does not accept pipeline input.

    .OUTPUTS
    CopyGitHubRepo.SnapshotVerificationResult or
    CopyGitHubRepo.FullHistoryVerificationResult. FullHistory results include a
    ReleaseVerification property when -IncludeReleases is requested. The returned
    IsSuccessful value reflects both Git/LFS and requested release verification.

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

    if ($IncludeReleases -and $ContentMode -ne 'FullHistory') {
        $message = 'GitHub Release verification is currently supported only with -ContentMode FullHistory.'
        $exception = [System.NotSupportedException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'SnapshotReleaseVerificationNotImplemented',
            [System.Management.Automation.ErrorCategory]::NotImplemented,
            'IncludeReleases'
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
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
