function Write-CgrWizardMessage {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string] $Message = '',

        [ValidateSet('None', 'Pass', 'Success', 'Fail', 'Error', 'Warning', 'Info')]
        [string] $Status = 'None',

        [ValidateSet('Normal', 'Heading', 'Prompt', 'Hint', 'Muted', 'Value', 'Success', 'Warning', 'Error')]
        [string] $Style = 'Normal'
    )

    if ($Status -ne 'None') {
        $Host.UI.WriteLine((Format-CgrConsoleStatus -Status $Status -Message $Message))
        return
    }

    $Host.UI.WriteLine((Format-CgrWizardText -Text $Message -Style $Style))
}
