function Invoke-CgrGitCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $HostName,

        [string[]] $ArgumentList = @(),

        [hashtable] $Environment = @{}
    )

    $credentialHelperKey = "credential.https://$HostName.helper"
    $prefixArgumentList = @(
        '-c'
        "$credentialHelperKey="
        '-c'
        "$credentialHelperKey=!gh auth git-credential"
    )

    $effectiveEnvironment = @{
        GIT_TERMINAL_PROMPT = '0'
    }
    foreach ($name in $Environment.Keys) {
        $effectiveEnvironment[$name] = $Environment[$name]
    }

    Invoke-CgrNativeCommand `
        -FilePath 'git' `
        -PrefixArgumentList $prefixArgumentList `
        -ArgumentList $ArgumentList `
        -Environment $effectiveEnvironment
}
