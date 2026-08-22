function Read-CgrWizardChoice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Title,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Choices,

        [AllowEmptyString()]
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

    $effectiveValue = $null
    if (-not [string]::IsNullOrWhiteSpace($CurrentValue) -and $CurrentValue -in $Choices) {
        $effectiveValue = $CurrentValue
    }
    elseif (-not [string]::IsNullOrWhiteSpace($DefaultValue) -and $DefaultValue -in $Choices) {
        $effectiveValue = $DefaultValue
    }

    $displayTitle = if ($Title -eq 'Repository copy plan' -and 'Execute' -in $Choices -and 'Cancel' -in $Choices) {
        'Confirm repository copy'
    }
    else {
        $Title
    }

    while ($true) {
        Write-CgrWizardMessage
        Write-CgrWizardMessage -Message $displayTitle -Style Heading
        for ($index = 0; $index -lt $Choices.Count; $index++) {
            $choice = $Choices[$index]
            $suffix = if ($choice -eq $effectiveValue) { ' (default)' } else { '' }
            Write-CgrWizardMessage -Message ('  {0}. {1}{2}' -f ($index + 1), $choice, $suffix)
        }

        $inputText = Read-CgrWizardInput `
            -Prompt 'Choose an option' `
            -DefaultValue $effectiveValue `
            -AllowHelp:(-not [string]::IsNullOrWhiteSpace($HelpTopic)) `
            -AllowBack:$AllowBack `
            -AllowCancel:$AllowCancel
        $navigation = Resolve-CgrWizardNavigationInput `
            -InputText $inputText `
            -AllowBack:$AllowBack `
            -AllowNext:($null -ne $effectiveValue) `
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

        $choiceNumber = 0
        if ([int]::TryParse($inputText, [ref] $choiceNumber) -and
            $choiceNumber -ge 1 -and
            $choiceNumber -le $Choices.Count) {
            return ConvertTo-CgrWizardNavigationResult -Action Next -Value $Choices[$choiceNumber - 1]
        }

        $matchingChoice = @($Choices | Where-Object { $_ -eq $inputText })
        if ($matchingChoice.Count -eq 1) {
            return ConvertTo-CgrWizardNavigationResult -Action Next -Value $matchingChoice[0]
        }

        Write-CgrWizardMessage -Message 'Enter a listed number or value, or use one of the bracketed commands shown at the prompt.' -Style Hint
    }
}
