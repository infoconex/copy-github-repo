function Set-CgrRepositoryProtectionConfiguration {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'The public Copy-GitHubRepository command performs ShouldProcess before this late-stage restoration boundary.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $SourceRepository,

        [Parameter(Mandatory)]
        [psobject] $DestinationRepository,

        [psobject] $SourceConfiguration,

        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com'
    )

    if ($PSBoundParameters.ContainsKey('SourceConfiguration') -and $null -eq $SourceConfiguration) {
        return [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.RepositoryProtectionRestoreResult'
            Repository = $DestinationRepository.FullName
            Status = 'Unsupported'
            Restored = @()
            Skipped = @('ProtectionPlanning:Invalid')
            IsSuccessful = $true
            IsComplete = $false
        }
    }

    $sourceConfiguration = if ($PSBoundParameters.ContainsKey('SourceConfiguration')) {
        $SourceConfiguration
    }
    else {
        Get-CgrRepositoryProtectionConfiguration `
            -Repository $SourceRepository `
            -HostName $HostName
    }

    $restored = [System.Collections.Generic.List[object]]::new()
    $skipped = [System.Collections.Generic.List[object]]::new()

    foreach ($item in @($sourceConfiguration.Unsupported)) {
        $skipped.Add([pscustomobject] @{
                Kind = $item.Kind
                Name = $item.Name
                Reason = (@($item.Reasons) -join ',')
            })
    }

    foreach ($ruleset in @($sourceConfiguration.Rulesets)) {
        $body = [ordered] @{
            name = $ruleset.Name
            target = $ruleset.Target
            enforcement = $ruleset.Enforcement
            conditions = $ruleset.Conditions
            rules = @($ruleset.Rules)
        }

        $created = Invoke-CgrGitHubApiMutation `
            -Method POST `
            -Path "repos/$($DestinationRepository.FullName)/rulesets" `
            -Body $body `
            -HostName $HostName

        $restored.Add([pscustomobject] @{
                Kind = 'Ruleset'
                Name = $ruleset.Name
                DestinationId = Get-CgrObjectProperty -InputObject $created -Name 'id'
            })
    }

    if ($sourceConfiguration.BranchProtection) {
        $branch = $sourceConfiguration.BranchProtection
        $encodedBranch = [Uri]::EscapeDataString([string] $branch.BranchName)
        $body = [ordered] @{
            required_status_checks = $branch.RequiredStatusChecks
            enforce_admins = [bool] $branch.EnforceAdmins
            required_pull_request_reviews = $branch.RequiredPullRequestReviews
            restrictions = $branch.Restrictions
            required_linear_history = [bool] $branch.RequiredLinearHistory
            allow_force_pushes = [bool] $branch.AllowForcePushes
            allow_deletions = [bool] $branch.AllowDeletions
            block_creations = [bool] $branch.BlockCreations
            required_conversation_resolution = [bool] $branch.RequiredConversationResolution
            lock_branch = [bool] $branch.LockBranch
            allow_fork_syncing = [bool] $branch.AllowForkSyncing
        }

        Invoke-CgrGitHubApiMutation `
            -Method PUT `
            -Path "repos/$($DestinationRepository.FullName)/branches/$encodedBranch/protection" `
            -Body $body `
            -HostName $HostName |
            Out-Null

        if ($branch.RequireSignatures) {
            Invoke-CgrGitHubApiMutation `
                -Method POST `
                -Path "repos/$($DestinationRepository.FullName)/branches/$encodedBranch/protection/required_signatures" `
                -HostName $HostName |
                Out-Null
        }

        $restored.Add([pscustomobject] @{
                Kind = 'BranchProtection'
                Name = $branch.BranchName
                DestinationId = $null
            })
    }

    $verifiedConfiguration = Get-CgrRepositoryProtectionConfiguration `
        -Repository $DestinationRepository `
        -HostName $HostName

    $mismatches = [System.Collections.Generic.List[string]]::new()
    foreach ($sourceRuleset in @($sourceConfiguration.Rulesets)) {
        $destinationRuleset = @($verifiedConfiguration.Rulesets | Where-Object { $_.Name -eq $sourceRuleset.Name })[0]
        if (-not $destinationRuleset) {
            $mismatches.Add("Ruleset '$($sourceRuleset.Name)' is missing from the destination.")
            continue
        }

        foreach ($propertyName in @('Target', 'Enforcement')) {
            if ([string] $destinationRuleset.$propertyName -ne [string] $sourceRuleset.$propertyName) {
                $mismatches.Add("Ruleset '$($sourceRuleset.Name)' property '$propertyName' does not match.")
            }
        }

        $sourceConditions = $sourceRuleset.Conditions | ConvertTo-Json -Depth 100 -Compress
        $destinationConditions = $destinationRuleset.Conditions | ConvertTo-Json -Depth 100 -Compress
        if ($sourceConditions -ne $destinationConditions) {
            $mismatches.Add("Ruleset '$($sourceRuleset.Name)' conditions do not match.")
        }

        $sourceRules = @($sourceRuleset.Rules) | ConvertTo-Json -Depth 100 -Compress
        $destinationRules = @($destinationRuleset.Rules) | ConvertTo-Json -Depth 100 -Compress
        if ($sourceRules -ne $destinationRules) {
            $mismatches.Add("Ruleset '$($sourceRuleset.Name)' rules do not match.")
        }
    }

    if ($sourceConfiguration.BranchProtection) {
        if (-not $verifiedConfiguration.BranchProtection) {
            $mismatches.Add("Branch protection for '$($sourceConfiguration.BranchProtection.BranchName)' is missing from the destination.")
        }
        else {
            $sourceProtectionJson = $sourceConfiguration.BranchProtection | ConvertTo-Json -Depth 100 -Compress
            $destinationProtectionJson = $verifiedConfiguration.BranchProtection | ConvertTo-Json -Depth 100 -Compress
            if ($sourceProtectionJson -ne $destinationProtectionJson) {
                $mismatches.Add("Branch protection for '$($sourceConfiguration.BranchProtection.BranchName)' does not match the source.")
            }
        }
    }

    if ($mismatches.Count -gt 0) {
        $message = "Repository protection verification failed for '$($DestinationRepository.FullName)': $($mismatches -join '; ')"
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'RepositoryProtectionVerificationFailed',
            [System.Management.Automation.ErrorCategory]::InvalidResult,
            $DestinationRepository.FullName
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $status = if ($restored.Count -eq 0 -and $skipped.Count -eq 0) {
        'NotApplicable'
    }
    elseif ($restored.Count -gt 0 -and $skipped.Count -eq 0) {
        'Restored'
    }
    elseif ($restored.Count -gt 0) {
        'Partial'
    }
    else {
        'Unsupported'
    }

    return [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.RepositoryProtectionRestoreResult'
        Repository = $DestinationRepository.FullName
        Status = $status
        Restored = @($restored)
        Skipped = @($skipped)
        IsSuccessful = $true
        IsComplete = @($skipped).Count -eq 0
    }
}
