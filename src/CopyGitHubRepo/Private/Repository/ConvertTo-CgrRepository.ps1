function ConvertTo-CgrRepository {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [psobject] $Repository,

        [Parameter(Mandatory)]
        [string] $HostName
    )

    process {
        $ownerName = $null
        $owner = Get-CgrObjectProperty -InputObject $Repository -Name 'owner'
        $ownerLogin = Get-CgrObjectProperty -InputObject $owner -Name 'login'
        if ($null -ne $ownerLogin) {
            $ownerName = [string] $ownerLogin
        }

        $visibility = [string] (Get-CgrObjectProperty -InputObject $Repository -Name 'visibility')
        if ([string]::IsNullOrWhiteSpace($visibility)) {
            if (Get-CgrObjectProperty -InputObject $Repository -Name 'private') {
                $visibility = 'private'
            }
            else {
                $visibility = 'public'
            }
        }

        $repositoryPermissions = Get-CgrObjectProperty -InputObject $Repository -Name 'permissions'
        $adminPermission = Get-CgrObjectProperty -InputObject $repositoryPermissions -Name 'admin'
        $maintainPermission = Get-CgrObjectProperty -InputObject $repositoryPermissions -Name 'maintain'
        $pushPermission = Get-CgrObjectProperty -InputObject $repositoryPermissions -Name 'push'
        $triagePermission = Get-CgrObjectProperty -InputObject $repositoryPermissions -Name 'triage'
        $pullPermission = Get-CgrObjectProperty -InputObject $repositoryPermissions -Name 'pull'
        $permissions = [ordered] @{
            Admin = [bool] ($adminPermission -eq $true)
            Maintain = [bool] ($maintainPermission -eq $true)
            Push = [bool] ($pushPermission -eq $true)
            Triage = [bool] ($triagePermission -eq $true)
            Pull = [bool] ($pullPermission -eq $true)
        }

        $updatedAt = Get-CgrObjectProperty -InputObject $Repository -Name 'updated_at'
        $topics = Get-CgrObjectProperty -InputObject $Repository -Name 'topics'
        $repositoryId = Get-CgrObjectProperty -InputObject $Repository -Name 'id'
        $repositoryNodeId = Get-CgrObjectProperty -InputObject $Repository -Name 'node_id'

        $nullableBooleanNames = @(
            'has_issues'
            'has_projects'
            'has_wiki'
            'has_discussions'
            'allow_squash_merge'
            'allow_merge_commit'
            'allow_rebase_merge'
            'allow_auto_merge'
            'delete_branch_on_merge'
            'allow_update_branch'
            'web_commit_signoff_required'
        )
        $nullableBooleans = @{}
        foreach ($propertyName in $nullableBooleanNames) {
            $propertyValue = Get-CgrObjectProperty -InputObject $Repository -Name $propertyName
            $nullableBooleans[$propertyName] = if ($null -eq $propertyValue) { $null } else { [bool] $propertyValue }
        }

        [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.Repository'
            Id = if ($null -eq $repositoryId) { $null } else { [long] $repositoryId }
            NodeId = if ($null -eq $repositoryNodeId) { $null } else { [string] $repositoryNodeId }
            Name = [string] (Get-CgrObjectProperty -InputObject $Repository -Name 'name')
            FullName = [string] (Get-CgrObjectProperty -InputObject $Repository -Name 'full_name')
            Owner = $ownerName
            Visibility = $visibility
            IsPrivate = [bool] (Get-CgrObjectProperty -InputObject $Repository -Name 'private')
            IsArchived = [bool] (Get-CgrObjectProperty -InputObject $Repository -Name 'archived')
            IsFork = [bool] (Get-CgrObjectProperty -InputObject $Repository -Name 'fork')
            DefaultBranch = [string] (Get-CgrObjectProperty -InputObject $Repository -Name 'default_branch')
            Description = [string] (Get-CgrObjectProperty -InputObject $Repository -Name 'description')
            Homepage = [string] (Get-CgrObjectProperty -InputObject $Repository -Name 'homepage')
            HasIssues = $nullableBooleans['has_issues']
            HasProjects = $nullableBooleans['has_projects']
            HasWiki = $nullableBooleans['has_wiki']
            HasDiscussions = $nullableBooleans['has_discussions']
            AllowSquashMerge = $nullableBooleans['allow_squash_merge']
            AllowMergeCommit = $nullableBooleans['allow_merge_commit']
            AllowRebaseMerge = $nullableBooleans['allow_rebase_merge']
            AllowAutoMerge = $nullableBooleans['allow_auto_merge']
            DeleteBranchOnMerge = $nullableBooleans['delete_branch_on_merge']
            AllowUpdateBranch = $nullableBooleans['allow_update_branch']
            WebCommitSignoffRequired = $nullableBooleans['web_commit_signoff_required']
            Topics = if ($null -eq $topics) { $null } else { @($topics | ForEach-Object { [string] $_ } | Sort-Object) }
            HtmlUrl = [string] (Get-CgrObjectProperty -InputObject $Repository -Name 'html_url')
            CloneUrl = [string] (Get-CgrObjectProperty -InputObject $Repository -Name 'clone_url')
            SshUrl = [string] (Get-CgrObjectProperty -InputObject $Repository -Name 'ssh_url')
            HostName = $HostName
            Permissions = [pscustomobject] $permissions
            CanAdmin = [bool] ($permissions['Admin'] -eq $true)
            CanPush = [bool] ($permissions['Push'] -eq $true)
            UpdatedAt = if ($updatedAt) { [datetimeoffset] $updatedAt } else { $null }
        }
    }
}
