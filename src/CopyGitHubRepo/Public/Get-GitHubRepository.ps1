function Get-GitHubRepository {
    <#
    .SYNOPSIS
    Gets GitHub repositories available to the authenticated user.

    .DESCRIPTION
    Returns structured GitHub repository objects by using GitHub CLI
    authentication and GitHub API access. Use the ByRepository parameter set
    for one direct owner/name lookup, or the Search parameter set to list and
    filter repositories. Search is the default parameter set, so invoking the
    command without search filters lists repositories available to the
    authenticated account.

    Direct lookup parameters cannot be combined with search filters. The command
    performs read-only discovery and does not create, rename, update, or delete
    repositories. Version 1 supports github.com only.

    .PARAMETER Repository
    Gets one repository by its exact owner/name identity, for example
    infoconex/copy-github-repo. This mandatory parameter belongs to the
    ByRepository parameter set and cannot be combined with Owner, Name,
    Visibility, or Archived.

    .PARAMETER Owner
    Filters repository search results by exact owner login. This parameter
    belongs to the Search parameter set.

    .PARAMETER Name
    Filters repository search results by repository name. This parameter belongs
    to the Search parameter set.

    .PARAMETER Visibility
    Filters repository search results by public, private, or internal visibility.
    This parameter belongs to the Search parameter set.

    .PARAMETER Archived
    Filters repository search results by archived state. Specify $true to return
    archived repositories or $false to return non-archived repositories. If this
    parameter is omitted, archived state is not used as a filter. This parameter
    belongs to the Search parameter set.

    .PARAMETER HostName
    Specifies the GitHub host used for discovery and authentication. The default
    is github.com. Version 1 supports github.com only. This parameter is available
    in both parameter sets.

    .EXAMPLE
    Get-GitHubRepository -Repository infoconex/copy-github-repo

    Performs one direct repository lookup using the ByRepository parameter set
    and returns the structured repository object.

    .EXAMPLE
    Get-GitHubRepository -Owner infoconex -Name copy -Visibility public -Archived $false

    Searches repositories using the Search parameter set and applies all supplied
    filters.

    .EXAMPLE
    Get-GitHubRepository -Owner infoconex

    Lists repositories owned by infoconex. Search is the default parameter set.

    .INPUTS
    None. This command does not accept pipeline input.

    .OUTPUTS
    CopyGitHubRepo.Repository. Returns structured repository objects that include
    repository identity, owner/name, visibility, archived state, default branch,
    URLs, and supported repository settings discovered from GitHub.

    .LINK
    https://github.com/infoconex/copy-github-repo

    .LINK
    https://github.com/infoconex/copy-github-repo/blob/main/docs/product/command-design.md
    #>
    [CmdletBinding(DefaultParameterSetName = 'Search')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByRepository')]
        [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
        [string] $Repository,

        [Parameter(ParameterSetName = 'Search')]
        [string] $Owner,

        [Parameter(ParameterSetName = 'Search')]
        [string] $Name,

        [Parameter(ParameterSetName = 'Search')]
        [ValidateSet('public', 'private', 'internal')]
        [string] $Visibility,

        [Parameter(ParameterSetName = 'Search')]
        [Nullable[bool]] $Archived,

        [Parameter(ParameterSetName = 'ByRepository')]
        [Parameter(ParameterSetName = 'Search')]
        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com'
    )

    Assert-CgrSupportedHostName -HostName $HostName

    $prerequisites = Get-CgrPrerequisiteStatus -HostName $HostName
    if (-not $prerequisites.GitHubCli.Found) {
        $exception = [System.InvalidOperationException]::new(
            "GitHub CLI is required for repository discovery. Install 'gh' from https://cli.github.com/."
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

    $repositoryParameters = @{
        HostName = $HostName
    }

    if ($Repository) {
        $repositoryParameters.Repository = $Repository
    }

    if ($Owner) {
        $repositoryParameters.Owner = $Owner
    }

    if ($Name) {
        $repositoryParameters.Name = $Name
    }

    if ($Visibility) {
        $repositoryParameters.Visibility = $Visibility
    }

    if ($PSBoundParameters.ContainsKey('Archived')) {
        $repositoryParameters.Archived = $Archived
    }

    Get-CgrRepository @repositoryParameters
}
