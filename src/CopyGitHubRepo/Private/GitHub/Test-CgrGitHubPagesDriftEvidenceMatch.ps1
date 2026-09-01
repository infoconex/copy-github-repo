function Test-CgrGitHubPagesDriftEvidenceMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $ReviewedEvidence,
        [Parameter(Mandatory)] [psobject] $CurrentEvidence
    )

    foreach ($name in @('Configured', 'BuildType', 'Branch', 'Path', 'CustomDomain', 'HttpsEnforced')) {
        if ((Get-CgrObjectProperty -InputObject $ReviewedEvidence -Name $name) -ne
            (Get-CgrObjectProperty -InputObject $CurrentEvidence -Name $name)) {
            return $false
        }
    }
    return $true
}
