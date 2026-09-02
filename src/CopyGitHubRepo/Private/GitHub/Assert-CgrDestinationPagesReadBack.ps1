function Assert-CgrDestinationPagesReadBack {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $DestinationRepository,
        [Parameter(Mandatory)] [psobject] $Pages,
        [switch] $VerifyCustomDomain,
        [ValidateNotNullOrEmpty()] [string] $HostName = 'github.com'
    )

    $actual = Get-CgrGitHubApiOptional -Path "repos/$($DestinationRepository.FullName)/pages" -HostName $HostName
    if ($null -eq $actual) {
        $exception = [System.InvalidOperationException]::new("GitHub Pages was not readable after restoration for '$($DestinationRepository.FullName)'.")
        throw [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationPagesVerificationFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $DestinationRepository.FullName)
    }

    $expectedBuildType = Get-CgrObjectProperty -InputObject $Pages -Name 'BuildType'
    if ((Get-CgrObjectProperty -InputObject $actual -Name 'build_type') -ne $expectedBuildType) {
        $exception = [System.InvalidOperationException]::new("Destination Pages build mode does not match the reviewed '$expectedBuildType' mode.")
        throw [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationPagesVerificationFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $actual)
    }
    if ($expectedBuildType -eq 'legacy') {
        $expectedSource = Get-CgrObjectProperty -InputObject $Pages -Name 'Source'
        $actualSource = Get-CgrObjectProperty -InputObject $actual -Name 'source'
        $expectedBranch = Get-CgrObjectProperty -InputObject $expectedSource -Name 'Branch'
        $expectedPath = Get-CgrObjectProperty -InputObject $expectedSource -Name 'Path'
        $actualBranch = Get-CgrObjectProperty -InputObject $actualSource -Name 'branch'
        $actualPath = Get-CgrObjectProperty -InputObject $actualSource -Name 'path'
        if ($actualBranch -ne $expectedBranch -or $actualPath -ne $expectedPath) {
            $exception = [System.InvalidOperationException]::new('Destination Pages branch/path does not match the exact reviewed source.')
            throw [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationPagesVerificationFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $actualSource)
        }
    }
    $expectedDomain = Get-CgrObjectProperty -InputObject $Pages -Name 'CustomDomain'
    $actualDomain = Get-CgrObjectProperty -InputObject $actual -Name 'cname'
    if ($VerifyCustomDomain -and $actualDomain -ne $expectedDomain) {
        $exception = [System.InvalidOperationException]::new('Destination Pages custom domain does not match the exact reviewed value.')
        throw [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationPagesVerificationFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $actual)
    }
    $expectedHttps = Get-CgrObjectProperty -InputObject $Pages -Name 'HttpsEnforced'
    if ($null -ne $expectedHttps) {
        $actualHttps = Get-CgrObjectProperty -InputObject $actual -Name 'https_enforced'
        $certificate = Get-CgrObjectProperty -InputObject $actual -Name 'https_certificate'
        $httpsNotYetEnforced = $null -eq $actualHttps -or -not [bool] $actualHttps
        $httpsPendingCertificate = [bool] $expectedHttps -and $httpsNotYetEnforced -and $null -eq $certificate
        $httpsMismatch = $null -eq $actualHttps -or [bool] $actualHttps -ne [bool] $expectedHttps
        if (-not $httpsPendingCertificate -and $httpsMismatch) {
            $exception = [System.InvalidOperationException]::new('Destination Pages HTTPS-enforcement state does not match the reviewed intent.')
            throw [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationPagesVerificationFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $actual)
        }
    }
    return $actual
}