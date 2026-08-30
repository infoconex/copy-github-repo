function Invoke-CgrRepositoryCopyWizard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $HostName,

        [Parameter(Mandatory)]
        [scriptblock] $ExecutionGuard
    )

    $cancelResult = {
        [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.WizardResult'
            Status = 'Cancelled'
            MutatedGitHub = $false
        }
    }

    Write-CgrWizardMessage -Message 'Copy GitHub Repository' -Style Heading
    Write-CgrWizardMessage -Message 'Discovering repositories and checking GitHub CLI access...' -Style Hint

    $repositories = @(Get-GitHubRepository -HostName $HostName)
    $sourceRepository = $null
    $destinationRepository = $null
    $contentMode = 'Snapshot'
    $commitMessage = 'Initial repository commit'
    $destinationVisibility = $null
    $settingsBehavior = 'Restore'
    $archiveRepositoryName = $null
    $sameNameConfirmation = $null
    $existingDestinationArchiveName = $null
    $existingDestinationConfirmation = $null
    $step = 0

    while ($true) {
        switch ($step) {
            0 {
                $result = Select-CgrWizardRepository -Repositories $repositories -CurrentValue $sourceRepository -AllowCancel
                if ($result.Action -eq 'Cancel') { return & $cancelResult }

                $previousSource = $sourceRepository
                $sourceRepository = $result.Value
                if ($null -eq $sourceRepository) { continue }

                if ($null -eq $previousSource -or $previousSource.FullName -ne $sourceRepository.FullName) {
                    $destinationVisibility = $null
                    $archiveRepositoryName = $null
                    $sameNameConfirmation = $null
                    $existingDestinationArchiveName = $null
                    $existingDestinationConfirmation = $null
                }
                $step = 1
            }

            1 {
                $result = Resolve-CgrWizardDestinationRepository -Repositories $repositories -CurrentValue $destinationRepository -AllowBack -AllowCancel
                if ($result.Action -eq 'Cancel') { return & $cancelResult }
                if ($result.Action -eq 'Back') { $step = 0; continue }

                if ($destinationRepository -ne $result.Value) {
                    $destinationRepository = [string] $result.Value
                    $archiveRepositoryName = $null
                    $sameNameConfirmation = $null
                    $existingDestinationArchiveName = $null
                    $existingDestinationConfirmation = $null
                }

                if ($destinationRepository -ne $sourceRepository.FullName -and (Test-CgrGitHubRepositoryExistence -Repository $destinationRepository -HostName $HostName)) {
                    Write-CgrWizardMessage -Message "Destination '$destinationRepository' already exists." -Status Warning
                    $conflictResult = Read-CgrWizardChoice `
                        -Title 'Existing destination' `
                        -Choices @('Choose another destination', 'Archive and replace existing destination', 'Cancel') `
                        -DefaultValue 'Choose another destination' `
                        -HelpTopic ExistingDestination `
                        -AllowBack `
                        -AllowCancel

                    if ($conflictResult.Action -eq 'Cancel' -or $conflictResult.Value -eq 'Cancel') { return & $cancelResult }
                    if ($conflictResult.Action -eq 'Back') { $step = 0; continue }
                    if ($conflictResult.Value -eq 'Choose another destination') {
                        $destinationRepository = $null
                        $existingDestinationArchiveName = $null
                        $existingDestinationConfirmation = $null
                        continue
                    }

                    if ([string]::IsNullOrWhiteSpace($existingDestinationArchiveName)) {
                        $existingDestinationArchiveName = Get-CgrDefaultArchiveRepositoryName -Repository $destinationRepository
                    }

                    while ($true) {
                        $archiveResult = Read-CgrWizardRepositoryName -Kind Archive -CurrentValue $existingDestinationArchiveName -AllowBack -AllowCancel
                        if ($archiveResult.Action -eq 'Cancel') { return & $cancelResult }
                        if ($archiveResult.Action -eq 'Back') {
                            $existingDestinationArchiveName = $null
                            $existingDestinationConfirmation = $null
                            break
                        }

                        $candidateArchiveName = [string] $archiveResult.Value
                        $destinationOwner = $destinationRepository.Split('/', 2)[0]
                        $candidateArchive = "$destinationOwner/$candidateArchiveName"
                        if (Test-CgrGitHubRepositoryExistence -Repository $candidateArchive -HostName $HostName) {
                            Write-CgrWizardMessage -Message "Archive repository '$candidateArchive' already exists. Choose another archive name." -Status Warning
                            $existingDestinationArchiveName = $candidateArchiveName
                            continue
                        }

                        if ($existingDestinationArchiveName -ne $candidateArchiveName) { $existingDestinationConfirmation = $null }
                        $existingDestinationArchiveName = $candidateArchiveName
                        break
                    }

                    if ([string]::IsNullOrWhiteSpace($existingDestinationArchiveName)) { continue }
                }
                else {
                    $existingDestinationArchiveName = $null
                    $existingDestinationConfirmation = $null
                }
                $step = 2
            }

            2 {
                $result = Read-CgrWizardChoice `
                    -Title 'Content mode' `
                    -Choices @('Snapshot', 'FullHistory') `
                    -DefaultValue Snapshot `
                    -CurrentValue $contentMode `
                    -HelpTopic ContentMode `
                    -AllowBack `
                    -AllowCancel
                if ($result.Action -eq 'Cancel') { return & $cancelResult }
                if ($result.Action -eq 'Back') { $step = 1; continue }
                $contentMode = [string] $result.Value
                $step = 3
            }

            3 {
                $visibilityChoices = @($sourceRepository.Visibility, 'public', 'private', 'internal') | Select-Object -Unique
                $result = Read-CgrWizardChoice `
                    -Title 'Destination visibility' `
                    -Choices $visibilityChoices `
                    -DefaultValue $sourceRepository.Visibility `
                    -CurrentValue $destinationVisibility `
                    -HelpTopic DestinationVisibility `
                    -AllowBack `
                    -AllowCancel
                if ($result.Action -eq 'Cancel') { return & $cancelResult }
                if ($result.Action -eq 'Back') { $step = 2; continue }
                $destinationVisibility = [string] $result.Value
                $step = 4
            }

            4 {
                $result = Read-CgrWizardChoice `
                    -Title 'Supported repository settings' `
                    -Choices @('Restore', 'Skip') `
                    -DefaultValue Restore `
                    -CurrentValue $settingsBehavior `
                    -HelpTopic SupportedSettings `
                    -AllowBack `
                    -AllowCancel
                if ($result.Action -eq 'Cancel') { return & $cancelResult }
                if ($result.Action -eq 'Back') { $step = 3; continue }
                $settingsBehavior = [string] $result.Value
                $step = if ($destinationRepository -eq $sourceRepository.FullName) { 5 } else { 6 }
            }

            5 {
                $archiveResult = Read-CgrWizardRepositoryName -Kind Archive -CurrentValue $archiveRepositoryName -AllowBack -AllowCancel
                if ($archiveResult.Action -eq 'Cancel') { return & $cancelResult }
                if ($archiveResult.Action -eq 'Back') { $step = 4; continue }

                if ($archiveRepositoryName -ne $archiveResult.Value) {
                    $archiveRepositoryName = [string] $archiveResult.Value
                    $sameNameConfirmation = $null
                }

                $expectedConfirmation = "SOURCE=$($sourceRepository.FullName);ARCHIVE=$($sourceRepository.Owner)/$archiveRepositoryName;REPLACEMENT=$destinationRepository"
                while ($true) {
                    Write-CgrWizardMessage -Message 'Same-name replacement preserves the current repository as an archive before creating the replacement.' -Status Warning
                    Write-CgrWizardMessage -Message 'Exact confirmation is required and cannot be bypassed.' -Style Hint
                    Write-CgrWizardMessage -Message 'Required text:' -Style Hint
                    Write-CgrWizardMessage -Message $expectedConfirmation -Style Value
                    if (-not [string]::IsNullOrWhiteSpace($sameNameConfirmation)) {
                        Write-CgrWizardMessage -Message 'A valid confirmation is already stored. Press Enter to reuse it.' -Style Hint
                    }

                    $inputText = Read-CgrWizardInput `
                        -Prompt 'Exact confirmation' `
                        -DefaultValue $sameNameConfirmation `
                        -AllowHelp `
                        -AllowBack `
                        -AllowCancel
                    $navigation = Resolve-CgrWizardNavigationInput `
                        -InputText $inputText `
                        -AllowBack `
                        -AllowNext:(-not [string]::IsNullOrWhiteSpace($sameNameConfirmation)) `
                        -AllowCancel `
                        -AllowHelp

                    if ($null -ne $navigation) {
                        if ($navigation.Action -eq 'Help') { Show-CgrWizardHelp -Topic ExactConfirmation; continue }
                        if ($navigation.Action -eq 'Cancel') { return & $cancelResult }
                        if ($navigation.Action -eq 'Back') { $step = 4; break }
                        if ($navigation.Action -eq 'Next') { $step = 6; break }
                    }

                    if ($inputText -ceq $expectedConfirmation) {
                        $sameNameConfirmation = $inputText
                        $step = 6
                        break
                    }
                    Write-CgrWizardMessage -Message 'The confirmation did not match exactly. Retry, go Back, or Cancel.' -Status Warning
                }
            }

            6 {
                if ($contentMode -eq 'Snapshot') {
                    $commitMessageResult = Read-CgrWizardTextValue `
                        -Title 'Snapshot commit message' `
                        -DefaultValue 'Initial repository commit' `
                        -CurrentValue $commitMessage `
                        -HelpTopic SnapshotCommitMessage `
                        -AllowBack `
                        -AllowCancel
                    if ($commitMessageResult.Action -eq 'Cancel') { return & $cancelResult }
                    if ($commitMessageResult.Action -eq 'Back') {
                        $step = if ($destinationRepository -eq $sourceRepository.FullName) { 5 } else { 4 }
                        continue
                    }
                    $commitMessage = [string] $commitMessageResult.Value
                }

                $planParameters = @{
                    SourceRepository = $sourceRepository.FullName
                    DestinationRepository = $destinationRepository
                    ContentMode = $contentMode
                    HostName = $HostName
                    PlanOnly = $true
                }
                if ($contentMode -eq 'Snapshot') { $planParameters.CommitMessage = $commitMessage }
                if ($destinationVisibility -ne $sourceRepository.Visibility) { $planParameters.DestinationVisibility = $destinationVisibility }
                if ($settingsBehavior -eq 'Skip') { $planParameters.SkipSettings = $true }
                if ($destinationRepository -eq $sourceRepository.FullName) {
                    $planParameters.ArchiveRepositoryName = $archiveRepositoryName
                }
                elseif (-not [string]::IsNullOrWhiteSpace($existingDestinationArchiveName)) {
                    $planParameters.ExistingDestinationArchiveName = $existingDestinationArchiveName
                }

                $plan = Copy-GitHubRepository @planParameters

                Write-CgrWizardMessage
                Write-CgrWizardMessage -Message 'Repository copy plan' -Style Heading
                Write-CgrWizardMessage -Message ('  Source: {0}' -f $plan.SourceRepository) -Style Value
                Write-CgrWizardMessage -Message ('  Destination: {0}' -f $plan.DestinationRepository) -Style Value
                Write-CgrWizardMessage -Message ('  Content mode: {0}' -f $plan.ContentMode)
                if ($plan.ContentMode -eq 'Snapshot') {
                    Write-CgrWizardMessage -Message '  Snapshot publishes the approved default-branch content as one new root commit without prior Git history.' -Style Hint
                    Write-CgrWizardMessage -Message ('  Approved source commit: {0}' -f $plan.SourceState.CommitSha) -Style Hint
                    Write-CgrWizardMessage -Message ('  Commit message: {0}' -f $plan.CommitMessage) -Style Hint

                    $historicalRecords = Get-CgrObjectProperty -InputObject $plan.SourceState -Name 'HistoricalRecords'
                    if ($historicalRecords) {
                        $tagCount = [int] (Get-CgrObjectProperty -InputObject $historicalRecords -Name 'TagCount')
                        $releaseCount = [int] (Get-CgrObjectProperty -InputObject $historicalRecords -Name 'ReleaseCount')
                        Write-CgrWizardMessage -Message ('  Git tags: {0} (not copied)' -f $tagCount) -Style Hint
                        Write-CgrWizardMessage -Message ('  GitHub Releases: {0} (not copied)' -f $releaseCount) -Style Hint
                        if ($plan.Mode -eq 'SameNameReplacement' -and ($tagCount -gt 0 -or $releaseCount -gt 0)) {
                            Write-CgrWizardMessage -Message 'Existing tags and GitHub Releases remain with the archived original repository; they are not recreated on the clean replacement.' -Status Warning
                            Write-CgrWizardMessage -Message 'Create the new release tag and GitHub Release only after the clean replacement has completed and been verified.' -Style Hint
                        }
                    }
                }
                else {
                    Write-CgrWizardMessage -Message '  FullHistory preserves the approved branches, tags, commits, and reachable Git LFS objects.' -Style Hint
                    Write-CgrWizardMessage -Message ('  Approved refs: {0}; reachable commits: {1}' -f @($plan.SourceState.Refs).Count, $plan.SourceState.ReachableCommitCount) -Style Hint
                }
                Write-CgrWizardMessage -Message ('  Visibility: {0}' -f $plan.DestinationVisibility)
                if (-not [string]::IsNullOrWhiteSpace([string] $plan.ArchiveRepository)) {
                    Write-CgrWizardMessage -Message ('  Archive: {0}' -f $plan.ArchiveRepository) -Style Value
                }
                Write-CgrWizardMessage -Message '  Planned steps:' -Style Heading
                foreach ($plannedStep in @($plan.Steps)) {
                    Write-CgrWizardMessage -Message ('    - {0}' -f $plannedStep.Description)
                }

                $confirmation = Read-CgrWizardChoice `
                    -Title 'Repository copy plan' `
                    -Choices @('Execute', 'Cancel') `
                    -DefaultValue Cancel `
                    -HelpTopic MigrationPlan `
                    -AllowBack `
                    -AllowCancel
                if ($confirmation.Action -eq 'Cancel' -or $confirmation.Value -eq 'Cancel') { return & $cancelResult }
                if ($confirmation.Action -eq 'Back') {
                    $step = if ($destinationRepository -eq $sourceRepository.FullName) { 5 } else { 4 }
                    continue
                }
                if ($confirmation.Value -ne 'Execute') { continue }

                if ($plan.Mode -eq 'ExistingDestinationReplacement') {
                    $expectedConfirmation = "DESTINATION=$($plan.DestinationRepository);ARCHIVE=$($plan.ArchiveRepository);REPLACEMENT=$($plan.DestinationRepository)"
                    while ($true) {
                        Write-CgrWizardMessage -Message 'The existing destination will be preserved as an archive before a fresh replacement is created.' -Status Warning
                        Write-CgrWizardMessage -Message 'Exact confirmation is required and cannot be bypassed.' -Style Hint
                        Write-CgrWizardMessage -Message 'Required text:' -Style Hint
                        Write-CgrWizardMessage -Message $expectedConfirmation -Style Value
                        $inputText = Read-CgrWizardInput -Prompt 'Exact confirmation' -AllowHelp -AllowCancel
                        $navigation = Resolve-CgrWizardNavigationInput -InputText $inputText -AllowCancel -AllowHelp
                        if ($null -ne $navigation) {
                            if ($navigation.Action -eq 'Help') { Show-CgrWizardHelp -Topic ExactConfirmation; continue }
                            if ($navigation.Action -eq 'Cancel') { return & $cancelResult }
                        }
                        if ($inputText -ceq $expectedConfirmation) {
                            $existingDestinationConfirmation = $inputText
                            break
                        }
                        Write-CgrWizardMessage -Message 'The confirmation did not match exactly. Retry or Cancel.' -Status Warning
                    }
                }

                if (-not (& $ExecutionGuard $destinationRepository)) { return $plan }

                Write-CgrWizardMessage -Message 'Executing the reviewed repository copy plan...' -Status Info
                try {
                    $executionResult = Invoke-CgrApprovedMigrationPlan `
                        -Plan $plan `
                        -SourceRepository $sourceRepository `
                        -SameNameConfirmation $sameNameConfirmation `
                        -ExistingDestinationConfirmation $existingDestinationConfirmation `
                        -HostName $HostName
                }
                catch {
                    $errorId = ([string] $_.FullyQualifiedErrorId).Split(',', 2)[0]
                    if ($errorId -eq 'SourceStateChangedSincePlanning') {
                        Write-CgrWizardMessage -Message $_.Exception.Message -Status Warning
                        Write-CgrWizardMessage -Message 'A new plan will be created for review. No GitHub mutation was performed from the stale plan.' -Style Hint
                        $sameNameConfirmation = $null
                        $existingDestinationConfirmation = $null
                        $step = 6
                        continue
                    }
                    throw
                }

                Write-CgrWizardCompletionSummary -Result $executionResult
                return $executionResult
            }
        }
    }
}
