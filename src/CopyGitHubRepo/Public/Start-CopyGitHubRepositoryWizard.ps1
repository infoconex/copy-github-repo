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
    or FullHistory content mode, destination visibility, and supported-settings
    behavior. Snapshot mode, source visibility, and supported repository-settings
    restoration are the defaults. Effective defaults are restated at the end of
    prompts and can be accepted with Enter. Back preserves valid prior choices
    before execution, and cancellation returns a structured no-change result.

    Snapshot is the clean-publication mode: it publishes the approved source
    default-branch content as one new unrelated root commit without prior Git
    history. FullHistory is the history-preserving mode and copies the approved
    branches, tags, commits, and reachable Git LFS objects. Git LFS activity
    distinguishes an actual transfer from a successful no-op when no LFS content
    exists.

    Planning captures immutable source-state evidence. The Execute action runs the
    exact reviewed plan rather than rebuilding an equivalent request. The final
    Execute/Cancel prompt is headed "Confirm repository copy". If the source changes
    after plan review, execution fails closed before mutation and the wizard returns
    to plan generation so the new source state can be reviewed explicitly.

    Known application, validation, prerequisite, and safety conditions are shown
    as concise wizard messages rather than raw PowerShell exception formatting.
    Unexpected defects are rethrown so diagnostic information is not hidden.

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
    restoration, and repository-protection handling are reported in actual execution
    order. Successful no-op stages are informational rather than presented as work
    performed, and completed terminal stages use the same elapsed-time convention.
    Direct structured API calls do not install this sink and remain presentation-free.

    Successful interactive execution ends with restoration statuses followed by a
    concise final completion heading. Use Copy-GitHubRepository directly when
    structured execution output is required by automation.

    .PARAMETER HostName
    Specifies the GitHub host used by discovery and copy commands. The default is
    github.com. Version 1 supports github.com only.

    .EXAMPLE
    Start-CopyGitHubRepositoryWizard

    Starts the guided repository-copy wizard using github.com.

    .EXAMPLE
    Start-CopyGitHubRepositoryWizard -WhatIf

    Runs selection and reviewed-plan flow but prevents the approved plan from
    mutating GitHub when ShouldProcess is reached.

    .INPUTS
    None. This command does not accept pipeline input.

    .OUTPUTS
    CopyGitHubRepo.WizardResult when the user cancels before mutation or a known
    pre-mutation application condition is presented cleanly. Successful interactive
    execution is rendered as a concise host summary rather than emitting the raw
    execution object.

    .LINK
    https://github.com/infoconex/copy-github-repo

    .LINK
    https://github.com/infoconex/copy-github-repo/blob/main/docs/product/wizard-contract.md
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com'
    )

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
