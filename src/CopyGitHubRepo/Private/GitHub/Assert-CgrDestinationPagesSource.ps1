function Assert-CgrDestinationPagesSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $DestinationRepository,
        [Parameter(Mandatory)] [psobject] $Pages,
        [ValidateNotNullOrEmpty()] [string] $HostName = 'github.com'
    )

    if ((Get-CgrObjectProperty -InputObject $Pages -Name 'BuildType') -ne 'legacy') { return }
    $source = Get-CgrObjectProperty -InputObject $Pages -Name 'Source'
    $branch = [string] (Get-CgrObjectProperty -InputObject $source -Name 'Branch')
    $path = [string] (Get-CgrObjectProperty -InputObject $source -Name 'Path')
    if ([string]::IsNullOrWhiteSpace($branch) -or $path -notin @('/', '/docs')) {
        $exception = [System.InvalidOperationException]::new('The reviewed branch/path Pages source is incomplete or unsupported.')
        throw [System.Management.Automation.ErrorRecord]::new($exception, 'ApprovedPagesSourceInvalid', [System.Management.Automation.ErrorCategory]::InvalidData, $source)
    }

    $encodedBranch = [Uri]::EscapeDataString($branch)
    if ($null -eq (Get-CgrGitHubApiOptional -Path "repos/$($DestinationRepository.FullName)/branches/$encodedBranch" -HostName $HostName)) {
        $exception = [System.InvalidOperationException]::new("The exact reviewed Pages publishing branch '$branch' does not exist at destination '$($DestinationRepository.FullName)'.")
        throw [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationPagesBranchMissing', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $branch)
    }
    if ($path -eq '/docs' -and
        $null -eq (Get-CgrGitHubApiOptional -Path "repos/$($DestinationRepository.FullName)/contents/docs?ref=$encodedBranch" -HostName $HostName)) {
        $exception = [System.InvalidOperationException]::new("The exact reviewed Pages publishing path '/docs' does not exist on destination branch '$branch'.")
        throw [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationPagesPathMissing', [System.Management.Automation.ErrorCategory]::ObjectNotFound, '/docs')
    }
}
