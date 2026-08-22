function Format-CgrWizardText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [ValidateSet('Normal', 'Heading', 'Prompt', 'Hint', 'Muted', 'Value', 'Success', 'Warning', 'Error')]
        [string] $Style = 'Normal',

        [switch] $NoStyle
    )

    if ($Style -eq 'Normal' -or $NoStyle -or -not (Test-CgrConsoleStylingAvailable)) {
        return $Text
    }

    $italic = "`e[3m"
    $prefix = switch ($Style) {
        'Heading' { $PSStyle.Foreground.BrightCyan }
        'Prompt' { $PSStyle.Foreground.Cyan }
        'Hint' { '{0}{1}' -f $PSStyle.Foreground.BrightBlack, $italic }
        'Muted' { $PSStyle.Dim }
        'Value' { $PSStyle.Foreground.BrightBlue }
        'Success' { $PSStyle.Foreground.Green }
        'Warning' { $PSStyle.Foreground.Yellow }
        'Error' { $PSStyle.Foreground.Red }
    }

    '{0}{1}{2}' -f $prefix, $Text, $PSStyle.Reset
}
