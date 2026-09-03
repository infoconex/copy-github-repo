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

    $readOptionalReleaseValue = {
        param(
            [Parameter(Mandatory)]
            [string] $Prompt,

            [AllowEmptyString()]
            [string] $CurrentValue,

            [switch] $PositiveInteger
        )

        while ($true) {
            Write-CgrWizardMessage
            Write-CgrWizardMessage -Message 'Press Enter to keep the current value. Enter - to clear it.' -Style Hint
            $inputText = Read-CgrWizardInput `
                -Prompt $Prompt `
                -DefaultValue $CurrentValue `
                -AllowBack `
                -AllowCancel
            $navigation = Resolve-CgrWizardNavigationInput `
                -InputText $inputText `
                -AllowBack `
                -AllowNext `
                -AllowCancel

            if ($null -ne $navigation) {
                if ($navigation.Action -eq 'Next') { $navigation.Value = $CurrentValue }
                return $navigation
            }

            $candidate = $inputText.Trim()
            if ($candidate -eq '-') {
                return ConvertTo-CgrWizardNavigationResult -Action Next -Value ''
            }
            if (-not $PositiveInteger) {
                return ConvertTo-CgrWizardNavigationResult -Action Next -Value $candidate
            }

            $count = 0
            if ([int]::TryParse($candidate, [ref] $count) -and $count -gt 0) {
                return ConvertTo-CgrWizardNavigationResult -Action Next -Value $candidate
            }
            Write-CgrWizardMessage -Message 'Enter a positive whole number, -, Back, or Cancel.' -Status Warning
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
    $restorePages = $false
    $archiveRepositoryName = $null
    $sameNameConfirmation = $null
    $existingDestinationArchiveName = $null
    $existingDestinationConfirmation = $null
    $snapshotReleaseOptions = [pscustomobject] @{
        IncludeReleases = $false
        ReleaseTag = ''
        ReleaseExcludeTag = ''
        IncludePrerelease = $false
        IncludeDraftReleases = $false
        ReleaseCount = ''
    }
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
                Write-CgrWizardMessage -Message 'GitHub Pages is GitHub-side state and is restored only when explicitly selected.' -Style Hint
                $currentSettingsChoice = if ($restorePages) {
                    if ($settingsBehavior -eq 'Skip') { 'Skip settings + restore GitHub Pages' } else { 'Restore settings + GitHub Pages' }
                }
                else {
                    $settingsBehavior
                }
                $result = Read-CgrWizardChoice `
                    -Title 'Supported repository settings' `
                    -Choices @('Restore', 'Skip', 'Restore settings + GitHub Pages', 'Skip settings + restore GitHub Pages') `
                    -DefaultValue Restore `
                    -CurrentValue $currentSettingsChoice `
                    -HelpTopic SupportedSettings `
                    -AllowBack `
                    -AllowCancel
                if ($result.Action -eq 'Cancel') { return & $cancelResult }
                if ($result.Action -eq 'Back') { $step = 3; continue }
                $settingsChoice = [string] $result.Value
                $settingsBehavior = if ($settingsChoice -like 'Skip*') { 'Skip' } else { 'Restore' }
                $restorePages = $settingsChoice -match 'GitHub Pages'
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
                $step = 6
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

                    $releaseScreen = -1
                    $returnToCommitMessage = $false
                    while ($releaseScreen -le 4) {
                        switch ($releaseScreen) {
                            -1 {
                                Write-CgrWizardMessage
                                Write-CgrWizardMessage -Message 'Snapshot release preservation creates new checkpoint commits from selected release states.' -Style Hint
                                Write-CgrWizardMessage -Message 'It does not preserve original commit identities or ancestry; selected tags are recreated against the new Snapshot checkpoints.' -Style Hint
                                $currentReleaseChoice = if ($snapshotReleaseOptions.IncludeReleases) { 'Preserve selected releases' } else { 'Skip' }
                                $releaseResult = Read-CgrWizardChoice `
                                    -Title 'Snapshot release preservation' `
                                    -Choices @('Skip', 'Preserve selected releases') `
                                    -DefaultValue Skip `
                                    -CurrentValue $currentReleaseChoice `
                                    -AllowBack `
                                    -AllowCancel
                                if ($releaseResult.Action -eq 'Cancel') { return & $cancelResult }
                                if ($releaseResult.Action -eq 'Back') { $returnToCommitMessage = $true; break }
                                $snapshotReleaseOptions.IncludeReleases = $releaseResult.Value -eq 'Preserve selected releases'
                                if (-not $snapshotReleaseOptions.IncludeReleases) { break }
                                $releaseScreen = 0
                            }
                            0 {
                                Write-CgrWizardMessage -Message 'Optional include patterns use the same PowerShell wildcard tag filtering as Copy-GitHubRepository. Separate multiple patterns with commas.' -Style Hint
                                $filterResult = & $readOptionalReleaseValue -Prompt 'Release tag include patterns' -CurrentValue $snapshotReleaseOptions.ReleaseTag
                                if ($filterResult.Action -eq 'Cancel') { return & $cancelResult }
                                if ($filterResult.Action -eq 'Back') { $releaseScreen = -1; continue }
                                $snapshotReleaseOptions.ReleaseTag = [string] $filterResult.Value
                                $releaseScreen = 1
                            }
                            1 {
                                Write-CgrWizardMessage -Message 'Optional exclude patterns are applied after include filtering. Separate multiple patterns with commas.' -Style Hint
                                $filterResult = & $readOptionalReleaseValue -Prompt 'Release tag exclude patterns' -CurrentValue $snapshotReleaseOptions.ReleaseExcludeTag
                                if ($filterResult.Action -eq 'Cancel') { return & $cancelResult }
                                if ($filterResult.Action -eq 'Back') { $releaseScreen = 0; continue }
                                $snapshotReleaseOptions.ReleaseExcludeTag = [string] $filterResult.Value
                                $releaseScreen = 2
                            }
                            2 {
                                $prereleaseChoice = if ($snapshotReleaseOptions.IncludePrerelease) { 'Include prereleases' } else { 'Exclude prereleases' }
                                $filterResult = Read-CgrWizardChoice `
                                    -Title 'Prerelease filtering' `
                                    -Choices @('Exclude prereleases', 'Include prereleases') `
                                    -DefaultValue 'Exclude prereleases' `
                                    -CurrentValue $prereleaseChoice `
                                    -AllowBack `
                                    -AllowCancel
                                if ($filterResult.Action -eq 'Cancel') { return & $cancelResult }
                                if ($filterResult.Action -eq 'Back') { $releaseScreen = 1; continue }
                                $snapshotReleaseOptions.IncludePrerelease = $filterResult.Value -eq 'Include prereleases'
                                $releaseScreen = 3
                            }
                            3 {
                                $draftChoice = if ($snapshotReleaseOptions.IncludeDraftReleases) { 'Include draft releases' } else { 'Exclude draft releases' }
                                $filterResult = Read-CgrWizardChoice `
                                    -Title 'Draft release filtering' `
                                    -Choices @('Exclude draft releases', 'Include draft releases') `
                                    -DefaultValue 'Exclude draft releases' `
                                    -CurrentValue $draftChoice `
                                    -AllowBack `
                                    -AllowCancel
                                if ($filterResult.Action -eq 'Cancel') { return & $cancelResult }
                                if ($filterResult.Action -eq 'Back') { $releaseScreen = 2; continue }
                                $snapshotReleaseOptions.IncludeDraftReleases = $filterResult.Value -eq 'Include draft releases'
                                $releaseScreen = 4
                            }
                            4 {
                                Write-CgrWizardMessage -Message 'Optionally limit the reviewed selection to the newest N releases after the other filters are applied.' -Style Hint
                                $filterResult = & $readOptionalReleaseValue -Prompt 'Release count limit' -CurrentValue $snapshotReleaseOptions.ReleaseCount -PositiveInteger
                                if ($filterResult.Action -eq 'Cancel') { return & $cancelResult }
                                if ($filterResult.Action -eq 'Back') { $releaseScreen = 3; continue }
                                $snapshotReleaseOptions.ReleaseCount = [string] $filterResult.Value
                                $releaseScreen = 5
                            }
                        }
                        if ($returnToCommitMessage -or -not $snapshotReleaseOptions.IncludeReleases) { break }
                    }
                    if ($returnToCommitMessage) { continue }
                }

                $planParameters = @{
                    SourceRepository = $sourceRepository.FullName
                    DestinationRepository = $destinationRepository
                    ContentMode = $contentMode
                    HostName = $HostName
                    PlanOnly = $true
                }
                if ($contentMode -eq 'Snapshot') {
                    $planParameters.CommitMessage = $commitMessage
                    if ($snapshotReleaseOptions.IncludeReleases) {
                        $planParameters.IncludeReleases = $true
                        $releaseTags = @($snapshotReleaseOptions.ReleaseTag -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                        $releaseExcludeTags = @($snapshotReleaseOptions.ReleaseExcludeTag -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                        if ($releaseTags.Count -gt 0) { $planParameters.ReleaseTag = $releaseTags }
                        if ($releaseExcludeTags.Count -gt 0) { $planParameters.ReleaseExcludeTag = $releaseExcludeTags }
                        if ($snapshotReleaseOptions.IncludePrerelease) { $planParameters.IncludePrerelease = $true }
                        if ($snapshotReleaseOptions.IncludeDraftReleases) { $planParameters.IncludeDraftReleases = $true }
                        if (-not [string]::IsNullOrWhiteSpace($snapshotReleaseOptions.ReleaseCount)) {
                            $planParameters.ReleaseCount = [int] $snapshotReleaseOptions.ReleaseCount
                        }
                    }
                }
                if ($destinationVisibility -ne $sourceRepository.Visibility) { $planParameters.DestinationVisibility = $destinationVisibility }
                if ($settingsBehavior -eq 'Skip') { $planParameters.SkipSettings = $true }
                if ($restorePages) { $planParameters.RestorePages = $true }
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
                    if ($plan.IncludeReleases) {
                        Write-CgrWizardMessage -Message '  Snapshot release preservation does not preserve original commit identities or ancestry.' -Status Warning
                        Write-CgrWizardMessage -Message '  Selected release states become newly constructed Snapshot checkpoint commits, and selected tags are recreated against those new commits.' -Style Hint
                        Write-CgrWizardMessage -Message ('  Approved source commit: {0}' -f $plan.SourceState.CommitSha) -Style Hint
                        Write-CgrWizardMessage -Message ('  Commit message: {0}' -f $plan.CommitMessage) -Style Hint

                        $releaseSelection = $plan.ReleaseSelection
                        $checkpointPlan = $plan.ReleaseCheckpointPlan
                        Write-CgrWizardMessage -Message ('  Selected releases: {0} of {1}' -f $releaseSelection.SelectedReleaseCount, $releaseSelection.AvailableReleaseCount) -Style Hint
                        Write-CgrWizardMessage -Message ('  Selected release assets: {0}' -f $releaseSelection.SelectedAssetCount) -Style Hint
                        $includePatterns = if (@($releaseSelection.IncludePatterns).Count -gt 0) { @($releaseSelection.IncludePatterns) -join ', ' } else { '(all tags)' }
                        $excludePatterns = if (@($releaseSelection.ExcludePatterns).Count -gt 0) { @($releaseSelection.ExcludePatterns) -join ', ' } else { '(none)' }
                        $releaseLimit = if ($null -ne $releaseSelection.ReleaseCount) { [string] $releaseSelection.ReleaseCount } else { '(none)' }
                        Write-CgrWizardMessage -Message ('  Include tag filters: {0}' -f $includePatterns) -Style Hint
                        Write-CgrWizardMessage -Message ('  Exclude tag filters: {0}' -f $excludePatterns) -Style Hint
                        Write-CgrWizardMessage -Message ('  Prereleases: {0}' -f $(if ($releaseSelection.IncludePrerelease) { 'included' } else { 'excluded' })) -Style Hint
                        Write-CgrWizardMessage -Message ('  Draft releases: {0}' -f $(if ($releaseSelection.IncludeDraftReleases) { 'included' } else { 'excluded' })) -Style Hint
                        Write-CgrWizardMessage -Message ('  Release count limit: {0}' -f $releaseLimit) -Style Hint
                        Write-CgrWizardMessage -Message ('  Snapshot release checkpoints: {0}' -f $checkpointPlan.CheckpointCount) -Style Hint
                        Write-CgrWizardMessage -Message ('  Planned Snapshot commits: {0}' -f $checkpointPlan.PlannedSnapshotCommitCount) -Style Hint
                        Write-CgrWizardMessage -Message ('  Final current-state checkpoint required: {0}' -f $checkpointPlan.FinalHeadCheckpointRequired) -Style Hint
                        Write-CgrWizardMessage -Message '  Reviewed Snapshot checkpoint plan:' -Style Heading
                        if (@($checkpointPlan.Checkpoints).Count -eq 0) {
                            Write-CgrWizardMessage -Message '    - No release checkpoint commits are selected; the reviewed plan contains only the current Snapshot state.' -Style Hint
                        }
                        else {
                            foreach ($checkpoint in @($checkpointPlan.Checkpoints)) {
                                $tagNames = @($checkpoint.TagNames) -join ', '
                                Write-CgrWizardMessage -Message ('    - {0}. source commit {1}; tree {2}; recreated tags: {3}' -f $checkpoint.Order, $checkpoint.SourceCommitSha, $checkpoint.SourceTreeSha, $tagNames)
                            }
                        }
                    }
                    else {
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
                }
                else {
                    Write-CgrWizardMessage -Message '  FullHistory preserves the approved branches, tags, commits, and reachable Git LFS objects.' -Style Hint
                    Write-CgrWizardMessage -Message ('  Approved refs: {0}; reachable commits: {1}' -f @($plan.SourceState.Refs).Count, $plan.SourceState.ReachableCommitCount) -Style Hint
                }
                Write-CgrWizardMessage -Message ('  Visibility: {0}' -f $plan.DestinationVisibility)
                if (-not [string]::IsNullOrWhiteSpace([string] $plan.ArchiveRepository)) {
                    Write-CgrWizardMessage -Message ('  Archive: {0}' -f $plan.ArchiveRepository) -Style Value
                }

                if (Get-CgrObjectProperty -InputObject $plan -Name 'RestorePages') {
                    Write-CgrWizardMessage -Message '  GitHub Pages restoration:' -Style Heading
                    $pages = Get-CgrObjectProperty -InputObject $plan -Name 'Pages'
                    if ($null -eq $pages) {
                        Write-CgrWizardMessage -Message '    - Reviewed Pages evidence is unavailable; Pages cannot be presented as restorable.' -Status Warning
                    }
                    else {
                        $pagesStatus = [string] (Get-CgrObjectProperty -InputObject $pages -Name 'Status')
                        Write-CgrWizardMessage -Message ('    - Source Pages status: {0}' -f $pagesStatus)
                        if ($pagesStatus -eq 'NotConfigured') {
                            Write-CgrWizardMessage -Message '    - Source Pages is not configured; the approved plan will not create a destination Pages site.' -Style Hint
                        }
                        else {
                            $buildType = [string] (Get-CgrObjectProperty -InputObject $pages -Name 'BuildType')
                            if ($buildType -eq 'workflow') {
                                Write-CgrWizardMessage -Message '    - Build mode: GitHub Actions (workflow-based Pages); no branch/path publishing source is implied.' -Style Hint
                            }
                            elseif (-not [string]::IsNullOrWhiteSpace($buildType)) {
                                Write-CgrWizardMessage -Message ('    - Build mode: {0} (branch/path-based Pages).' -f $buildType) -Style Hint
                                $pagesSource = Get-CgrObjectProperty -InputObject $pages -Name 'Source'
                                if ($null -ne $pagesSource) {
                                    Write-CgrWizardMessage -Message ('    - Publishing source: {0}{1}' -f (Get-CgrObjectProperty -InputObject $pagesSource -Name 'Branch'), (Get-CgrObjectProperty -InputObject $pagesSource -Name 'Path')) -Style Hint
                                }
                            }

                            $representability = Get-CgrObjectProperty -InputObject $pages -Name 'Representability'
                            if ($null -ne $representability -and -not [bool] (Get-CgrObjectProperty -InputObject $representability -Name 'IsRepresentable')) {
                                Write-CgrWizardMessage -Message ('    - Pages is not restorable from this reviewed plan: {0}' -f (Get-CgrObjectProperty -InputObject $representability -Name 'Reason')) -Status Warning
                            }

                            $customDomain = [string] (Get-CgrObjectProperty -InputObject $pages -Name 'CustomDomain')
                            $httpsIntent = Get-CgrObjectProperty -InputObject $pages -Name 'HttpsEnforced'
                            $domainText = if ([string]::IsNullOrWhiteSpace($customDomain)) { '(none)' } else { $customDomain }
                            Write-CgrWizardMessage -Message ('    - Custom domain: {0}' -f $domainText) -Style Hint
                            Write-CgrWizardMessage -Message ('    - HTTPS enforcement intent: {0}' -f $httpsIntent) -Style Hint

                            $externalReadiness = Get-CgrObjectProperty -InputObject $pages -Name 'ExternalReadiness'
                            if ($null -ne $externalReadiness) {
                                $domainVerification = Get-CgrObjectProperty -InputObject $externalReadiness -Name 'DomainVerification'
                                $certificate = Get-CgrObjectProperty -InputObject $externalReadiness -Name 'Certificate'
                                $certificateState = if ($null -eq $certificate) {
                                    'NotReportedByGitHub'
                                }
                                elseif ($certificate -is [string]) {
                                    [string] $certificate
                                }
                                else {
                                    $state = [string] (Get-CgrObjectProperty -InputObject $certificate -Name 'state')
                                    if ([string]::IsNullOrWhiteSpace($state)) { [string] $certificate } else { $state }
                                }
                                $dnsReadiness = Get-CgrObjectProperty -InputObject $externalReadiness -Name 'Dns'
                                Write-CgrWizardMessage -Message ('    - Domain verification readiness: {0}' -f $domainVerification) -Style Hint
                                Write-CgrWizardMessage -Message ('    - Certificate readiness: {0}' -f $certificateState) -Style Hint
                                Write-CgrWizardMessage -Message ('    - DNS evidence: {0}' -f $dnsReadiness) -Style Hint
                            }

                            if (-not [string]::IsNullOrWhiteSpace($customDomain) -or [bool] $httpsIntent) {
                                Write-CgrWizardMessage -Message '    - Custom-domain and HTTPS completion can depend on external DNS, GitHub domain verification, and certificate readiness; the wizard does not discover or mutate external DNS.' -Status Warning
                            }
                            if (-not [string]::IsNullOrWhiteSpace($customDomain) -and $plan.Mode -eq 'SameNameReplacement') {
                                Write-CgrWizardMessage -Message ("    - Same-name replacement must hand off custom-domain ownership for '$customDomain': the archived original may need to release the exact domain before the replacement can claim it. This happens only through the reviewed Pages handoff contract; external DNS is unchanged.") -Status Warning
                            }
                        }
                    }
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

                $restartPlanning = $false
                if ($plan.Mode -eq 'SameNameReplacement') {
                    $expectedConfirmation = "SOURCE=$($plan.SourceRepository);ARCHIVE=$($plan.ArchiveRepository);REPLACEMENT=$($plan.DestinationRepository)"
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
                            if ($navigation.Action -eq 'Back') {
                                $step = 5
                                $restartPlanning = $true
                                break
                            }
                            if ($navigation.Action -eq 'Next') { break }
                        }

                        if ($inputText -ceq $expectedConfirmation) {
                            $sameNameConfirmation = $inputText
                            break
                        }
                        Write-CgrWizardMessage -Message 'The confirmation did not match exactly. Retry, go Back, or Cancel.' -Status Warning
                    }
                }
                if ($restartPlanning) { continue }

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
