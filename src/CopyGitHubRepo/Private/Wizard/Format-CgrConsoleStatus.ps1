function Format-CgrConsoleStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Pass', 'Success', 'Fail', 'Error', 'Warning', 'Info')]
        [string] $Status,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Message,

        [switch] $NoColor
    )

    $checkMark = [char] 0x2713
    $crossMark = [char] 0x2717
    $bullet = [char] 0x2022

    $statusDefinition = switch ($Status) {
        'Pass' {
            [pscustomobject] @{ Symbol = $checkMark; Label = 'PASS'; Color = $PSStyle.Foreground.Green }
        }
        'Success' {
            [pscustomobject] @{ Symbol = $checkMark; Label = 'SUCCESS'; Color = $PSStyle.Foreground.Green }
        }
        'Fail' {
            [pscustomobject] @{ Symbol = $crossMark; Label = 'FAIL'; Color = $PSStyle.Foreground.Red }
        }
        'Error' {
            [pscustomobject] @{ Symbol = $crossMark; Label = 'ERROR'; Color = $PSStyle.Foreground.Red }
        }
        'Warning' {
            [pscustomobject] @{ Symbol = '!'; Label = 'WARN'; Color = $PSStyle.Foreground.Yellow }
        }
        'Info' {
            [pscustomobject] @{ Symbol = $bullet; Label = 'INFO'; Color = $PSStyle.Foreground.Cyan }
        }
    }

    $statusText = '{0} {1}' -f $statusDefinition.Symbol, $statusDefinition.Label
    $useColor = -not $NoColor -and (Test-CgrConsoleStylingAvailable)

    if ($useColor) {
        $statusText = '{0}{1}{2}' -f $statusDefinition.Color, $statusText, $PSStyle.Reset
    }

    if ([string]::IsNullOrEmpty($Message)) {
        return $statusText
    }

    '{0}  {1}' -f $statusText, $Message
}
