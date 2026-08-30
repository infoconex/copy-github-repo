function Get-CgrActivityCompletionMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $DefaultMessage,

        [AllowNull()]
        [object] $Result
    )

    if ($null -eq $Result) {
        return $DefaultMessage
    }

    if ($Name -eq 'TransferGitLfs') {
        $usesGitLfs = [bool] (Get-CgrObjectProperty -InputObject $Result -Name 'UsesGitLfs')
        $pointerFiles = @(Get-CgrObjectProperty -InputObject $Result -Name 'PointerFiles')
        $objectsCopied = [bool] (Get-CgrObjectProperty -InputObject $Result -Name 'ObjectsCopied')

        if (-not $usesGitLfs -or $pointerFiles.Count -eq 0) {
            return 'No Git LFS objects found; no transfer required.'
        }

        if ($objectsCopied) {
            return ('Transferred Git LFS objects for {0} tracked path(s).' -f $pointerFiles.Count)
        }

        return ('Git LFS content was detected for {0} tracked path(s), but no objects were transferred.' -f $pointerFiles.Count)
    }

    if ($Name -eq 'VerifyDestinationContent') {
        if ([bool] (Get-CgrObjectProperty -InputObject $Result -Name 'IsSuccessful')) {
            return 'Verified destination content.'
        }

        return 'Destination content verification failed.'
    }

    if ($Name -eq 'RestoreSupportedSettings') {
        $restored = @(Get-CgrObjectProperty -InputObject $Result -Name 'Restored')
        $skipped = @(Get-CgrObjectProperty -InputObject $Result -Name 'Skipped')
        $isSuccessful = [bool] (Get-CgrObjectProperty -InputObject $Result -Name 'IsSuccessful')

        if (-not $isSuccessful) {
            if ($skipped -match 'VerificationFailed') {
                return 'Supported repository settings were not restored because content verification failed.'
            }
            return 'Supported repository settings restoration failed.'
        }
        if ($skipped -contains 'AllSettings') {
            return 'Supported repository settings restoration was skipped by request.'
        }
        if ($restored.Count -eq 0) {
            return 'Supported repository settings required no changes.'
        }
        return 'Restored supported repository settings.'
    }

    if ($Name -eq 'RestoreRepositoryProtection') {
        $status = [string] (Get-CgrObjectProperty -InputObject $Result -Name 'Status')
        $skipped = @(Get-CgrObjectProperty -InputObject $Result -Name 'Skipped')
        switch ($status) {
            'Restored' { return 'Restored transferable repository protection.' }
            'NotApplicable' { return 'No transferable repository protection to restore.' }
            'Skipped' {
                if ($skipped -contains 'AllSettings') {
                    return 'Repository protection restoration was skipped by request.'
                }
                if ($skipped -match 'VerificationFailed') {
                    return 'Repository protection was not restored because content verification failed.'
                }
                return 'Repository protection restoration was skipped.'
            }
            'Unsupported' { return 'Repository protection contains items that cannot be transferred.' }
            'Partial' { return 'Repository protection was only partially restored.' }
            'Failed' { return 'Repository protection restoration failed.' }
        }
    }

    return $DefaultMessage
}
