function Set-CgrGitHubRepositorySetting {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'The public Copy-GitHubRepository command performs the ShouldProcess check before calling this GitHub API boundary.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $SourceRepository,

        [Parameter(Mandatory)]
        [psobject] $DestinationRepository,

        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com'
    )

    $settingDefinitions = @(
        [pscustomobject] @{ Name = 'Description'; ApiName = 'description'; Kind = 'String' }
        [pscustomobject] @{ Name = 'Homepage'; ApiName = 'homepage'; Kind = 'String' }
        [pscustomobject] @{ Name = 'HasIssues'; ApiName = 'has_issues'; Kind = 'Boolean' }
        [pscustomobject] @{ Name = 'HasProjects'; ApiName = 'has_projects'; Kind = 'Boolean' }
        [pscustomobject] @{ Name = 'HasWiki'; ApiName = 'has_wiki'; Kind = 'Boolean' }
        [pscustomobject] @{ Name = 'HasDiscussions'; ApiName = 'has_discussions'; Kind = 'Boolean' }
        [pscustomobject] @{ Name = 'AllowSquashMerge'; ApiName = 'allow_squash_merge'; Kind = 'Boolean' }
        [pscustomobject] @{ Name = 'AllowMergeCommit'; ApiName = 'allow_merge_commit'; Kind = 'Boolean' }
        [pscustomobject] @{ Name = 'AllowRebaseMerge'; ApiName = 'allow_rebase_merge'; Kind = 'Boolean' }
        [pscustomobject] @{ Name = 'AllowAutoMerge'; ApiName = 'allow_auto_merge'; Kind = 'Boolean' }
        [pscustomobject] @{ Name = 'DeleteBranchOnMerge'; ApiName = 'delete_branch_on_merge'; Kind = 'Boolean' }
        [pscustomobject] @{ Name = 'AllowUpdateBranch'; ApiName = 'allow_update_branch'; Kind = 'Boolean' }
        [pscustomobject] @{ Name = 'WebCommitSignoffRequired'; ApiName = 'web_commit_signoff_required'; Kind = 'Boolean' }
    )

    $restored = [System.Collections.Generic.List[object]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()
    $patchArguments = [System.Collections.Generic.List[string]]::new()
    $patchArguments.Add('api')
    $patchArguments.Add('--hostname')
    $patchArguments.Add($HostName)
    $patchArguments.Add('-X')
    $patchArguments.Add('PATCH')
    $patchArguments.Add("repos/$($DestinationRepository.FullName)")

    foreach ($setting in $settingDefinitions) {
        $sourceValue = Get-CgrObjectProperty -InputObject $SourceRepository -Name $setting.Name
        if ($null -eq $sourceValue) {
            $skipped.Add("$($setting.Name):UnavailableFromSource")
            continue
        }

        $destinationValue = Get-CgrObjectProperty -InputObject $DestinationRepository -Name $setting.Name
        $changed = $destinationValue -ne $sourceValue
        if ($changed) {
            if ($setting.Kind -eq 'Boolean') {
                $patchArguments.Add('-F')
                $patchArguments.Add("$($setting.ApiName)=$(([bool] $sourceValue).ToString().ToLowerInvariant())")
            }
            else {
                $patchArguments.Add('-f')
                $patchArguments.Add("$($setting.ApiName)=$([string] $sourceValue)")
            }
        }

        $restored.Add([pscustomobject] @{
                Name = $setting.Name
                Status = 'Restored'
                Value = $sourceValue
                Changed = $changed
            })
    }

    if ($patchArguments.Count -gt 7) {
        $result = Invoke-CgrNativeCommand -FilePath 'gh' -ArgumentList $patchArguments.ToArray()
        if ($result.ExitCode -ne 0) {
            $message = "GitHub CLI failed to restore repository settings for '$($DestinationRepository.FullName)'. $($result.ErrorText)"
            $exception = [System.InvalidOperationException]::new($message.Trim())
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'GitHubRepositorySettingsRestoreFailed',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $DestinationRepository.FullName
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }

    $sourceTopics = Get-CgrObjectProperty -InputObject $SourceRepository -Name 'Topics'
    $destinationTopics = Get-CgrObjectProperty -InputObject $DestinationRepository -Name 'Topics'
    $topicsChanged = $false
    $topicsWereAvailable = $null -ne $sourceTopics
    if ($topicsWereAvailable) {
        $sourceTopicList = @($sourceTopics | ForEach-Object { [string] $_ } | Sort-Object)
        $destinationTopicList = if ($null -eq $destinationTopics) { @() } else { @($destinationTopics | ForEach-Object { [string] $_ } | Sort-Object) }
        $topicsChanged = ($sourceTopicList -join "`n") -ne ($destinationTopicList -join "`n")

        if ($topicsChanged) {
            $topicsInputPath = Join-Path ([System.IO.Path]::GetTempPath()) "copy-github-repo-topics-$([guid]::NewGuid().ToString('N')).json"
            try {
                @{ names = $sourceTopicList } | ConvertTo-Json -Compress | Set-Content -LiteralPath $topicsInputPath -Encoding utf8NoBOM | Out-Null
                $topicsResult = Invoke-CgrNativeCommand -FilePath 'gh' -ArgumentList @('api', '--hostname', $HostName, '-X', 'PUT', "repos/$($DestinationRepository.FullName)/topics", '--input', $topicsInputPath)
                if ($topicsResult.ExitCode -ne 0) {
                    $message = "GitHub CLI failed to restore repository topics for '$($DestinationRepository.FullName)'. $($topicsResult.ErrorText)"
                    $exception = [System.InvalidOperationException]::new($message.Trim())
                    $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'GitHubRepositoryTopicsRestoreFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $DestinationRepository.FullName)
                    $PSCmdlet.ThrowTerminatingError($errorRecord)
                }
            }
            finally { Remove-Item -LiteralPath $topicsInputPath -Force -ErrorAction SilentlyContinue }
        }

        $restored.Add([pscustomobject] @{ Name = 'Topics'; Status = 'Restored'; Value = $sourceTopicList; Changed = $topicsChanged })
    }
    else { $skipped.Add('Topics:UnavailableFromSource') }

    $verifiedDestination = Get-CgrRepository -Repository $DestinationRepository.FullName -HostName $HostName
    $mismatches = [System.Collections.Generic.List[string]]::new()
    foreach ($setting in $settingDefinitions) {
        $sourceValue = Get-CgrObjectProperty -InputObject $SourceRepository -Name $setting.Name
        if ($null -eq $sourceValue) { continue }
        $actualValue = Get-CgrObjectProperty -InputObject $verifiedDestination -Name $setting.Name
        if ($actualValue -ne $sourceValue) { $mismatches.Add("$($setting.Name): expected '$sourceValue' but found '$actualValue'") }
    }

    if ($topicsWereAvailable) {
        $actualTopics = Get-CgrObjectProperty -InputObject $verifiedDestination -Name 'Topics'
        $actualTopicList = if ($null -eq $actualTopics) { @() } else { @($actualTopics | ForEach-Object { [string] $_ } | Sort-Object) }
        if (($sourceTopicList -join "`n") -ne ($actualTopicList -join "`n")) {
            $mismatches.Add("Topics: expected '$($sourceTopicList -join ',')' but found '$($actualTopicList -join ',')'")
        }
    }

    if ($mismatches.Count -gt 0) {
        $message = "GitHub repository settings verification failed for '$($DestinationRepository.FullName)': $($mismatches -join '; ')"
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'GitHubRepositorySettingsVerificationFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $DestinationRepository.FullName)
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    return [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.SettingsRestoreResult'
        Repository = $DestinationRepository.FullName
        Restored = @($restored)
        Skipped = @($skipped)
        Unsupported = @(
            'GitHubPages'
            'GitHubActionsActivation'
            'Secrets'
            'Webhooks'
            'DeployKeys'
            'Environments'
            'CollaboratorsAndTeams'
        )
        IsSuccessful = $true
    }
}
