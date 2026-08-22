function Assert-CgrSupportedHostName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $HostName
    )

    if ($HostName.Equals('github.com', [System.StringComparison]::OrdinalIgnoreCase)) {
        return
    }

    $message = "GitHub host '$HostName' is not supported in version 1. Only 'github.com' is supported. GitHub Enterprise support is reserved for a future release."
    $exception = [System.NotSupportedException]::new($message)
    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
        $exception,
        'GitHubHostNotSupported',
        [System.Management.Automation.ErrorCategory]::NotImplemented,
        $HostName
    )
    $PSCmdlet.ThrowTerminatingError($errorRecord)
}
