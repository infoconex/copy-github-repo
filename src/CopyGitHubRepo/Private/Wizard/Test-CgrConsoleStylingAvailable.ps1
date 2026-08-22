function Test-CgrConsoleStylingAvailable {
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrEmpty($env:NO_COLOR)) {
        return $false
    }

    if ($PSStyle.OutputRendering -eq [System.Management.Automation.OutputRendering]::PlainText) {
        return $false
    }

    try {
        if ([Console]::IsOutputRedirected) {
            return $false
        }
    }
    catch {
        return $false
    }

    return $true
}
