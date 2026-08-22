#requires -Version 7.4

[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string] $Owner = 'infoconex',

    [switch] $KeepRepositories
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
$runId = [guid]::NewGuid().ToString('N').Substring(0, 10)
$repositoryPrefix = "copy-github-repo-settings-e2e-$runId"
$createdRepositories = [System.Collections.Generic.List[string]]::new()
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) $repositoryPrefix

function Invoke-E2eNativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $FilePath,

        [Parameter(Mandatory)]
        [string[]] $ArgumentList,

        [string] $WorkingDirectory
    )

    $originalLocation = Get-Location
    try {
        if ($WorkingDirectory) {
            Set-Location -LiteralPath $WorkingDirectory
        }

        $output = & $FilePath @ArgumentList 2>&1
        $exitCode = if ($null -ne $global:LASTEXITCODE) { $global:LASTEXITCODE } else { 0 }
        if ($exitCode -ne 0) {
            $message = (@($output) | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
            throw "$FilePath failed with exit code $exitCode. $message"
        }

        return @($output)
    }
    finally {
        Set-Location -LiteralPath $originalLocation
    }
}

function Assert-E2eCleanupCapability {
    [CmdletBinding()]
    param()

    if ($KeepRepositories) {
        return
    }

    $headerOutput = & gh api --include user 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = (@($headerOutput) | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "Unable to verify GitHub cleanup capability before E2E repository creation. $message"
    }

    $scopeLine = @($headerOutput | ForEach-Object { $_.ToString() }) |
        Where-Object { $_ -match '^(?i)x-oauth-scopes:\s*' } |
        Select-Object -First 1

    if (-not $scopeLine) {
        throw 'Unable to prove repository-delete capability from the authenticated GitHub token. No E2E repositories were created. Use -KeepRepositories only when deliberate manual cleanup is acceptable.'
    }

    $scopes = ($scopeLine -replace '^(?i)x-oauth-scopes:\s*', '').Split(',') |
        ForEach-Object { $_.Trim() }
    if ($scopes -notcontains 'delete_repo') {
        throw "The authenticated GitHub token does not advertise the 'delete_repo' scope required for automatic E2E cleanup. No E2E repositories were created. Run 'gh auth refresh --hostname github.com --scopes delete_repo' before retrying, or use -KeepRepositories for deliberate manual cleanup."
    }
}

function Invoke-E2eRepositoryCreation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    if ($Name -notlike "$repositoryPrefix-*") {
        throw "Refusing to create an E2E repository outside the protected prefix '$repositoryPrefix-*'."
    }

    $fullName = "$Owner/$Name"
    Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @('repo', 'create', $fullName, '--private') | Out-Null
    $createdRepositories.Add($fullName)
    return $fullName
}

function Invoke-E2eRepositoryDeletion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Repository
    )

    $expectedPrefix = "$Owner/$repositoryPrefix-"
    if (-not $Repository.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to delete repository '$Repository' because it is outside the protected E2E prefix '$expectedPrefix'."
    }

    $output = & gh repo delete $Repository --yes 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = (@($output) | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "Failed to delete E2E repository '$Repository'. $message"
    }
}

function Publish-E2eSourceRepository {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Repository,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LocalPath
    )

    New-Item -Path $LocalPath -ItemType Directory -Force | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('init', '-b', 'main') -WorkingDirectory $LocalPath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('config', 'user.name', 'Copy GitHub Repo E2E') -WorkingDirectory $LocalPath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('config', 'user.email', 'copy-github-repo-e2e@users.noreply.github.com') -WorkingDirectory $LocalPath | Out-Null
    Set-Content -LiteralPath (Join-Path $LocalPath 'README.md') -Value '# Repository Settings E2E Fixture' -Encoding utf8NoBOM
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('add', 'README.md') -WorkingDirectory $LocalPath | Out-Null
    Invoke-E2eNativeCommand -FilePath 'git' -ArgumentList @('commit', '-m', 'Create repository settings fixture') -WorkingDirectory $LocalPath | Out-Null

    $module = Get-Module CopyGitHubRepo
    if (-not $module) {
        throw 'CopyGitHubRepo module is not loaded.'
    }

    $repositoryUrl = "https://github.com/$Repository.git"
    $pushResult = & $module {
        param($RepositoryUrl, $LocalPath)
        Invoke-CgrGitCommand -HostName 'github.com' -ArgumentList @('-C', $LocalPath, 'push', '-u', $RepositoryUrl, 'main')
    } $repositoryUrl $LocalPath

    if ($pushResult.ExitCode -ne 0) {
        throw "Failed to publish E2E source '$Repository'. $($pushResult.ErrorText)"
    }
}

function Invoke-E2eSourceConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Repository
    )

    Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @(
        'api', '-X', 'PATCH', "repos/$Repository",
        '-f', 'description=Repository settings restoration E2E source',
        '-f', 'homepage=https://example.com/copy-github-repo-settings-e2e',
        '-F', 'has_issues=false',
        '-F', 'has_projects=false',
        '-F', 'has_wiki=false',
        '-F', 'has_discussions=true',
        '-F', 'allow_squash_merge=false',
        '-F', 'allow_merge_commit=false',
        '-F', 'allow_rebase_merge=true',
        '-F', 'allow_auto_merge=false',
        '-F', 'delete_branch_on_merge=true',
        '-F', 'allow_update_branch=true',
        '-F', 'web_commit_signoff_required=true'
    ) | Out-Null

    $topicsPath = Join-Path $tempRoot 'topics.json'
    @{ names = @('copy-github-repo', 'migration-e2e', 'settings') } |
        ConvertTo-Json -Compress |
        Set-Content -LiteralPath $topicsPath -Encoding utf8NoBOM

    Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @(
        'api', '-X', 'PUT', "repos/$Repository/topics", '--input', $topicsPath
    ) | Out-Null
}

function Get-E2eRepositorySetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Repository
    )

    $json = Invoke-E2eNativeCommand -FilePath 'gh' -ArgumentList @('api', "repos/$Repository")
    $data = ($json -join [Environment]::NewLine) | ConvertFrom-Json

    [pscustomobject] @{
        Description = [string] $data.description
        Homepage = [string] $data.homepage
        HasIssues = [bool] $data.has_issues
        HasProjects = [bool] $data.has_projects
        HasWiki = [bool] $data.has_wiki
        HasDiscussions = [bool] $data.has_discussions
        AllowSquashMerge = [bool] $data.allow_squash_merge
        AllowMergeCommit = [bool] $data.allow_merge_commit
        AllowRebaseMerge = [bool] $data.allow_rebase_merge
        AllowAutoMerge = [bool] $data.allow_auto_merge
        DeleteBranchOnMerge = [bool] $data.delete_branch_on_merge
        AllowUpdateBranch = [bool] $data.allow_update_branch
        WebCommitSignoffRequired = [bool] $data.web_commit_signoff_required
        Topics = @($data.topics | ForEach-Object { [string] $_ } | Sort-Object)
    }
}

function Compare-E2eRepositorySetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Source,

        [Parameter(Mandatory)]
        [psobject] $Destination
    )

    $propertyNames = @(
        'Description', 'Homepage', 'HasIssues', 'HasProjects', 'HasWiki', 'HasDiscussions',
        'AllowSquashMerge', 'AllowMergeCommit', 'AllowRebaseMerge', 'AllowAutoMerge',
        'DeleteBranchOnMerge', 'AllowUpdateBranch', 'WebCommitSignoffRequired'
    )

    $mismatches = [System.Collections.Generic.List[string]]::new()
    foreach ($propertyName in $propertyNames) {
        if ($Source.$propertyName -ne $Destination.$propertyName) {
            $mismatches.Add("$propertyName source='$($Source.$propertyName)' destination='$($Destination.$propertyName)'")
        }
    }

    if ((@($Source.Topics) -join "`n") -ne (@($Destination.Topics) -join "`n")) {
        $mismatches.Add("Topics source='$(@($Source.Topics) -join ',')' destination='$(@($Destination.Topics) -join ',')'")
    }

    return @($mismatches)
}

if ($Owner -notmatch '^[A-Za-z0-9_.-]+$') {
    throw "Owner '$Owner' is not valid."
}

Assert-E2eCleanupCapability
Import-Module $modulePath -Force -ErrorAction Stop
New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

$sourceName = "$repositoryPrefix-source"
$destinationName = "$repositoryPrefix-destination"
$sourceRepository = $null
$destinationRepository = "$Owner/$destinationName"

try {
    $sourceRepository = Invoke-E2eRepositoryCreation -Name $sourceName
    $sourcePath = Join-Path $tempRoot 'source'
    Publish-E2eSourceRepository -Repository $sourceRepository -LocalPath $sourcePath
    Invoke-E2eSourceConfiguration -Repository $sourceRepository

    $sourceSettings = Get-E2eRepositorySetting -Repository $sourceRepository

    # Register the destination for guarded cleanup before the migration can create it.
    $createdRepositories.Add($destinationRepository)
    $result = Copy-GitHubRepository `
        -SourceRepository $sourceRepository `
        -DestinationRepository $destinationRepository `
        -NonInteractive `
        -Force

    if (-not $result.IsVerified) {
        throw 'Snapshot content verification did not succeed during repository settings E2E migration.'
    }
    if (-not $result.SettingsRestored) {
        throw 'Migration did not report successful supported-settings restoration.'
    }

    $destinationSettings = Get-E2eRepositorySetting -Repository $destinationRepository
    $mismatches = @(Compare-E2eRepositorySetting -Source $sourceSettings -Destination $destinationSettings)
    if ($mismatches.Count -gt 0) {
        throw "Repository settings were not preserved:`n$($mismatches -join [Environment]::NewLine)"
    }

    [pscustomobject] @{
        Scenario = 'Successful repository settings restoration'
        SourceRepository = $sourceRepository
        DestinationRepository = $destinationRepository
        Verified = $result.IsVerified
        SettingsRestored = $result.SettingsRestored
        DescriptionPreserved = $sourceSettings.Description -eq $destinationSettings.Description
        HomepagePreserved = $sourceSettings.Homepage -eq $destinationSettings.Homepage
        FeatureFlagsPreserved = (
            $sourceSettings.HasIssues -eq $destinationSettings.HasIssues -and
            $sourceSettings.HasProjects -eq $destinationSettings.HasProjects -and
            $sourceSettings.HasWiki -eq $destinationSettings.HasWiki -and
            $sourceSettings.HasDiscussions -eq $destinationSettings.HasDiscussions
        )
        MergePoliciesPreserved = (
            $sourceSettings.AllowSquashMerge -eq $destinationSettings.AllowSquashMerge -and
            $sourceSettings.AllowMergeCommit -eq $destinationSettings.AllowMergeCommit -and
            $sourceSettings.AllowRebaseMerge -eq $destinationSettings.AllowRebaseMerge -and
            $sourceSettings.AllowAutoMerge -eq $destinationSettings.AllowAutoMerge -and
            $sourceSettings.DeleteBranchOnMerge -eq $destinationSettings.DeleteBranchOnMerge -and
            $sourceSettings.AllowUpdateBranch -eq $destinationSettings.AllowUpdateBranch
        )
        WebCommitSignoffPreserved = $sourceSettings.WebCommitSignoffRequired -eq $destinationSettings.WebCommitSignoffRequired
        TopicsPreserved = (@($sourceSettings.Topics) -join "`n") -eq (@($destinationSettings.Topics) -join "`n")
    } | Format-List
}
finally {
    if (-not $KeepRepositories) {
        foreach ($repository in @($createdRepositories) | Select-Object -Unique | Sort-Object -Descending) {
            try {
                $existsOutput = & gh repo view $repository --json nameWithOwner --jq '.nameWithOwner' 2>$null
                if ($LASTEXITCODE -eq 0 -and $existsOutput) {
                    Invoke-E2eRepositoryDeletion -Repository $repository
                }
            }
            catch {
                Write-Warning "Failed to clean up E2E repository '$repository'. $($_.Exception.Message)"
            }
        }
    }
    else {
        Write-Warning "E2E repositories were retained because -KeepRepositories was supplied: $(@($createdRepositories) -join ', ')"
    }

    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
