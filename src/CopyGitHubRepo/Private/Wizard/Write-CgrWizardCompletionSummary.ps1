function Write-CgrWizardCompletionSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Result,

        [string] $ReportPath
    )

    $plan = Get-CgrObjectProperty -InputObject $Result -Name 'Plan'
    $provenance = Get-CgrObjectProperty -InputObject $Result -Name 'Provenance'
    $destination = [string] (Get-CgrObjectProperty -InputObject $Result -Name 'DestinationRepository')
    $destinationUrl = [string] (Get-CgrObjectProperty -InputObject $Result -Name 'DestinationHtmlUrl')
    $archive = if ($plan) { [string] (Get-CgrObjectProperty -InputObject $plan -Name 'ArchiveRepository') } else { '' }
    $contentMode = if ($plan) { [string] (Get-CgrObjectProperty -InputObject $plan -Name 'ContentMode') } else { '' }
    $isVerified = [bool] (Get-CgrObjectProperty -InputObject $Result -Name 'IsVerified')
    $skipSettings = [bool] ($plan -and (Get-CgrObjectProperty -InputObject $plan -Name 'SkipSettings'))
    $settings = Get-CgrObjectProperty -InputObject $Result -Name 'Settings'
    $protection = Get-CgrObjectProperty -InputObject $Result -Name 'Protection'
    $settingsRestored = [bool] (Get-CgrObjectProperty -InputObject $Result -Name 'SettingsRestored')
    $protectionRestored = [bool] (Get-CgrObjectProperty -InputObject $Result -Name 'ProtectionRestored')

    Write-CgrWizardMessage
    if ($isVerified) {
        Write-CgrWizardMessage -Message 'Verify destination content' -Status Success
    }
    else {
        Write-CgrWizardMessage -Message 'Destination content verification did not complete successfully.' -Status Error
    }

    if ($skipSettings) {
        Write-CgrWizardMessage -Message 'Supported repository settings were skipped by request.' -Style Hint
        Write-CgrWizardMessage -Message 'Repository protection was skipped by request.' -Style Hint
    }
    else {
        if ($settingsRestored) {
            Write-CgrWizardMessage -Message 'Restore supported repository settings' -Status Success
        }
        elseif ($settings -and [bool] (Get-CgrObjectProperty -InputObject $settings -Name 'IsSuccessful')) {
            Write-CgrWizardMessage -Message 'Supported repository settings required no additional restoration.' -Style Hint
        }
        else {
            Write-CgrWizardMessage -Message 'Supported repository settings were not fully restored.' -Status Warning
        }

        $protectionStatus = if ($protection) { [string] (Get-CgrObjectProperty -InputObject $protection -Name 'Status') } else { '' }
        $restoredProtection = @(if ($protection) { Get-CgrObjectProperty -InputObject $protection -Name 'Restored' })
        $skippedProtection = @(if ($protection) { Get-CgrObjectProperty -InputObject $protection -Name 'Skipped' })
        $protectionSuccessful = [bool] ($protection -and (Get-CgrObjectProperty -InputObject $protection -Name 'IsSuccessful'))
        $protectionComplete = [bool] ($protection -and (Get-CgrObjectProperty -InputObject $protection -Name 'IsComplete'))

        if ([string]::IsNullOrWhiteSpace($protectionStatus)) {
            $protectionStatus = if ($protectionRestored -and $restoredProtection.Count -gt 0) {
                'Restored'
            }
            elseif ($protectionSuccessful -and $restoredProtection.Count -eq 0 -and $skippedProtection.Count -eq 0) {
                'NotApplicable'
            }
            elseif ($protectionSuccessful -and $restoredProtection.Count -gt 0 -and -not $protectionComplete) {
                'Partial'
            }
            elseif ($protectionSuccessful -and $skippedProtection.Count -gt 0) {
                'Unsupported'
            }
            elseif (-not $protectionSuccessful) {
                'Failed'
            }
            else {
                'Skipped'
            }
        }

        switch ($protectionStatus) {
            'Restored' {
                Write-CgrWizardMessage -Message 'Restore transferable repository protection' -Status Success
            }
            'NotApplicable' {
                Write-CgrWizardMessage -Message 'No transferable repository protection to restore.' -Style Hint
            }
            'Skipped' {
                Write-CgrWizardMessage -Message 'Repository protection restoration was skipped.' -Style Hint
            }
            'Unsupported' {
                $detail = if ($skippedProtection.Count -gt 0) { ': ' + ($skippedProtection -join ', ') } else { '.' }
                Write-CgrWizardMessage -Message ('Repository protection was not transferable{0}' -f $detail) -Status Warning
            }
            'Partial' {
                Write-CgrWizardMessage -Message 'Repository protection was only partially restored.' -Status Warning
            }
            default {
                Write-CgrWizardMessage -Message 'Repository protection restoration failed.' -Status Error
            }
        }
    }

    $replacementRepositoryId = Get-CgrObjectProperty -InputObject $Result -Name 'ReplacementDestinationRepositoryId'
    if ($null -ne $replacementRepositoryId) {
        $archiveRepositoryId = Get-CgrObjectProperty -InputObject $Result -Name 'ArchiveRepositoryId'
        $identityPreserved = [bool] (Get-CgrObjectProperty -InputObject $Result -Name 'ArchivedOriginalIdentityPreserved')
        $replacementDistinct = [bool] (Get-CgrObjectProperty -InputObject $Result -Name 'ReplacementHasDistinctIdentity')
        if ($identityPreserved) {
            Write-CgrWizardMessage -Message ('Archived original identity preserved (repository ID {0}).' -f $archiveRepositoryId) -Status Success
        }
        else {
            Write-CgrWizardMessage -Message 'Archived original repository identity could not be confirmed.' -Status Error
        }
        if ($replacementDistinct) {
            Write-CgrWizardMessage -Message ('Replacement uses a new repository identity (repository ID {0}).' -f $replacementRepositoryId) -Status Success
        }
        else {
            Write-CgrWizardMessage -Message 'Replacement repository identity is not distinct from the original.' -Status Error
        }
    }

    $overallSuccessful = $isVerified -and ($skipSettings -or ($settingsRestored -and $protectionStatus -notin @('Failed', 'Partial', 'Unsupported')))
    Write-CgrWizardMessage
    if ($overallSuccessful) {
        Write-CgrWizardMessage -Message 'Repository copy complete' -Style Heading
    }
    else {
        Write-CgrWizardMessage -Message 'Repository copy completed with warnings' -Style Heading
    }

    if (-not [string]::IsNullOrWhiteSpace($destination)) {
        Write-CgrWizardMessage -Message ('  Destination: {0}' -f $destination) -Style Value
    }
    if (-not [string]::IsNullOrWhiteSpace($destinationUrl)) {
        Write-CgrWizardMessage -Message ('  URL: {0}' -f $destinationUrl) -Style Hint
    }
    if (-not [string]::IsNullOrWhiteSpace($archive)) {
        Write-CgrWizardMessage -Message ('  Archive: {0}' -f $archive) -Style Value
    }
    if (-not [string]::IsNullOrWhiteSpace($contentMode)) {
        Write-CgrWizardMessage -Message ('  Mode: {0}' -f $contentMode)
    }

    if ($contentMode -eq 'Snapshot' -and $provenance) {
        $sourceCommit = [string] (Get-CgrObjectProperty -InputObject $provenance -Name 'SourceCommitSha')
        $sourceTree = [string] (Get-CgrObjectProperty -InputObject $provenance -Name 'SourceTreeSha')
        $destinationCommit = [string] (Get-CgrObjectProperty -InputObject $provenance -Name 'DestinationRootCommitSha')
        if (-not [string]::IsNullOrWhiteSpace($sourceCommit)) {
            Write-CgrWizardMessage -Message ('  Source commit: {0}' -f $sourceCommit) -Style Hint
        }
        if (-not [string]::IsNullOrWhiteSpace($sourceTree)) {
            Write-CgrWizardMessage -Message ('  Source tree: {0}' -f $sourceTree) -Style Hint
        }
        if (-not [string]::IsNullOrWhiteSpace($destinationCommit)) {
            Write-CgrWizardMessage -Message ('  Snapshot root commit: {0}' -f $destinationCommit) -Style Hint
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
        Write-CgrWizardMessage -Message ('  Report: {0}' -f $ReportPath) -Style Hint
    }
}
