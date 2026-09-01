function New-CgrMigrationPlan {
    <#
    .SYNOPSIS
    Builds the immutable migration plan reviewed before repository mutation.

    .DESCRIPTION
    Normalizes source and destination identity, rejects unsafe archive/destination
    conflicts, captures approved source Git evidence and transferable protection,
    and produces the ordered steps for Snapshot or FullHistory execution. Planning
    itself does not perform the repository-copy mutation; the returned source-state
    evidence is later revalidated so execution fails closed if the source changes.

    Release planning captures the exact GitHub Releases selected for restoration,
    including tag targets and release asset metadata. Snapshot release planning also
    captures immutable checkpoint trees and derives checkpoint order from Git ancestry.
    Execution must use the approved selection rather than re-evaluating live filters.

    When Pages restoration is requested, planning also captures the reviewed
    GitHub-side Pages configuration, external readiness evidence, representability,
    and drift-driving fields. Later Pages work must consume that immutable evidence
    rather than rediscover mutable source configuration as execution authority.

    .NOTES
    Replacement modes deliberately require unused archive names. The plan is the
    safety contract between review and execution and must not be reconstructed from
    live source state after the user has approved it.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'This private helper builds a dry-run plan object only; it performs no mutation.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $SourceRepository,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
        [string] $DestinationRepository,

        [Parameter(Mandatory)]
        [ValidateSet('Snapshot', 'FullHistory')]
        [string] $ContentMode,

        [switch] $IncludeReleases,

        [string[]] $ReleaseTag,

        [string[]] $ReleaseExcludeTag,

        [switch] $IncludePrerelease,

        [switch] $IncludeDraftReleases,

        [ValidateRange(1, [int]::MaxValue)]
        [int] $ReleaseCount,

        [Parameter(Mandatory)]
        [ValidateSet('public', 'private', 'internal')]
        [string] $DestinationVisibility,

        [string] $ArchiveRepositoryName,

        [string] $ExistingDestinationArchiveName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $CommitMessage,

        [switch] $RestorePages,

        [switch] $EnableActionsAfterMigration,

        [switch] $SkipSettings,

        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com',

        [switch] $PlanOnly
    )

    $normalizedDestination = ConvertTo-CgrRepositoryName -Repository $DestinationRepository
    $sourceFullName = ConvertTo-CgrRepositoryName -Repository $SourceRepository.FullName

    if ([string]::IsNullOrWhiteSpace([string] $SourceRepository.DefaultBranch)) {
        $message = "Source repository '$sourceFullName' is empty and has no default branch to copy. Add at least one commit before copying the repository."
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'SourceRepositoryEmpty',
            [System.Management.Automation.ErrorCategory]::InvalidData,
            $sourceFullName
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $isSameNameReplacement = $sourceFullName -eq $normalizedDestination
    $destinationExists = $false
    $isExistingDestinationReplacement = $false
    $archiveFullName = $null

    if ($isSameNameReplacement) {
        if ([string]::IsNullOrWhiteSpace($ArchiveRepositoryName)) {
            $exception = [System.InvalidOperationException]::new(
                'Same-name replacement planning requires -ArchiveRepositoryName so the original repository can be preserved.'
            )
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'ArchiveRepositoryNameRequired',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                $DestinationRepository
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $archiveFullName = "$($SourceRepository.Owner)/$ArchiveRepositoryName"
        if (Test-CgrGitHubRepositoryExistence -Repository $archiveFullName -HostName $HostName) {
            $exception = [System.InvalidOperationException]::new(
                "Archive repository '$archiveFullName' already exists. Choose an unused archive repository name."
            )
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'ArchiveRepositoryAlreadyExists',
                [System.Management.Automation.ErrorCategory]::ResourceExists,
                $archiveFullName
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }
    else {
        $destinationExists = Test-CgrGitHubRepositoryExistence -Repository $normalizedDestination -HostName $HostName
        if ($destinationExists) {
            if ([string]::IsNullOrWhiteSpace($ExistingDestinationArchiveName)) {
                $exception = [System.InvalidOperationException]::new(
                    "Destination repository '$normalizedDestination' already exists. The tool will not overwrite an existing repository."
                )
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'DestinationRepositoryAlreadyExists',
                    [System.Management.Automation.ErrorCategory]::ResourceExists,
                    $normalizedDestination
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            $destinationParts = $normalizedDestination.Split('/', 2)
            $archiveFullName = "$($destinationParts[0])/$ExistingDestinationArchiveName"
            if (Test-CgrGitHubRepositoryExistence -Repository $archiveFullName -HostName $HostName) {
                $exception = [System.InvalidOperationException]::new(
                    "Archive repository '$archiveFullName' already exists. Choose an unused archive repository name."
                )
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'ExistingDestinationArchiveAlreadyExists',
                    [System.Management.Automation.ErrorCategory]::ResourceExists,
                    $archiveFullName
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            $isExistingDestinationReplacement = $true
        }
        elseif (-not [string]::IsNullOrWhiteSpace($ExistingDestinationArchiveName)) {
            $exception = [System.InvalidOperationException]::new(
                "Existing-destination archive name was supplied, but destination repository '$normalizedDestination' does not exist."
            )
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'ExistingDestinationArchiveNotRequired',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                $normalizedDestination
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }

    $sourceRepositoryId = Get-CgrObjectProperty -InputObject $SourceRepository -Name 'Id'
    $protectionConfiguration = $null
    $protectionPlanningStatus = if ($SkipSettings) {
        'SkippedWithSettings'
    }
    elseif ($null -eq $sourceRepositoryId) {
        'SkippedSourceIdentityUnavailable'
    }
    else {
        $protectionConfiguration = Get-CgrRepositoryProtectionConfiguration `
            -Repository $SourceRepository `
            -HostName $HostName
        'Captured'
    }

    $protectionPlan = [pscustomobject] @{
        Status = $protectionPlanningStatus
        RulesetCount = if ($protectionConfiguration) { @($protectionConfiguration.Rulesets).Count } else { 0 }
        DefaultBranchProtectionCaptured = [bool] ($protectionConfiguration -and $protectionConfiguration.BranchProtection)
        Unsupported = if ($protectionConfiguration) { @($protectionConfiguration.Unsupported) } else { @() }
        Configuration = $protectionConfiguration
    }

    $sourceState = Get-CgrApprovedSourceState -Repository $SourceRepository -ContentMode $ContentMode
    $pagesPlan = if ($RestorePages) {
        Get-CgrGitHubPagesPlanEvidence `
            -Repository $SourceRepository `
            -ContentMode $ContentMode `
            -SourceState $sourceState `
            -HostName $HostName
    }
    else {
        $null
    }

    $releaseSelection = $null
    $releaseCheckpointPlan = $null
    if ($IncludeReleases) {
        $releaseSelectionParameters = @{
            Repository = $SourceRepository
            ReleaseTag = $ReleaseTag
            ReleaseExcludeTag = $ReleaseExcludeTag
            IncludePrerelease = $IncludePrerelease
            IncludeDraftReleases = $IncludeDraftReleases
            HostName = $HostName
        }
        if ($PSBoundParameters.ContainsKey('ReleaseCount')) {
            $releaseSelectionParameters.ReleaseCount = $ReleaseCount
        }
        $releaseSelection = Get-CgrGitHubReleaseSelection @releaseSelectionParameters

        if ($ContentMode -eq 'Snapshot') {
            $releaseCheckpointPlan = New-CgrSnapshotReleaseCheckpointPlan `
                -Repository $SourceRepository `
                -ReleaseSelection $releaseSelection `
                -SourceState $sourceState `
                -HostName $HostName
        }
    }

    $steps = [System.Collections.Generic.List[object]]::new()
    if ($isSameNameReplacement) {
        $steps.Add([pscustomobject] @{
                Order = 1
                Name = 'PreserveSourceAsArchive'
                Description = "Preserve the original repository by renaming '$sourceFullName' to '$archiveFullName'."
                MutatesGitHub = $true
            })
        $steps.Add([pscustomobject] @{
                Order = 2
                Name = 'CreateReplacementRepository'
                Description = "Create a fresh '$normalizedDestination' repository with '$DestinationVisibility' visibility."
                MutatesGitHub = $true
            })
    }
    elseif ($isExistingDestinationReplacement) {
        $steps.Add([pscustomobject] @{
                Order = 1
                Name = 'PreserveDestinationAsArchive'
                Description = "Preserve the existing destination by renaming '$normalizedDestination' to '$archiveFullName'."
                MutatesGitHub = $true
            })
        $steps.Add([pscustomobject] @{
                Order = 2
                Name = 'CreateReplacementRepository'
                Description = "Create a fresh '$normalizedDestination' repository with '$DestinationVisibility' visibility."
                MutatesGitHub = $true
            })
    }
    else {
        $steps.Add([pscustomobject] @{
                Order = 1
                Name = 'CreateDestinationRepository'
                Description = "Create '$normalizedDestination' with '$DestinationVisibility' visibility."
                MutatesGitHub = $true
            })
    }

    $steps.Add([pscustomobject] @{
            Order = $steps.Count + 1
            Name = "Copy$ContentMode"
            Description = if ($ContentMode -eq 'Snapshot' -and $IncludeReleases) {
                "Publish the approved Snapshot as $($releaseCheckpointPlan.CheckpointCount) release checkpoint(s) in source Git-ancestry order$(if ($releaseCheckpointPlan.FinalHeadCheckpointRequired) { ', followed by one reviewed current-state checkpoint' } else { '' }). Destination commits are new and unrelated to source history."
            }
            elseif ($ContentMode -eq 'Snapshot') {
                "Publish the approved '$($SourceRepository.DefaultBranch)' branch content from '$sourceFullName' as one new root commit. Prior commit history, other branches, and tags are not published."
            }
            else {
                "Copy the approved Git history from '$sourceFullName', preserving branches, tags, commits, and reachable Git LFS objects."
            }
            MutatesGitHub = $true
        })

    $steps.Add([pscustomobject] @{
            Order = $steps.Count + 1
            Name = 'VerifyMigration'
            Description = if ($ContentMode -eq 'Snapshot' -and $IncludeReleases) {
                'Verify the future Snapshot checkpoint history against the immutable reviewed checkpoint and source-HEAD evidence before restoring repository configuration.'
            }
            elseif ($ContentMode -eq 'Snapshot') {
                'Verify the published Snapshot content against the approved source tree before restoring repository configuration.'
            }
            else {
                'Verify the copied history, branches, tags, commits, and Git LFS availability against the approved source state before restoring repository configuration.'
            }
            MutatesGitHub = $false
        })

    if ($IncludeReleases) {
        $steps.Add([pscustomobject] @{
                Order = $steps.Count + 1
                Name = 'RestoreGitHubReleases'
                Description = if ($ContentMode -eq 'Snapshot') {
                    "Restore $($releaseSelection.SelectedReleaseCount) approved GitHub Release(s) and $($releaseSelection.SelectedAssetCount) release asset(s) against their future Snapshot checkpoint tags after checkpoint verification."
                }
                else {
                    "Restore $($releaseSelection.SelectedReleaseCount) approved GitHub Release(s) and $($releaseSelection.SelectedAssetCount) release asset(s) after FullHistory verification."
                }
                MutatesGitHub = $true
            })
    }

    if (-not $SkipSettings) {
        $steps.Add([pscustomobject] @{
                Order = $steps.Count + 1
                Name = 'RestoreSupportedSettings'
                Description = 'Restore supported repository settings and topics after content verification.'
                MutatesGitHub = $true
            })
        $rulesetCount = if ($protectionConfiguration) { @($protectionConfiguration.Rulesets).Count } else { 0 }
        $hasDefaultBranchProtection = [bool] ($protectionConfiguration -and $protectionConfiguration.BranchProtection)
        $protectionDescription = if ($protectionPlanningStatus -ne 'Captured') {
            'Repository protection could not be fully inspected during planning. Only protection that can be restored safely will be applied, and anything unavailable will be reported.'
        }
        elseif ($rulesetCount -eq 0 -and -not $hasDefaultBranchProtection) {
            'No transferable repository protection was found.'
        }
        elseif ($rulesetCount -gt 0 -and $hasDefaultBranchProtection) {
            "Restore $rulesetCount transferable repository ruleset(s) and default-branch protection after content verification. Identity-bound protection will be reported rather than weakened."
        }
        elseif ($rulesetCount -gt 0) {
            "Restore $rulesetCount transferable repository ruleset(s) after content verification. Identity-bound protection will be reported rather than weakened."
        }
        else {
            'Restore transferable default-branch protection after content verification. Identity-bound protection will be reported rather than weakened.'
        }
        $steps.Add([pscustomobject] @{
                Order = $steps.Count + 1
                Name = 'RestoreRepositoryProtection'
                Description = $protectionDescription
                MutatesGitHub = $true
            })
    }

    $mode = if ($isSameNameReplacement) {
        'SameNameReplacement'
    }
    elseif ($isExistingDestinationReplacement) {
        'ExistingDestinationReplacement'
    }
    else {
        'NewDestination'
    }

    $plan = [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.MigrationPlan'
        SchemaVersion = 1
        Mode = $mode
        HostName = $HostName
        SourceRepository = $sourceFullName
        SourceDefaultBranch = $SourceRepository.DefaultBranch
        SourceVisibility = $SourceRepository.Visibility
        SourceState = $sourceState
        DestinationRepository = $normalizedDestination
        DestinationExistedBeforeMigration = [bool] $destinationExists
        ArchiveRepository = $archiveFullName
        ContentMode = $ContentMode
        DestinationVisibility = $DestinationVisibility
        CommitMessage = $CommitMessage
        IncludeReleases = [bool] $IncludeReleases
        ReleaseSelection = $releaseSelection
        ReleaseCheckpointPlan = $releaseCheckpointPlan
        RestorePages = [bool] $RestorePages
        EnableActionsAfterMigration = [bool] $EnableActionsAfterMigration
        SkipSettings = [bool] $SkipSettings
        Protection = $protectionPlan
        WillMutateGitHub = -not [bool] $PlanOnly
        PlanOnly = [bool] $PlanOnly
        Steps = $steps.ToArray()
    }

    if ($RestorePages) {
        $plan | Add-Member -NotePropertyName Pages -NotePropertyValue $pagesPlan
    }

    $plan
}
