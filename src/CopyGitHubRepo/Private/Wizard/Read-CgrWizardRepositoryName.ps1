function Read-CgrWizardRepositoryName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Destination', 'Archive')]
        [string] $Kind,

        [AllowEmptyString()]
        [string] $CurrentValue,

        [switch] $AllowList,

        [switch] $AllowBack,

        [switch] $AllowCancel
    )

    $pattern = if ($Kind -eq 'Destination') { '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' } else { '^[A-Za-z0-9_.-]+$' }
    $currentIsValid = -not [string]::IsNullOrWhiteSpace($CurrentValue) -and $CurrentValue -match $pattern
    $basePrompt = if ($Kind -eq 'Destination') { 'Destination repository (owner/name)' } else { 'Archive repository name' }
    $helpTopic = if ($Kind -eq 'Destination') { 'DestinationRepository' } else { 'ArchiveRepositoryName' }

    while ($true) {
        Write-CgrWizardMessage
        $inputText = Read-CgrWizardInput `
            -Prompt $basePrompt `
            -DefaultValue $(if ($currentIsValid) { $CurrentValue } else { '' }) `
            -AllowList:($AllowList -and $Kind -eq 'Destination') `
            -AllowHelp `
            -AllowBack:$AllowBack `
            -AllowCancel:$AllowCancel

        if ($AllowList -and $Kind -eq 'Destination' -and $inputText.Trim().ToLowerInvariant() -eq 'l') {
            return ConvertTo-CgrWizardNavigationResult -Action List
        }

        $navigation = Resolve-CgrWizardNavigationInput `
            -InputText $inputText `
            -AllowBack:$AllowBack `
            -AllowNext:$currentIsValid `
            -AllowCancel:$AllowCancel `
            -AllowHelp

        if ($null -ne $navigation) {
            if ($navigation.Action -eq 'Help') {
                Show-CgrWizardHelp -Topic $helpTopic
                continue
            }
            if ($navigation.Action -eq 'Next') { $navigation.Value = $CurrentValue }
            return $navigation
        }

        $candidate = $inputText.Trim()
        if ($candidate -match $pattern) {
            return ConvertTo-CgrWizardNavigationResult -Action Next -Value $candidate
        }

        if ($Kind -eq 'Destination') {
            Write-CgrWizardMessage -Message 'Enter a repository as owner/name using letters, numbers, dot, underscore, or hyphen.' -Style Hint
        }
        else {
            Write-CgrWizardMessage -Message 'Enter a repository name using letters, numbers, dot, underscore, or hyphen.' -Style Hint
        }
    }
}
