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

    The default content mode is Snapshot. Use the same content mode that was used
    for the migration. The command does not repair a failed verification and does
    not mutate either repository. Version 1 supports github.com only.

    .PARAMETER SourceRepository
    Specifies the source repository as owner/name. The repository must exist and
    be visible to the authenticated GitHub account.

    .PARAMETER DestinationRepository
    Specifies the destination repository as owner/name. This is the repository
    whose migrated Git content is verified against the source.

    .PARAMETER ContentMode
    Selects the verification contract. Snapshot is the default and verifies the
    default-branch tree plus the destination's single-root-commit history shape.
    FullHistory verifies branches, tags, reachable commit counts, branch-tip
    trees, the default branch, and reachable Git LFS object availability.

    .PARAMETER HostName
    Specifies the GitHub host used for discovery and authentication. The default
    is github.com. Version 1 supports github.com only.

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

    .INPUTS
    None. This command does not accept pipeline input.

    .OUTPUTS
    CopyGitHubRepo.SnapshotVerificationResult or
    CopyGitHubRepo.FullHistoryVerificationResult. The returned structured result
    contains the verification evidence and an IsSuccessful value that indicates
    whether the selected migration contract was satisfied.

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

        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com'
    )

    Assert-CgrSupportedHostName -HostName $HostName

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
        return Invoke-CgrRepositoryFullHistoryVerification `
            -SourceRepository $source `
            -DestinationRepository $destination
    }

    Invoke-CgrRepositorySnapshotVerification `
        -SourceRepository $source `
        -DestinationRepository $destination
}
