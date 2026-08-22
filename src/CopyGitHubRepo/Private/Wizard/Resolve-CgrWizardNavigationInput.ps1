function Resolve-CgrWizardNavigationInput {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string] $InputText,

        [switch] $AllowBack,

        [switch] $AllowNext,

        [switch] $AllowCancel,

        [switch] $AllowHelp
    )

    $normalized = $InputText.Trim().ToLowerInvariant()

    if ($AllowHelp -and $normalized -eq '?') {
        return ConvertTo-CgrWizardNavigationResult -Action Help
    }

    if ($AllowBack -and $normalized -eq 'b') {
        return ConvertTo-CgrWizardNavigationResult -Action Back
    }

    if ($AllowNext -and [string]::IsNullOrWhiteSpace($normalized)) {
        return ConvertTo-CgrWizardNavigationResult -Action Next
    }

    if ($AllowCancel -and $normalized -eq 'c') {
        return ConvertTo-CgrWizardNavigationResult -Action Cancel
    }

    return $null
}
