function Read-CgrWizardInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Prompt,

        [AllowEmptyString()]
        [string] $DefaultValue,

        [switch] $AllowHelp,

        [switch] $AllowBack,

        [switch] $AllowCancel,

        [switch] $AllowFilter,

        [switch] $AllowList,

        [switch] $AllowPreviousPage,

        [switch] $AllowNextPage
    )

    $navigationParts = [System.Collections.Generic.List[string]]::new()
    if ($AllowFilter) { $navigationParts.Add('[F filter]') }
    if ($AllowList) { $navigationParts.Add('[L list]') }
    if ($AllowPreviousPage) { $navigationParts.Add('[P previous]') }
    if ($AllowNextPage) { $navigationParts.Add('[N next]') }
    if ($AllowHelp) { $navigationParts.Add('[? help]') }
    if ($AllowBack) { $navigationParts.Add('[B back]') }
    if ($AllowCancel) { $navigationParts.Add('[C cancel]') }

    $promptParts = [System.Collections.Generic.List[string]]::new()
    $promptParts.Add((Format-CgrWizardText -Text $Prompt -Style Prompt))
    if ($navigationParts.Count -gt 0) {
        $promptParts.Add((Format-CgrWizardText -Text ($navigationParts -join '  ') -Style Hint))
    }
    if (-not [string]::IsNullOrWhiteSpace($DefaultValue)) {
        $promptParts.Add((Format-CgrWizardText -Text ("({0})" -f $DefaultValue) -Style Hint))
    }

    Read-Host -Prompt ($promptParts -join '   ')
}
