function Assert-CgrSameNameReplacementConfirmation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Plan,

        [string] $Confirmation
    )

    $expectedConfirmation = "SOURCE=$($Plan.SourceRepository);ARCHIVE=$($Plan.ArchiveRepository);REPLACEMENT=$($Plan.DestinationRepository)"
    if ($Confirmation -cne $expectedConfirmation) {
        $message = "Same-name replacement requires exact confirmation before mutation. Supply -SameNameConfirmation '$expectedConfirmation'. -Force does not bypass this requirement."
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'SameNameReplacementConfirmationRequired',
            [System.Management.Automation.ErrorCategory]::PermissionDenied,
            $Plan.DestinationRepository
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    return $expectedConfirmation
}
