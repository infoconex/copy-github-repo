function Get-CgrRepositoryProtectionConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Repository,

        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com'
    )

    $supportedRulesets = [System.Collections.Generic.List[object]]::new()
    $unsupported = [System.Collections.Generic.List[object]]::new()

    $rulesetSummaries = @(Get-CgrGitHubApi `
            -Path "repos/$($Repository.FullName)/rulesets?includes_parents=false" `
            -HostName $HostName)

    foreach ($summary in $rulesetSummaries) {
        if ([string] $summary.source_type -ne 'Repository') {
            continue
        }

        $ruleset = Get-CgrGitHubApi `
            -Path "repos/$($Repository.FullName)/rulesets/$($summary.id)?includes_parents=false" `
            -HostName $HostName

        $reasons = [System.Collections.Generic.List[string]]::new()
        if (@($ruleset.bypass_actors).Count -gt 0) {
            $reasons.Add('BypassActorsAreIdentityBound')
        }

        foreach ($rule in @($ruleset.rules)) {
            if ([string] $rule.type -eq 'required_deployments') {
                $reasons.Add('RequiredDeploymentsDependOnDestinationEnvironments')
            }

            if ([string] $rule.type -eq 'required_status_checks') {
                foreach ($check in @($rule.parameters.required_status_checks)) {
                    $integrationId = Get-CgrObjectProperty -InputObject $check -Name 'integration_id'
                    if ($null -ne $integrationId) {
                        $reasons.Add('RequiredStatusCheckIntegrationIsIdentityBound')
                        break
                    }
                }
            }
        }

        if ($reasons.Count -gt 0) {
            $unsupported.Add([pscustomobject] @{
                    Kind = 'Ruleset'
                    Name = [string] $ruleset.name
                    Reasons = @($reasons | Select-Object -Unique)
                })
            continue
        }

        $supportedRulesets.Add([pscustomobject] @{
                Name = [string] $ruleset.name
                Target = [string] $ruleset.target
                Enforcement = [string] $ruleset.enforcement
                Conditions = $ruleset.conditions
                Rules = @($ruleset.rules)
            })
    }

    $branchProtection = $null
    if (-not [string]::IsNullOrWhiteSpace([string] $Repository.DefaultBranch)) {
        $encodedBranch = [Uri]::EscapeDataString([string] $Repository.DefaultBranch)
        $rawProtection = Get-CgrGitHubApiOptional `
            -Path "repos/$($Repository.FullName)/branches/$encodedBranch/protection" `
            -HostName $HostName

        if ($rawProtection) {
            $branchReasons = [System.Collections.Generic.List[string]]::new()
            foreach ($collectionName in @('users', 'teams', 'apps')) {
                if ($rawProtection.restrictions -and @($rawProtection.restrictions.$collectionName).Count -gt 0) {
                    $branchReasons.Add('PushRestrictionsAreIdentityBound')
                    break
                }
            }

            if ($rawProtection.required_pull_request_reviews -and $rawProtection.required_pull_request_reviews.dismissal_restrictions) {
                foreach ($collectionName in @('users', 'teams', 'apps')) {
                    if (@($rawProtection.required_pull_request_reviews.dismissal_restrictions.$collectionName).Count -gt 0) {
                        $branchReasons.Add('DismissalRestrictionsAreIdentityBound')
                        break
                    }
                }
            }

            if ($rawProtection.required_status_checks) {
                foreach ($check in @($rawProtection.required_status_checks.checks)) {
                    $appId = Get-CgrObjectProperty -InputObject $check -Name 'app_id'
                    if ($null -ne $appId) {
                        $branchReasons.Add('RequiredStatusCheckAppIsIdentityBound')
                        break
                    }
                }
            }

            if ($branchReasons.Count -gt 0) {
                $unsupported.Add([pscustomobject] @{
                        Kind = 'BranchProtection'
                        Name = [string] $Repository.DefaultBranch
                        Reasons = @($branchReasons | Select-Object -Unique)
                    })
            }
            else {
                $requiredStatusChecks = if ($rawProtection.required_status_checks) {
                    [pscustomobject] @{
                        strict = [bool] $rawProtection.required_status_checks.strict
                        contexts = @($rawProtection.required_status_checks.contexts | ForEach-Object { [string] $_ })
                    }
                }
                else {
                    $null
                }

                $requiredPullRequestReviews = if ($rawProtection.required_pull_request_reviews) {
                    [pscustomobject] @{
                        dismissal_restrictions = [pscustomobject] @{ users = @(); teams = @(); apps = @() }
                        dismiss_stale_reviews = [bool] $rawProtection.required_pull_request_reviews.dismiss_stale_reviews
                        require_code_owner_reviews = [bool] $rawProtection.required_pull_request_reviews.require_code_owner_reviews
                        required_approving_review_count = [int] $rawProtection.required_pull_request_reviews.required_approving_review_count
                        require_last_push_approval = [bool] (Get-CgrObjectProperty -InputObject $rawProtection.required_pull_request_reviews -Name 'require_last_push_approval')
                    }
                }
                else {
                    $null
                }

                $branchProtection = [pscustomobject] @{
                    BranchName = [string] $Repository.DefaultBranch
                    RequiredStatusChecks = $requiredStatusChecks
                    EnforceAdmins = [bool] $rawProtection.enforce_admins.enabled
                    RequiredPullRequestReviews = $requiredPullRequestReviews
                    Restrictions = $null
                    RequiredLinearHistory = [bool] $rawProtection.required_linear_history.enabled
                    AllowForcePushes = [bool] $rawProtection.allow_force_pushes.enabled
                    AllowDeletions = [bool] $rawProtection.allow_deletions.enabled
                    BlockCreations = [bool] $rawProtection.block_creations.enabled
                    RequiredConversationResolution = [bool] $rawProtection.required_conversation_resolution.enabled
                    LockBranch = [bool] $rawProtection.lock_branch.enabled
                    AllowForkSyncing = [bool] $rawProtection.allow_fork_syncing.enabled
                    RequireSignatures = [bool] $rawProtection.required_signatures.enabled
                }
            }
        }
    }

    return [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.RepositoryProtectionConfiguration'
        Repository = $Repository.FullName
        Rulesets = @($supportedRulesets)
        BranchProtection = $branchProtection
        Unsupported = @($unsupported)
    }
}
