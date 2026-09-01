function Test-CgrExpectedWizardApplicationError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    $errorId = ([string] $ErrorRecord.FullyQualifiedErrorId).Split(',', 2)[0]
    $expectedErrorIds = @(
        'ArchiveRepositoryAlreadyExists'
        'ArchiveRepositoryNameRequired'
        'DestinationRepositoryAlreadyExists'
        'EnableActionsAfterMigrationExecutionNotImplemented'
        'ExistingDestinationArchiveAlreadyExists'
        'ExistingDestinationArchiveNotRequired'
        'ExistingDestinationReplacementConfirmationRequired'
        'GitCommitIdentityUnavailable'
        'GitHubCliNotAuthenticated'
        'GitHubCliNotFound'
        'GitNotFound'
        'NonInteractiveExecutionRequiresForce'
        'SameNameReplacementConfirmationRequired'
        'SourceRepositoryEmpty'
        'UnsupportedGitHubHost'
        'VisibilityChangeRequiresForce'
    )

    return $errorId -in $expectedErrorIds
}
