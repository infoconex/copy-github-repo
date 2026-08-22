function Rename-CgrGitHubRepository {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'The public Copy-GitHubRepository command performs the ShouldProcess and stronger same-name confirmation checks before calling this GitHub API boundary.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $SourceRepository,
        [Parameter(Mandatory)] [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')] [string] $ArchiveRepository,
        [ValidateNotNullOrEmpty()] [string] $HostName = 'github.com'
    )

    $sourceRepositoryId = Get-CgrObjectProperty -InputObject $SourceRepository -Name 'Id'
    if ($null -eq $sourceRepositoryId) {
        $message = "Source repository '$($SourceRepository.FullName)' is missing immutable GitHub repository identity. Same-name replacement was stopped before mutation."
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'SourceRepositoryIdentityMissing', [System.Management.Automation.ErrorCategory]::InvalidData, $SourceRepository.FullName)
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $normalizedArchive = ConvertTo-CgrRepositoryName -Repository $ArchiveRepository
    $archiveParts = $normalizedArchive.Split('/', 2)
    if ($archiveParts[0] -ne $SourceRepository.Owner) {
        $message = "Archive repository '$normalizedArchive' must remain under source owner '$($SourceRepository.Owner)'."
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'ArchiveRepositoryOwnerMismatch', [System.Management.Automation.ErrorCategory]::InvalidArgument, $normalizedArchive)
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $activityMessage = "Archive '$($SourceRepository.FullName)' as '$normalizedArchive'"
    Send-CgrActivityEvent -Name 'ArchiveRepository' -State Started -Message $activityMessage
    $path = "repos/$($SourceRepository.FullName)"
    $result = Invoke-CgrNativeCommand -FilePath 'gh' -ArgumentList @('api', '--hostname', $HostName, '-X', 'PATCH', $path, '-f', "name=$($archiveParts[1])")

    if ($result.ExitCode -ne 0) {
        Send-CgrActivityEvent -Name 'ArchiveRepository' -State Failed -Message $activityMessage
        $message = "GitHub CLI failed to preserve '$($SourceRepository.FullName)' as '$normalizedArchive'. $($result.ErrorText)"
        $exception = [System.InvalidOperationException]::new($message.Trim())
        $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'GitHubRepositoryRenameFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $SourceRepository.FullName)
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $archive = Get-CgrRepository -Repository $normalizedArchive -HostName $HostName
    if ($archive.FullName -ne $normalizedArchive) {
        Send-CgrActivityEvent -Name 'ArchiveRepository' -State Failed -Message $activityMessage
        $message = "GitHub reported the renamed repository as '$($archive.FullName)' instead of expected archive '$normalizedArchive'."
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'GitHubRepositoryRenameVerificationFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $normalizedArchive)
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $archiveRepositoryId = Get-CgrObjectProperty -InputObject $archive -Name 'Id'
    if ($null -eq $archiveRepositoryId) {
        Send-CgrActivityEvent -Name 'ArchiveRepository' -State Failed -Message $activityMessage
        $message = "Archived repository '$normalizedArchive' is missing immutable GitHub repository identity. Replacement creation was stopped."
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'ArchiveRepositoryIdentityMissing', [System.Management.Automation.ErrorCategory]::InvalidData, $normalizedArchive)
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    if ([long] $archiveRepositoryId -ne [long] $sourceRepositoryId) {
        Send-CgrActivityEvent -Name 'ArchiveRepository' -State Failed -Message $activityMessage
        $message = "Archived repository '$normalizedArchive' has GitHub repository ID '$archiveRepositoryId' instead of original source ID '$sourceRepositoryId'. Replacement creation was stopped."
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'GitHubRepositoryRenameIdentityMismatch', [System.Management.Automation.ErrorCategory]::InvalidResult, $normalizedArchive)
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    Send-CgrActivityEvent -Name 'ArchiveRepository' -State Completed -Message $activityMessage
    return $archive
}
