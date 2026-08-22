function ConvertTo-CgrWizardNavigationResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Next', 'Back', 'Cancel', 'Help', 'List')]
        [string] $Action,

        [AllowNull()]
        [object] $Value
    )

    [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.WizardNavigationResult'
        Action = $Action
        Value = $Value
    }
}
