function Assert-CgrApprovedSourceState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Repository,

        [Parameter(Mandatory)]
        [psobject] $SourceState,

        [switch] $AllowRepositoryNameChange
    )

    $expectedRepository = [string] (Get-CgrObjectProperty -InputObject $SourceState -Name 'Repository')
    $expectedRepositoryId = Get-CgrObjectProperty -InputObject $SourceState -Name 'RepositoryId'
    $expectedNodeId = Get-CgrObjectProperty -InputObject $SourceState -Name 'RepositoryNodeId'
    $actualRepositoryId = Get-CgrObjectProperty -InputObject $Repository -Name 'Id'
    $actualNodeId = Get-CgrObjectProperty -InputObject $Repository -Name 'NodeId'
    $contentMode = [string] (Get-CgrObjectProperty -InputObject $SourceState -Name 'ContentMode')

    $hasRepositoryIds = $null -ne $expectedRepositoryId -and $null -ne $actualRepositoryId
    $identityMatches = if ($hasRepositoryIds) {
        [long] $expectedRepositoryId -eq [long] $actualRepositoryId
    }
    else {
        $AllowRepositoryNameChange -or $Repository.FullName -eq $expectedRepository
    }
    if ($identityMatches -and $null -ne $expectedNodeId -and $null -ne $actualNodeId) {
        $identityMatches = [string] $expectedNodeId -eq [string] $actualNodeId
    }
    if ($identityMatches -and -not $AllowRepositoryNameChange) {
        $identityMatches = $Repository.FullName -eq $expectedRepository
    }

    $currentState = if ($contentMode -eq 'FullHistory') {
        $identity = Get-CgrRepositoryFullHistoryIdentity -Repository $Repository
        [pscustomobject] @{
            DefaultBranch = $identity.DefaultBranch
            Refs = @($identity.Refs)
            ReachableCommitCount = $identity.ReachableCommitCount
            BranchTrees = @($identity.BranchTrees)
            GitLfsObjectsAvailable = [bool] $identity.GitLfsObjectsAvailable
        }
    }
    else {
        $tree = Get-CgrRepositoryDefaultBranchTree -Repository $Repository
        [pscustomobject] @{
            DefaultBranch = $tree.BranchName
            CommitSha = $tree.CommitSha
            TreeSha = $tree.TreeSha
            GitLfsObjectsAvailable = [bool] $tree.GitLfsObjectsAvailable
            GitLfsPointerFiles = @($tree.GitLfsPointerFiles)
        }
    }

    $stateMatches = $identityMatches -and $currentState.DefaultBranch -eq (Get-CgrObjectProperty -InputObject $SourceState -Name 'DefaultBranch')
    if ($contentMode -eq 'FullHistory') {
        $stateMatches = $stateMatches -and
            (($currentState.Refs | Sort-Object) -join "`n") -eq ((@(Get-CgrObjectProperty -InputObject $SourceState -Name 'Refs') | Sort-Object) -join "`n") -and
            $currentState.ReachableCommitCount -eq (Get-CgrObjectProperty -InputObject $SourceState -Name 'ReachableCommitCount') -and
            (($currentState.BranchTrees | Sort-Object) -join "`n") -eq ((@(Get-CgrObjectProperty -InputObject $SourceState -Name 'BranchTrees') | Sort-Object) -join "`n") -and
            $currentState.GitLfsObjectsAvailable -eq [bool] (Get-CgrObjectProperty -InputObject $SourceState -Name 'GitLfsObjectsAvailable')
    }
    else {
        $stateMatches = $stateMatches -and
            $currentState.CommitSha -eq (Get-CgrObjectProperty -InputObject $SourceState -Name 'CommitSha') -and
            $currentState.TreeSha -eq (Get-CgrObjectProperty -InputObject $SourceState -Name 'TreeSha') -and
            $currentState.GitLfsObjectsAvailable -eq [bool] (Get-CgrObjectProperty -InputObject $SourceState -Name 'GitLfsObjectsAvailable') -and
            (($currentState.GitLfsPointerFiles | Sort-Object) -join "`n") -eq ((@(Get-CgrObjectProperty -InputObject $SourceState -Name 'GitLfsPointerFiles') | Sort-Object) -join "`n")
    }

    if (-not $stateMatches) {
        $message = "Source repository '$expectedRepository' changed after the approved repository copy plan was created. No further mutation is allowed from this plan. Recreate and review the plan before executing it."
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'SourceStateChangedSincePlanning',
            [System.Management.Automation.ErrorCategory]::InvalidResult,
            $expectedRepository
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    return $currentState
}
