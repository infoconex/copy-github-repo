function Get-CgrActivityTerminalState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [AllowNull()]
        [object] $Result
    )

    if ($null -eq $Result) {
        return 'Completed'
    }

    $isSuccessfulProperty = $Result.PSObject.Properties['IsSuccessful']
    if ($null -ne $isSuccessfulProperty -and -not [bool] $isSuccessfulProperty.Value) {
        return 'Failed'
    }

    if ($Name -eq 'RestoreRepositoryProtection') {
        $status = [string] (Get-CgrObjectProperty -InputObject $Result -Name 'Status')
        switch ($status) {
            'NotApplicable' { return 'Info' }
            'Skipped' { return 'Info' }
            'Unsupported' { return 'Warning' }
            'Partial' { return 'Warning' }
            'Failed' { return 'Failed' }
        }
    }

    if ($Name -eq 'RestoreSupportedSettings') {
        $restored = @(Get-CgrObjectProperty -InputObject $Result -Name 'Restored')
        if ($restored.Count -eq 0) {
            return 'Info'
        }
    }

    if ($Name -eq 'TransferGitLfs') {
        $usesGitLfs = Get-CgrObjectProperty -InputObject $Result -Name 'UsesGitLfs'
        if ($null -ne $usesGitLfs -and -not [bool] $usesGitLfs) {
            return 'Info'
        }
    }

    return 'Completed'
}
