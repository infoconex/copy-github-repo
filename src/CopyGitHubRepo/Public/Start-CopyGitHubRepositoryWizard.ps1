function Start-CopyGitHubRepositoryWizard {
    <#
    .SYNOPSIS
    Starts the guided repository-copy wizard.

    .DESCRIPTION
    Provides the human-facing orchestration layer for repository discovery,
    repository-copy planning, explicit plan review, and execution. The wizard
    uses Get-GitHubRepository for read-only discovery and Copy-GitHubRepository
    -PlanOnly for the real repository copy plan.

    Repository selectors are paged for large accounts and support next/previous
    navigation plus filtering. The destination prompt accepts a repository name
    directly or [L list] to reuse the same selector. A selected destination can be
    used unchanged, modified, or replaced by another selection; every path then
    converges on the same destination-conflict and archive-and-replace workflow.

    The guided flow selects a source repository, destination identity, Snapshot
    or FullHistory content mode, destination visibility, supported-settings
    behavior, optional release preservation where applicable, and optional
    GitHub Pages restoration. Snapshot mode, source visibility, supported
    repository-settings restoration, no release preservation, and no Pages
    restoration are safe defaults. Effective defaults are restated at the end of
    prompts and can be accepted with Enter. Back preserves valid prior choices
    before execution, and cancellation returns a structured no-change result.

    Snapshot is the clean-publication mode: it publishes the approved source
    default-branch content as one new unrelated root commit without prior Git
    history. FullHistory is the history-preserving mode and copies the approved
    branches, tags, commits, and reachable Git LFS objects. Git LFS activity
    distinguishes an actual transfer from a successful no-op when no LFS content
    exists.

    GitHub Pages restoration is explicit and opt-in. Repository site files, CNAME,
    Jekyll configuration, and Pages workflow files remain ordinary Git content;
    copying them is distinct from restoring GitHub-side Pages configuration. The
    Pages decision uses the real plan evidence and presents source configured state,
    publishing mode/source, custom domain, HTTPS intent, representability, and
    external readiness where available. External DNS, account/organization domain
    verification, certificate provisioning, and secrets are not presented as state
    the migration will copy.

    Actions-based Pages and safely representable branch/path publishing can be
    restored by the delegated deterministic command. A branch/path that cannot be
    represented under the selected content mode is not silently redirected. For
    same-name or existing-destination replacement with a reviewed custom domain,
    the wizard surfaces the archive-to-replacement handoff before execution; the
    deterministic command retains identity, stale-state, verification, and recovery
    authority.

    Planning captures immutable source-state evidence. The Execute action runs the
    exact reviewed plan rather than rebuilding an equivalent request. The final
    Execute/Cancel prompt is headed "Confirm repository copy". If plan-driving
    source state changes after review, execution fails closed before the affected
    mutation and the wizard returns to plan generation so the new state can be
    reviewed explicitly.

    Known application, validation, prerequisite, and safety conditions are shown
    as concise wizard messages rather than raw PowerShell exception formatting.
    Expected fail-closed Pages recovery conditions are presented as application
    conditions; unexpected defects are rethrown so diagnostic information is not
    hidden.

    Replacement workflows preserve the existing repository under an archive name
    before creating the replacement. Their exact typed confirmation remains
    case-sensitive and non-bypassable; -Force and -Confirm:$false do not weaken it.

    No GitHub mutation is requested until a real Copy-GitHubRepository -PlanOnly
    plan has been generated, displayed, and explicitly confirmed. ShouldProcess
    then gates execution of that reviewed plan. Once mutation begins, the wizard
    does not offer Back; recovery information is retained for post-mutation errors.

    During execution, the wizard installs a presentation-only activity sink.
    Interactive terminals receive in-place progress for the active operation and
    durable completed-stage status lines. Redirected/non-interactive hosts receive
    line-oriented activity without cursor control. Verification, supported-settings
    restoration, requested Pages restoration, and repository-protection handling
    are reported in actual execution order. Successful no-op stages are
    informational rather than presented as work performed, and completed terminal
    stages use the same elapsed-time convention.
    Direct structured API calls do not install this sink and remain presentation-free.

    Successful interactive execution ends with restoration statuses followed by a
    concise final completion heading. Use Copy-GitHubRepository directly when
    structured execution output is required by automation.

    .PARAMETER HostName
    Specifies the GitHub host used by discovery and copy commands. The default is
    github.com. Version 1 supports github.com only.

    .PARAMETER Version
    Displays the loaded CopyGitHubRepo module version and exits without starting
    discovery, planning, or migration operations.

    .EXAMPLE
    Start-CopyGitHubRepositoryWizard

    Starts the guided repository-copy wizard using github.com. Pages restoration
    remains off unless explicitly selected in the reviewed guided flow.

    .EXAMPLE
    Start-CopyGitHubRepositoryWizard -Version

    Displays the loaded CopyGitHubRepo module version and exits.

    .EXAMPLE
    Start-CopyGitHubRepositoryWizard -WhatIf

    Runs selection and reviewed-plan flow, including optional Pages review, but
    prevents the approved plan from mutating GitHub when ShouldProcess is reached.

    .INPUTS
    None. This command does not accept pipeline input.

    .OUTPUTS
    System.String when -Version is specified. Otherwise, CopyGitHubRepo.WizardResult
    when the user cancels before mutation or a known pre-mutation application
    condition is presented cleanly. Successful interactive execution is rendered as
    a concise host summary rather than emitting the raw execution object.

    .LINK
    https://github.com/infoconex/copy-github-repo

    .LINK
    https://github.com/infoconex/copy-github-repo/blob/main/docs/user/github-pages-migration.md

    .LINK
    https://github.com/infoconex/copy-github-repo/blob/main/docs/product/wizard-contract.md
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com',

        [switch] $Version
    )

    if ($Version) {
        return $ExecutionContext.SessionState.Module.Version.ToString()
    }

    $resolvedHostName = $HostName
    $callerPSCmdlet = $PSCmdlet
    $executionGuard = {
        param([string] $Target)
        $callerPSCmdlet.ShouldProcess($Target, 'Execute the reviewed repository copy plan')
    }

    try {
        $activitySink = New-CgrWizardActivitySink
        $result = Invoke-CgrWithActivitySink -Sink $activitySink -Action {
            Invoke-CgrRepositoryCopyWizard -HostName $resolvedHostName -ExecutionGuard $executionGuard
        }

        if ($null -ne $result -and
            $null -ne (Get-CgrObjectProperty -InputObject $result -Name 'CompletedSteps') -and
            $null -ne (Get-CgrObjectProperty -InputObject $result -Name 'Plan')) {
            return
        }

        return $result
    }
    catch {
        if (-not (Test-CgrExpectedWizardApplicationError -ErrorRecord $_)) {
            throw
        }

        $errorId = ([string] $_.FullyQualifiedErrorId).Split(',', 2)[0]
        Write-CgrWizardMessage
        Write-CgrWizardMessage -Message 'Unable to continue' -Style Heading
        Write-CgrWizardMessage -Message $_.Exception.Message -Status Error

        [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.WizardResult'
            Status = 'ApplicationError'
            MutatedGitHub = $false
            ErrorId = $errorId
            Message = $_.Exception.Message
        }
    }
}
