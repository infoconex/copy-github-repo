function Copy-CgrGitLfsObject {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'The public Copy-GitHubRepository command performs the ShouldProcess check before calling this migration boundary.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SourcePath,

        [Parameter(Mandatory)]
        [psobject] $SourceRepository,

        [Parameter(Mandatory)]
        [psobject] $DestinationRepository,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $BranchName
    )

    $attributeFiles = if ([System.IO.Directory]::Exists($SourcePath)) {
        @([System.IO.Directory]::EnumerateFiles($SourcePath, '.gitattributes', [System.IO.SearchOption]::AllDirectories) |
            Where-Object { $_ -notmatch '[\\/]\.git[\\/]' })
    }
    else {
        @()
    }

    $hasGitLfsFilter = $false
    foreach ($attributeFile in $attributeFiles) {
        foreach ($line in [System.IO.File]::ReadAllLines($attributeFile)) {
            $trimmedLine = $line.Trim()
            if (-not $trimmedLine.StartsWith('#') -and $trimmedLine -match '(^|\s)filter=lfs(\s|$)') {
                $hasGitLfsFilter = $true
                break
            }
        }
        if ($hasGitLfsFilter) {
            break
        }
    }

    if (-not $hasGitLfsFilter) {
        return [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.GitLfsCopyResult'
            UsesGitLfs = $false
            PointerFiles = @()
            ObjectsCopied = $false
            IsSuccessful = $true
        }
    }

    $gitLfsVersionResult = Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('lfs', 'version')
    if ($gitLfsVersionResult.ExitCode -ne 0) {
        $message = "Source repository '$($SourceRepository.FullName)' uses Git LFS, but Git LFS is not available. Install Git LFS before retrying so the referenced objects can be copied safely."
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'GitLfsRequired',
            [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
            'git-lfs'
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $listResult = Invoke-CgrNativeCommand `
        -FilePath 'git' `
        -ArgumentList @('-C', $SourcePath, 'lfs', 'ls-files', '--name-only')
    if ($listResult.ExitCode -ne 0) {
        $message = "Git LFS failed while listing tracked files in '$($SourceRepository.FullName)'. $($listResult.ErrorText)"
        $exception = [System.InvalidOperationException]::new($message.Trim())
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'GitLfsPointerDetectionFailed',
            [System.Management.Automation.ErrorCategory]::InvalidData,
            $SourceRepository.FullName
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $pointerFiles = @($listResult.Output | ForEach-Object { $_.ToString() })
    if ($pointerFiles.Count -eq 0) {
        return [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.GitLfsCopyResult'
            UsesGitLfs = $false
            PointerFiles = @()
            ObjectsCopied = $false
            IsSuccessful = $true
        }
    }

    $fetchResult = Invoke-CgrGitCommand `
        -HostName $SourceRepository.HostName `
        -ArgumentList @('-C', $SourcePath, 'lfs', 'fetch', 'origin', $BranchName)
    if ($fetchResult.ExitCode -ne 0) {
        $message = "Git LFS failed to fetch objects from '$($SourceRepository.FullName)'. $($fetchResult.ErrorText)"
        $exception = [System.InvalidOperationException]::new($message.Trim())
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'SourceGitLfsFetchFailed',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $SourceRepository.FullName
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $remoteName = 'cgr-destination'
    $addRemoteResult = Invoke-CgrNativeCommand `
        -FilePath 'git' `
        -ArgumentList @('-C', $SourcePath, 'remote', 'add', $remoteName, $DestinationRepository.CloneUrl)
    if ($addRemoteResult.ExitCode -ne 0) {
        $message = "Git failed to configure the destination remote for Git LFS migration. $($addRemoteResult.ErrorText)"
        $exception = [System.InvalidOperationException]::new($message.Trim())
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'DestinationGitLfsRemoteConfigurationFailed',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $DestinationRepository.FullName
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    try {
        $pushResult = Invoke-CgrGitCommand `
            -HostName $DestinationRepository.HostName `
            -ArgumentList @('-C', $SourcePath, 'lfs', 'push', '--all', $remoteName, $BranchName)
        if ($pushResult.ExitCode -ne 0) {
            $message = "Git LFS failed to push objects to '$($DestinationRepository.FullName)'. $($pushResult.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'DestinationGitLfsPushFailed',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $DestinationRepository.FullName
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }
    finally {
        Invoke-CgrNativeCommand `
            -FilePath 'git' `
            -ArgumentList @('-C', $SourcePath, 'remote', 'remove', $remoteName) |
            Out-Null
    }

    [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.GitLfsCopyResult'
        UsesGitLfs = $true
        PointerFiles = $pointerFiles
        ObjectsCopied = $true
        IsSuccessful = $true
    }
}
