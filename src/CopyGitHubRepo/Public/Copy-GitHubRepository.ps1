function Copy-GitHubRepository {
    <#
    .SYNOPSIS
    Publishes or copies a GitHub repository from an approved repository copy plan.

    .DESCRIPTION
    Plans or executes a GitHub repository copy. Snapshot is the default and
    publishes the approved source default-branch content as one unrelated root
    commit without prior Git history, other branches, or tags. FullHistory is
    explicit and preserves the approved branches, tags, commits, and reachable
    Git LFS objects.

    FullHistory can optionally preserve selected GitHub Releases and their assets.
    Release selection is stable/non-draft by default and can be narrowed with tag
    include/exclude patterns or a newest-N limit. Prereleases and draft releases
    require explicit opt-in. Snapshot -IncludeReleases is available for PlanOnly
    review; mutating Snapshot release-checkpoint execution is not implemented yet.

    Planning captures immutable source-state evidence. Execution uses that same
    plan and fails closed with SourceStateChangedSincePlanning if the source no
    longer matches the approved state before mutation. Selected releases are also
    captured in the plan and revalidated before release restoration.

    An existing destination is never silently overwritten. Replacement requires
    an explicit archive plan and exact confirmation, and the prior repository is
    preserved before a fresh replacement is created. -Force does not bypass exact
    replacement confirmation.

    After content verification, approved GitHub Releases are restored when
    requested, followed by supported repository settings and transferable
    repository protection. -SkipSettings skips only the settings/protection stages.

    Mutating execution supports -WhatIf and -Confirm. Non-interactive mutation
    requires -Force. Changing destination visibility requires -Force. GitHub Pages
    restoration and Actions activation are reserved switches and are not yet
    implemented for mutating execution. Version 1 supports github.com only.

    .PARAMETER SourceRepository
    Specifies the source repository as owner/name. The source must exist and have
    a default branch with content. Planning captures immutable source Git state.

    .PARAMETER DestinationRepository
    Specifies the destination as owner/name. A different existing destination is
    never overwritten; use -ExistingDestinationArchiveName to archive and replace
    it explicitly. The same owner/name selects same-name replacement.

    .PARAMETER ContentMode
    Selects Snapshot or FullHistory. Snapshot is the default clean-publication
    mode. FullHistory preserves approved Git history, branches, tags, and reachable
    Git LFS objects.

    .PARAMETER IncludeReleases
    Requests GitHub Release preservation. FullHistory supports planning and execution.
    Snapshot supports PlanOnly review of immutable release-checkpoint evidence; its
    mutating checkpoint/release execution is implemented by dependent work.

    .PARAMETER ReleaseTag
    Includes only GitHub Releases whose tag names match one or more PowerShell
    wildcard patterns. Exact tag names are valid patterns.

    .PARAMETER ReleaseExcludeTag
    Excludes GitHub Releases whose tag names match one or more PowerShell wildcard
    patterns after include filtering.

    .PARAMETER IncludePrerelease
    Includes GitHub Releases marked as prereleases. Prereleases are excluded by
    default even when -IncludeReleases is specified.

    .PARAMETER IncludeDraftReleases
    Includes draft GitHub Releases. Draft releases are excluded by default.

    .PARAMETER ReleaseCount
    Limits the selected releases to the newest N after all other release filters
    are applied. Ordering uses release publication time, then creation time.

    .PARAMETER DestinationVisibility
    Specifies public, private, or internal destination visibility. If omitted,
    source visibility is preserved. A deliberate visibility change requires -Force.

    .PARAMETER ArchiveRepositoryName
    Specifies the archive repository name for same-name replacement. The archive
    must not already exist.

    .PARAMETER SameNameConfirmation
    Supplies the exact case-sensitive confirmation for same-name replacement in
    SOURCE=owner/source;ARCHIVE=owner/archive;REPLACEMENT=owner/source form.
    -Force and -Confirm:$false do not bypass this requirement.

    .PARAMETER ExistingDestinationArchiveName
    Specifies the archive repository name used to preserve an already-existing
    different destination before creating its replacement.

    .PARAMETER ExistingDestinationConfirmation
    Supplies the exact case-sensitive confirmation for an existing-destination
    replacement in DESTINATION=owner/destination;ARCHIVE=owner/archive;REPLACEMENT=owner/destination form.
    -Force and -Confirm:$false do not bypass this requirement.

    .PARAMETER CommitMessage
    Specifies the Snapshot root commit message. The default is 'Initial repository commit'.
    FullHistory preserves existing commits and does not rewrite them.

    .PARAMETER RestorePages
    Requests GitHub Pages restoration. Planning records the request, but mutating
    execution rejects it because Pages restoration is not yet implemented.

    .PARAMETER EnableActionsAfterMigration
    Requests Actions activation after the copy. Planning records the request, but
    mutating execution rejects it because this behavior is not yet implemented.

    .PARAMETER SkipSettings
    Skips restoration of supported repository settings and repository protection.
    Content verification and requested release restoration still run.

    .PARAMETER PlanOnly
    Returns a read-only repository copy plan without mutation. The plan contains
    immutable source-state evidence used to bind later review and execution.

    .PARAMETER NonInteractive
    Prevents interactive confirmation prompts. Non-interactive mutation requires
    -Force, and replacement modes still require exact confirmation values.

    .PARAMETER OutputMode
    Selects PlanOnly output: Interactive returns the structured plan, Plain returns
    Markdown, and Json returns JSON. Execution always returns structured results.

    .PARAMETER ReportPath
    Writes the plan or execution report to the selected path. Recovery reporting
    uses this as the preferred path when mutation has begun.

    .PARAMETER HostName
    Specifies the GitHub host. The default is github.com. Version 1 supports
    github.com only.

    .PARAMETER Force
    Acknowledges non-interactive mutation and deliberate visibility changes and
    suppresses routine confirmation prompts. Force does not bypass exact archive
    and replacement confirmation.

    .EXAMPLE
    Copy-GitHubRepository -SourceRepository infoconex/source -DestinationRepository infoconex/destination -PlanOnly

    Creates a read-only Snapshot repository copy plan with immutable source commit
    and tree evidence.

    .EXAMPLE
    Copy-GitHubRepository -SourceRepository infoconex/source -DestinationRepository infoconex/destination

    Publishes the approved Snapshot source state as one new unrelated root commit,
    verifies it, and restores supported configuration.

    .EXAMPLE
    Copy-GitHubRepository -SourceRepository infoconex/source -DestinationRepository infoconex/destination -ContentMode FullHistory

    Copies and verifies the approved history-preserving branch/tag/ref state.

    .EXAMPLE
    Copy-GitHubRepository -SourceRepository infoconex/source -DestinationRepository infoconex/destination -ContentMode FullHistory -IncludeReleases -ReleaseTag 'v2.*' -ReleaseCount 3

    Copies FullHistory and restores the three newest stable non-draft GitHub Releases
    whose tags match v2.*, including their release assets.

    .INPUTS
    None. This command does not accept pipeline input.

    .OUTPUTS
    CopyGitHubRepo.MigrationPlan for structured planning, System.String for Plain
    or Json plan output, and CopyGitHubRepo.MigrationExecutionResult for execution.

    .LINK
    https://github.com/infoconex/copy-github-repo

    .LINK
    https://github.com/infoconex/copy-github-repo/blob/main/docs/product/product-contract.md
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
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

        [ValidateSet('public', 'private', 'internal')]
        [string] $DestinationVisibility,

        [ValidatePattern('^[A-Za-z0-9_.-]+$')]
        [string] $ArchiveRepositoryName,

        [string] $SameNameConfirmation,

        [ValidatePattern('^[A-Za-z0-9_.-]+$')]
        [string] $ExistingDestinationArchiveName,

        [string] $ExistingDestinationConfirmation,

        [ValidateNotNullOrEmpty()]
        [string] $CommitMessage = 'Initial repository commit',

        [switch] $RestorePages,

        [switch] $EnableActionsAfterMigration,

        [switch] $SkipSettings,

        [switch] $PlanOnly,

        [switch] $NonInteractive,

        [ValidateSet('Interactive', 'Plain', 'Json')]
        [string] $OutputMode = 'Interactive',

        [string] $ReportPath,

        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com',

        [switch] $Force
    )

    Assert-CgrSupportedHostName -HostName $HostName

    $releaseFilterWasSpecified = $PSBoundParameters.ContainsKey('ReleaseTag') -or
    $PSBoundParameters.ContainsKey('ReleaseExcludeTag') -or
    $IncludePrerelease -or
    $IncludeDraftReleases -or
    $PSBoundParameters.ContainsKey('ReleaseCount')

    if ($releaseFilterWasSpecified -and -not $IncludeReleases) {
        $message = 'Release filter parameters require -IncludeReleases.'
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'ReleaseFilterRequiresIncludeReleases', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'IncludeReleases')
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    if ($IncludeReleases -and $ContentMode -eq 'Snapshot' -and -not $PlanOnly) {
        $message = 'Snapshot -IncludeReleases execution is not implemented yet. Use -PlanOnly to review the immutable release-checkpoint plan.'
        $exception = [System.NotSupportedException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'SnapshotReleaseMigrationNotImplemented', [System.Management.Automation.ErrorCategory]::NotImplemented, 'IncludeReleases')
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $prerequisites = Get-CgrPrerequisiteStatus -HostName $HostName
    if (-not $prerequisites.Git.Found) {
        $exception = [System.InvalidOperationException]::new("Git is required for repository copy planning. Install 'git' from https://git-scm.com/.")
        $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'GitNotFound', [System.Management.Automation.ErrorCategory]::ResourceUnavailable, 'git')
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
    if (-not $prerequisites.GitHubCli.Found) {
        $exception = [System.InvalidOperationException]::new("GitHub CLI is required for repository copy planning. Install 'gh' from https://cli.github.com/.")
        $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'GitHubCliNotFound', [System.Management.Automation.ErrorCategory]::ResourceUnavailable, 'gh')
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
    if (-not $prerequisites.Authentication.Authenticated) {
        $exception = [System.InvalidOperationException]::new($prerequisites.Authentication.Message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'GitHubCliNotAuthenticated', [System.Management.Automation.ErrorCategory]::SecurityError, $HostName)
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $source = Get-CgrRepository -Repository $SourceRepository -HostName $HostName
    $destinationVisibilityWasProvided = $PSBoundParameters.ContainsKey('DestinationVisibility')
    $resolvedDestinationVisibility = if ($destinationVisibilityWasProvided) { $DestinationVisibility } else { $source.Visibility }

    $planParameters = @{
        SourceRepository = $source
        DestinationRepository = $DestinationRepository
        ContentMode = $ContentMode
        DestinationVisibility = $resolvedDestinationVisibility
        ArchiveRepositoryName = $ArchiveRepositoryName
        ExistingDestinationArchiveName = $ExistingDestinationArchiveName
        CommitMessage = $CommitMessage
        RestorePages = $RestorePages
        EnableActionsAfterMigration = $EnableActionsAfterMigration
        SkipSettings = $SkipSettings
        HostName = $HostName
        PlanOnly = $PlanOnly
        IncludeReleases = $IncludeReleases
        ReleaseTag = $ReleaseTag
        ReleaseExcludeTag = $ReleaseExcludeTag
        IncludePrerelease = $IncludePrerelease
        IncludeDraftReleases = $IncludeDraftReleases
    }
    if ($PSBoundParameters.ContainsKey('ReleaseCount')) {
        $planParameters.ReleaseCount = $ReleaseCount
    }

    $plan = New-CgrMigrationPlan @planParameters

    if ($PlanOnly) {
        if ($ReportPath) { Write-CgrMigrationPlanReport -Plan $plan -Path $ReportPath }
        if ($OutputMode -eq 'Json') { return Format-CgrMigrationPlan -Plan $plan -Format Json }
        if ($OutputMode -eq 'Plain') { return Format-CgrMigrationPlan -Plan $plan -Format Markdown }
        return $plan
    }

    if ($RestorePages) {
        $message = 'Pages restoration is not implemented yet. Remove -RestorePages and review the plan output for unsupported settings.'
        $exception = [System.NotSupportedException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'RestorePagesExecutionNotImplemented', [System.Management.Automation.ErrorCategory]::NotImplemented, 'RestorePages')
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
    if ($EnableActionsAfterMigration) {
        $message = 'Actions activation after repository copy is not implemented yet. Remove -EnableActionsAfterMigration and review the plan output.'
        $exception = [System.NotSupportedException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'EnableActionsAfterMigrationExecutionNotImplemented', [System.Management.Automation.ErrorCategory]::NotImplemented, 'EnableActionsAfterMigration')
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
    if ($NonInteractive -and -not $Force) {
        $message = 'Non-interactive mutation requires -Force for repository copies.'
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'NonInteractiveExecutionRequiresForce', [System.Management.Automation.ErrorCategory]::InvalidOperation, $DestinationRepository)
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $isVisibilityChange = $plan.DestinationVisibility -ne $source.Visibility
    if ($isVisibilityChange -and -not $Force) {
        $message = "Changing '$($source.FullName)' from '$($source.Visibility)' to '$($plan.DestinationVisibility)' visibility requires explicit acknowledgement. Rerun with -Force only when this visibility change is intentional."
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'VisibilityChangeRequiresForce', [System.Management.Automation.ErrorCategory]::PermissionDenied, $DestinationRepository)
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    if ($Force) { $ConfirmPreference = 'None' }

    $target = $plan.DestinationRepository
    $action = switch ($plan.Mode) {
        'SameNameReplacement' {
            if ($plan.ContentMode -eq 'FullHistory') {
                "Preserve '$($plan.SourceRepository)' as '$($plan.ArchiveRepository)', create '$target', and copy the approved FullHistory state"
            }
            else {
                "Preserve '$($plan.SourceRepository)' as '$($plan.ArchiveRepository)', create '$target', and publish the approved Snapshot state"
            }
        }
        'ExistingDestinationReplacement' {
            "Preserve existing destination '$target' as '$($plan.ArchiveRepository)', create a fresh replacement, and copy the approved $($plan.ContentMode) state"
        }
        default {
            if ($plan.ContentMode -eq 'FullHistory') {
                "Create '$target' and copy the approved FullHistory state"
            }
            else {
                "Create '$target' and publish the approved Snapshot state"
            }
        }
    }

    if (-not $PSCmdlet.ShouldProcess($target, $action)) { return $plan }

    $resolvedSameNameConfirmation = $SameNameConfirmation
    $resolvedExistingDestinationConfirmation = $ExistingDestinationConfirmation
    $confirmWasExplicitlyDisabled = $PSBoundParameters.ContainsKey('Confirm') -and -not [bool] $PSBoundParameters['Confirm']

    if ($plan.Mode -eq 'SameNameReplacement' -and
        [string]::IsNullOrWhiteSpace($resolvedSameNameConfirmation) -and
        -not $NonInteractive -and
        -not $confirmWasExplicitlyDisabled) {
        $expectedConfirmation = "SOURCE=$($plan.SourceRepository);ARCHIVE=$($plan.ArchiveRepository);REPLACEMENT=$($plan.DestinationRepository)"
        $resolvedSameNameConfirmation = Read-Host "Type exactly: $expectedConfirmation"
    }

    if ($plan.Mode -eq 'ExistingDestinationReplacement' -and
        [string]::IsNullOrWhiteSpace($resolvedExistingDestinationConfirmation) -and
        -not $NonInteractive -and
        -not $confirmWasExplicitlyDisabled) {
        $expectedConfirmation = "DESTINATION=$($plan.DestinationRepository);ARCHIVE=$($plan.ArchiveRepository);REPLACEMENT=$($plan.DestinationRepository)"
        $resolvedExistingDestinationConfirmation = Read-Host "Type exactly: $expectedConfirmation"
    }

    return Invoke-CgrApprovedMigrationPlan `
        -Plan $plan `
        -SourceRepository $source `
        -SameNameConfirmation $resolvedSameNameConfirmation `
        -ExistingDestinationConfirmation $resolvedExistingDestinationConfirmation `
        -HostName $HostName `
        -ReportPath $ReportPath
}
