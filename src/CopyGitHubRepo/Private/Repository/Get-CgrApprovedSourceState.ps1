function Get-CgrApprovedSourceState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Repository,

        [Parameter(Mandatory)]
        [ValidateSet('Snapshot', 'FullHistory')]
        [string] $ContentMode
    )

    $repositoryId = Get-CgrObjectProperty -InputObject $Repository -Name 'Id'
    $repositoryNodeId = Get-CgrObjectProperty -InputObject $Repository -Name 'NodeId'

    if ($ContentMode -eq 'FullHistory') {
        $identity = Get-CgrRepositoryFullHistoryIdentity -Repository $Repository
        $planningWorkspaceBytesValue = Get-CgrObjectProperty -InputObject $identity -Name 'PlanningWorkspaceBytes'
        $planningWorkspaceBytes = if ($null -eq $planningWorkspaceBytesValue) { 0L } else { [long] $planningWorkspaceBytesValue }
        return [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.ApprovedSourceState'
            SchemaVersion = 1
            ContentMode = 'FullHistory'
            Repository = $Repository.FullName
            RepositoryId = if ($null -ne $repositoryId) { [long] $repositoryId } else { $null }
            RepositoryNodeId = $repositoryNodeId
            DefaultBranch = $identity.DefaultBranch
            Refs = @($identity.Refs)
            ReachableCommitCount = $identity.ReachableCommitCount
            BranchTrees = @($identity.BranchTrees)
            GitLfsObjectsAvailable = [bool] $identity.GitLfsObjectsAvailable
            PlanningWorkspaceBytes = $planningWorkspaceBytes
            PlanningWorkspaceEvidenceKind = if ($planningWorkspaceBytes -gt 0) { 'ObservedPlanningWorkspaceLowerBound' } else { 'Unknown' }
            CapturedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        }
    }

    $treeIdentity = Get-CgrRepositoryDefaultBranchTree -Repository $Repository
    $historicalRecords = Get-CgrSnapshotHistory -Repository $Repository
    $planningWorkspaceBytesValue = Get-CgrObjectProperty -InputObject $treeIdentity -Name 'PlanningWorkspaceBytes'
    $planningWorkspaceBytes = if ($null -eq $planningWorkspaceBytesValue) { 0L } else { [long] $planningWorkspaceBytesValue }
    return [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.ApprovedSourceState'
        SchemaVersion = 1
        ContentMode = 'Snapshot'
        Repository = $Repository.FullName
        RepositoryId = if ($null -ne $repositoryId) { [long] $repositoryId } else { $null }
        RepositoryNodeId = $repositoryNodeId
        DefaultBranch = $treeIdentity.BranchName
        CommitSha = $treeIdentity.CommitSha
        TreeSha = $treeIdentity.TreeSha
        GitLfsObjectsAvailable = Get-CgrObjectProperty -InputObject $treeIdentity -Name 'GitLfsObjectsAvailable'
        GitLfsPointerFiles = @(Get-CgrObjectProperty -InputObject $treeIdentity -Name 'GitLfsPointerFiles')
        HistoricalRecords = $historicalRecords
        PlanningWorkspaceBytes = $planningWorkspaceBytes
        PlanningWorkspaceEvidenceKind = if ($planningWorkspaceBytes -gt 0) { 'ObservedPlanningWorkspaceLowerBound' } else { 'Unknown' }
        CapturedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    }
}
