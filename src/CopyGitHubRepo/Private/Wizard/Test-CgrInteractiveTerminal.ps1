function Test-CgrInteractiveTerminal {
    [CmdletBinding()]
    param()

    try {
        if ([Console]::IsOutputRedirected -or [Console]::IsInputRedirected) {
            return $false
        }
    }
    catch {
        return $false
    }

    return $true
}
