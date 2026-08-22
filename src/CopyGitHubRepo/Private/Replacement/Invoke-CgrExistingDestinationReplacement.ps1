function Invoke-CgrExistingDestinationReplacement {
    <#
    .SYNOPSIS
    Archives an existing destination and executes a verified replacement copy.

    .DESCRIPTION
    Internal mutation boundary used only after Copy-GitHubRepository has completed
    ShouldProcess and exact archive-and-replace confirmation. The original
    destination is renamed first, its immutable repository identity is verified,
    and only then is a fresh replacement created and populated from the approved
    plan. Any failure after mutation begins records recovery evidence when possible.

    .NOTES
    This function intentionally does not perform its own ShouldProcess prompt. The
    public command owns user consent; this layer owns ordered mutation, identity
    verification, fail-closed source-state validation, and recovery reporting.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'The public Copy-GitHubRepository command performs ShouldProcess and exact archive-and-replace confirmation before calling this orchestration boundary.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Plan,

        [Parameter(Mandatory)]
        [psobject] $SourceRepository,

        [Parameter(Mandatory)]
        [psobject] $ExistingDestinationRepository,

        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com',

        [string] $ReportPath
    )

    $completedSteps = [System.Collections.Generic.List[object]]::new()
    $archive = $null
    $replacement = $null
    $failureStage = 'ValidateApprovedSourceState'
    $originalRepositoryId = Get-CgrObjectProperty -InputObject $ExistingDestinationRepository -Name 'Id'
    $originalRepositoryNodeId = Get-CgrObjectProperty -InputObject $ExistingDestinationRepository -Name 'NodeId'
    $sourceState = Get-CgrObjectProperty -InputObject $Plan -Name 'SourceState'

    try {
        Assert-CgrApprovedSourceState -Repository $SourceRepository -SourceState $sourceState | Out-Null

        $failureStage = 'PreserveDestinationAsArchive'
        $archive = Rename-CgrGitHubRepository `
            -SourceRepository $ExistingDestinationRepository `
            -ArchiveRepository $Plan.ArchiveRepository `
            -HostName $HostName
        $completedSteps.Add([pscustomobject] @{
                Order = 1
                Name = 'PreserveDestinationAsArchive'
                MutatedGitHub = $true
                Verified = $true
            })

        $failureStage = 'VerifyArchivedDestinationIdentity'
        $archiveRepositoryId = Get-CgrObjectProperty -InputObject $archive -Name 'Id'
        $archiveRepositoryNodeId = Get-CgrObjectProperty -InputObject $archive -Name 'NodeId'
        $idMatches = $null -ne $originalRepositoryId -and $archiveRepositoryId -eq $originalRepositoryId
        $nodeIdMatches = $null -eq $originalRepositoryNodeId -or $null -eq $archiveRepositoryNodeId -or $archiveRepositoryNodeId -eq $originalRepositoryNodeId
        if (-not $idMatches -or -not $nodeIdMatches) {
            $message = "Archived destination '$($archive.FullName)' does not retain the immutable identity of the original destination. Replacement creation was stopped."
            $exception = [System.InvalidOperationException]::new($message)
            throw [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'ArchivedDestinationIdentityMismatch',
                [System.Management.Automation.ErrorCategory]::InvalidResult,
                $archive.FullName
            )
        }
        $completedSteps.Add([pscustomobject] @{
                Order = 2
                Name = 'VerifyArchivedDestinationIdentity'
                MutatedGitHub = $false
                Verified = $true
            })

        $failureStage = 'CreateReplacementRepository'
        $replacement = New-CgrGitHubRepository `
            -Repository $Plan.DestinationRepository `
            -Visibility $Plan.DestinationVisibility `
            -HostName $HostName
        $completedSteps.Add([pscustomobject] @{
                Order = 3
                Name = 'CreateReplacementRepository'
                MutatedGitHub = $true
                Verified = $true
            })

        $failureStage = 'VerifyReplacementRepositoryIdentity'
        $repositoryIdentity = Assert-CgrReplacementRepositoryIdentity `
            -SourceRepository $ExistingDestinationRepository `
            -ArchiveRepository $archive `
            -ReplacementRepository $replacement
        $completedSteps.Add([pscustomobject] @{
                Order = 4
                Name = 'VerifyReplacementRepositoryIdentity'
                MutatedGitHub = $false
                Verified = $true
            })

        $failureStage = "Copy$($Plan.ContentMode)"
        $result = if ($Plan.ContentMode -eq 'FullHistory') {
            Invoke-CgrNewDestinationFullHistory `
                -Plan $Plan `
                -SourceRepository $SourceRepository `
                -DestinationRepository $replacement `
                -HostName $HostName
        }
        else {
            Invoke-CgrNewDestinationSnapshot `
                -Plan $Plan `
                -SourceRepository $SourceRepository `
                -DestinationRepository $replacement `
                -HostName $HostName
        }

        $nextOrder = 5
        foreach ($childStep in @($result.CompletedSteps)) {
            if ($childStep.Name -eq 'CreateDestinationRepository') {
                continue
            }

            $completedSteps.Add([pscustomobject] @{
                    Order = $nextOrder
                    Name = $childStep.Name
                    MutatedGitHub = [bool] $childStep.MutatedGitHub
                    Verified = [bool] $childStep.Verified
                })
            $nextOrder++
        }

        $replacementRepositoryId = $repositoryIdentity.ReplacementRepositoryId
        $replacementRepositoryNodeId = Get-CgrObjectProperty -InputObject $replacement -Name 'NodeId'
        $result | Add-Member -NotePropertyName OriginalDestinationRepository -NotePropertyValue $ExistingDestinationRepository.FullName -Force
        $result | Add-Member -NotePropertyName OriginalDestinationRepositoryId -NotePropertyValue $originalRepositoryId -Force
        $result | Add-Member -NotePropertyName OriginalDestinationRepositoryNodeId -NotePropertyValue $originalRepositoryNodeId -Force
        $result | Add-Member -NotePropertyName ArchiveRepository -NotePropertyValue $archive.FullName -Force
        $result | Add-Member -NotePropertyName ArchiveRepositoryId -NotePropertyValue $repositoryIdentity.ArchiveRepositoryId -Force
        $result | Add-Member -NotePropertyName ArchiveRepositoryNodeId -NotePropertyValue $archiveRepositoryNodeId -Force
        $result | Add-Member -NotePropertyName ArchivedOriginalIdentityPreserved -NotePropertyValue ($repositoryIdentity.ArchiveRepositoryId -eq $repositoryIdentity.SourceRepositoryId) -Force
        $result | Add-Member -NotePropertyName ReplacementDestinationRepository -NotePropertyValue $replacement.FullName -Force
        $result | Add-Member -NotePropertyName ReplacementDestinationRepositoryId -NotePropertyValue $replacementRepositoryId -Force
        $result | Add-Member -NotePropertyName ReplacementDestinationRepositoryNodeId -NotePropertyValue $replacementRepositoryNodeId -Force
        $result | Add-Member -NotePropertyName ReplacementHasDistinctIdentity -NotePropertyValue ($replacementRepositoryId -ne $repositoryIdentity.SourceRepositoryId) -Force
        $result | Add-Member -NotePropertyName DestinationRepositoryId -NotePropertyValue $replacementRepositoryId -Force
        $result | Add-Member -NotePropertyName DestinationRepositoryNodeId -NotePropertyValue $replacementRepositoryNodeId -Force
        $result | Add-Member -NotePropertyName ReplacedDestinationRepositoryId -NotePropertyValue $originalRepositoryId -Force
        $result | Add-Member -NotePropertyName CompletedSteps -NotePropertyValue @($completedSteps) -Force

        if ($ReportPath) {
            $failureStage = 'WriteCompletionReport'
            Write-CgrMigrationExecutionReport -Result $result -Path $ReportPath | Out-Null
        }
        return $result
    }
    catch {
        $recoveryReportPath = $null
        try {
            $recoveryReportPath = Write-CgrExistingDestinationRecoveryReport `
                -Plan $Plan `
                -OriginalDestinationRepositoryId $originalRepositoryId `
                -OriginalDestinationRepositoryNodeId $originalRepositoryNodeId `
                -ArchiveRepository $archive `
                -DestinationRepository $replacement `
                -FailureStage $failureStage `
                -ErrorRecord $_ `
                -CompletedSteps @($completedSteps) `
                -PreferredReportPath $ReportPath
        }
        catch {
            Write-Warning "Existing-destination replacement failed after mutation began, and the recovery report could not be written. Recovery reporting error: $($_.Exception.Message)"
        }

        if ($recoveryReportPath) {
            Write-Warning "Existing-destination replacement failed. The previous destination remains preserved when the archive rename completed. Recovery report: $recoveryReportPath"
        }

        throw
    }
}
