function Read-CgrWizardTextValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Title,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $DefaultValue,

        [AllowEmptyString()]
        [string] $CurrentValue,

        [ValidateSet(
            'SourceRepository',
            'DestinationRepository',
            'ExistingDestination',
            'ContentMode',
            'DestinationVisibility',
            'SupportedSettings',
            'SnapshotCommitMessage',
            'ArchiveRepositoryName',
            'MigrationPlan',
            'ExactConfirmation'
        )]
        [string] $HelpTopic,

        [switch] $AllowBack,

        [switch] $AllowCancel
    )

    $effectiveValue = if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
        $CurrentValue
    }
    else {
        $DefaultValue
    }

    while ($true) {
        Write-CgrWizardMessage
        $inputText = Read-CgrWizardInput `
            -Prompt $Title `
            -DefaultValue $effectiveValue `
            -AllowHelp:(-not [string]::IsNullOrWhiteSpace($HelpTopic)) `
            -AllowBack:$AllowBack `
            -AllowCancel:$AllowCancel
        $navigation = Resolve-CgrWizardNavigationInput `
            -InputText $inputText `
            -AllowBack:$AllowBack `
            -AllowNext `
            -AllowCancel:$AllowCancel `
            -AllowHelp:(-not [string]::IsNullOrWhiteSpace($HelpTopic))

        if ($null -ne $navigation) {
            if ($navigation.Action -eq 'Help') {
                Show-CgrWizardHelp -Topic $HelpTopic
                continue
            }

            if ($navigation.Action -eq 'Next') {
                $navigation.Value = $effectiveValue
            }
            return $navigation
        }

        $effectiveValue = $inputText.Trim()
        return ConvertTo-CgrWizardNavigationResult -Action Next -Value $effectiveValue
    }
}
