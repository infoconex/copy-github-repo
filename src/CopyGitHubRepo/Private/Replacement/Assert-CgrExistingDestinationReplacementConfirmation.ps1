function Assert-CgrExistingDestinationReplacementConfirmation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Plan,

        [AllowNull()]
        [string] $Confirmation
    )

    $expected = "DESTINATION=$($Plan.DestinationRepository);ARCHIVE=$($Plan.ArchiveRepository);REPLACEMENT=$($Plan.DestinationRepository)"
    if ($Confirmation -cne $expected) {
        $message = "Archive-and-replace requires exact confirmation. Expected: $expected"
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'ExistingDestinationReplacementConfirmationRequired',
            [System.Management.Automation.ErrorCategory]::PermissionDenied,
            $Plan.DestinationRepository
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    return $true
}
