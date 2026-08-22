function Assert-CgrReplacementRepositoryIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $SourceRepository,

        [Parameter(Mandatory)]
        [psobject] $ArchiveRepository,

        [Parameter(Mandatory)]
        [psobject] $ReplacementRepository
    )

    $sourceRepositoryId = Get-CgrObjectProperty -InputObject $SourceRepository -Name 'Id'
    $archiveRepositoryId = Get-CgrObjectProperty -InputObject $ArchiveRepository -Name 'Id'
    $replacementRepositoryId = Get-CgrObjectProperty -InputObject $ReplacementRepository -Name 'Id'

    if ($null -eq $sourceRepositoryId -or $null -eq $archiveRepositoryId) {
        $message = 'Source/archive immutable GitHub repository identity is missing. Replacement verification cannot continue safely.'
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'PreservedRepositoryIdentityMissing',
            [System.Management.Automation.ErrorCategory]::InvalidData,
            $ArchiveRepository.FullName
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    if ([long] $archiveRepositoryId -ne [long] $sourceRepositoryId) {
        $message = "Archive GitHub repository ID '$archiveRepositoryId' does not match original source ID '$sourceRepositoryId'."
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'PreservedRepositoryIdentityMismatch',
            [System.Management.Automation.ErrorCategory]::InvalidResult,
            $ArchiveRepository.FullName
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    if ($null -eq $replacementRepositoryId) {
        $message = "Replacement repository '$($ReplacementRepository.FullName)' is missing immutable GitHub repository identity. Migration was stopped before content copy."
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'ReplacementRepositoryIdentityMissing',
            [System.Management.Automation.ErrorCategory]::InvalidData,
            $ReplacementRepository.FullName
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    if ([long] $replacementRepositoryId -eq [long] $sourceRepositoryId) {
        $message = "Replacement repository '$($ReplacementRepository.FullName)' reused preserved source GitHub repository ID '$sourceRepositoryId'. Migration was stopped before content copy."
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'ReplacementRepositoryIdentityCollision',
            [System.Management.Automation.ErrorCategory]::InvalidResult,
            $ReplacementRepository.FullName
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    [pscustomobject] @{
        SourceRepositoryId = [long] $sourceRepositoryId
        ArchiveRepositoryId = [long] $archiveRepositoryId
        ReplacementRepositoryId = [long] $replacementRepositoryId
    }
}
