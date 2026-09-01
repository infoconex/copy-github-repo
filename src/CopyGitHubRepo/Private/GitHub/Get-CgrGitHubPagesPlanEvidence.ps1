function Get-CgrGitHubPagesPlanEvidence {
    <#
    .SYNOPSIS
    Captures immutable GitHub Pages evidence for migration planning.

    .DESCRIPTION
    Reads source GitHub-side Pages configuration only when Pages restoration was
    requested. The returned object separates transferable configuration from
    external/asynchronous readiness evidence and records whether the exact reviewed
    configuration is representable under the selected Git-content mode.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Repository,

        [Parameter(Mandatory)]
        [ValidateSet('Snapshot', 'FullHistory')]
        [string] $ContentMode,

        [Parameter(Mandatory)]
        [psobject] $SourceState,

        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com'
    )

    $result = Invoke-CgrGitHubApiReadRequest `
        -ArgumentList @('api', '--hostname', $HostName, "repos/$($Repository.FullName)/pages")

    if ($result.ExitCode -ne 0) {
        if ([string] $result.ErrorText -match '(?i)404|not found') {
            return [pscustomobject] @{
                PSTypeName = 'CopyGitHubRepo.GitHubPagesPlanEvidence'
                SchemaVersion = 1
                Status = 'NotConfigured'
                Configured = $false
                BuildType = $null
                Source = $null
                CustomDomain = $null
                HttpsEnforced = $null
                Representability = [pscustomobject] @{
                    Status = 'NotApplicable'
                    IsRepresentable = $true
                    Reason = 'Source Pages is not configured.'
                }
                ExternalReadiness = [pscustomobject] @{
                    DomainVerification = 'NotApplicable'
                    Certificate = 'NotApplicable'
                    Dns = 'ExternalNotQueried'
                }
                DriftEvidence = [pscustomobject] @{
                    Configured = $false
                    BuildType = $null
                    Branch = $null
                    Path = $null
                    CustomDomain = $null
                    HttpsEnforced = $null
                }
                CapturedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
            }
        }

        $diagnostic = Protect-CgrDiagnosticText -Text ([string] $result.ErrorText)
        $message = "GitHub CLI failed to read Pages configuration for '$($Repository.FullName)'. $diagnostic"
        $exception = [System.InvalidOperationException]::new($message.Trim())
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'SourceGitHubPagesReadFailed',
            [System.Management.Automation.ErrorCategory]::ReadError,
            $Repository.FullName
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $json = ($result.Output | ForEach-Object { [string] $_ }) -join "`n"
    if ([string]::IsNullOrWhiteSpace($json)) {
        $exception = [System.InvalidOperationException]::new("GitHub returned an empty Pages response for '$($Repository.FullName)'.")
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'SourceGitHubPagesResponseEmpty',
            [System.Management.Automation.ErrorCategory]::InvalidData,
            $Repository.FullName
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $pages = $json | ConvertFrom-Json -Depth 100
    $buildType = [string] (Get-CgrObjectProperty -InputObject $pages -Name 'build_type')
    $sourceObject = Get-CgrObjectProperty -InputObject $pages -Name 'source'
    $branch = if ($sourceObject) { [string] (Get-CgrObjectProperty -InputObject $sourceObject -Name 'branch') } else { $null }
    $path = if ($sourceObject) { [string] (Get-CgrObjectProperty -InputObject $sourceObject -Name 'path') } else { $null }
    $customDomain = Get-CgrObjectProperty -InputObject $pages -Name 'cname'
    $httpsEnforced = Get-CgrObjectProperty -InputObject $pages -Name 'https_enforced'
    $protectedDomainState = Get-CgrObjectProperty -InputObject $pages -Name 'protected_domain_state'
    $pendingDomainUnverifiedAt = Get-CgrObjectProperty -InputObject $pages -Name 'pending_domain_unverified_at'
    $httpsCertificate = Get-CgrObjectProperty -InputObject $pages -Name 'https_certificate'

    $representable = $true
    $representabilityStatus = 'Supported'
    $representabilityReason = 'The reviewed Pages configuration is representable under the selected content mode.'

    switch ($buildType) {
        'workflow' { }
        'legacy' {
            if ([string]::IsNullOrWhiteSpace($branch) -or $path -notin @('/', '/docs')) {
                $representable = $false
                $representabilityStatus = 'Unsupported'
                $representabilityReason = 'Branch/path Pages requires an exact publishing branch and a supported source path of / or /docs.'
                break
            }

            $branchAvailable = if ($ContentMode -eq 'Snapshot') {
                $branch -eq [string] (Get-CgrObjectProperty -InputObject $SourceState -Name 'DefaultBranch')
            }
            else {
                $approvedRefs = @(Get-CgrObjectProperty -InputObject $SourceState -Name 'Refs')
                @($approvedRefs | Where-Object { [string] $_ -match "^refs/heads/$([regex]::Escape($branch))(?:\s|$)" }).Count -gt 0
            }

            if (-not $branchAvailable) {
                $representable = $false
                $representabilityStatus = 'Unrepresentable'
                $representabilityReason = "Reviewed Pages publishing branch '$branch' is not preserved by the selected $ContentMode content plan."
            }
        }
        default {
            $representable = $false
            $representabilityStatus = 'Unsupported'
            $representabilityReason = "GitHub Pages build type '$buildType' is not supported by the migration contract."
        }
    }

    [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.GitHubPagesPlanEvidence'
        SchemaVersion = 1
        Status = if ($representable) { 'Configured' } else { $representabilityStatus }
        Configured = $true
        BuildType = $buildType
        Source = if ($buildType -eq 'legacy') {
            [pscustomobject] @{
                Branch = $branch
                Path = $path
            }
        }
        else { $null }
        CustomDomain = if ([string]::IsNullOrWhiteSpace([string] $customDomain)) { $null } else { [string] $customDomain }
        HttpsEnforced = if ($null -eq $httpsEnforced) { $null } else { [bool] $httpsEnforced }
        Representability = [pscustomobject] @{
            Status = $representabilityStatus
            IsRepresentable = $representable
            Reason = $representabilityReason
        }
        ExternalReadiness = [pscustomobject] @{
            DomainVerification = if ($null -ne $protectedDomainState) { [string] $protectedDomainState } elseif ($null -ne $pendingDomainUnverifiedAt) { 'Pending' } else { 'NotReportedByGitHub' }
            PendingDomainUnverifiedAt = $pendingDomainUnverifiedAt
            Certificate = if ($null -ne $httpsCertificate) { $httpsCertificate } else { 'NotReportedByGitHub' }
            Dns = 'ExternalNotQueried'
        }
        DriftEvidence = [pscustomobject] @{
            Configured = $true
            BuildType = $buildType
            Branch = $branch
            Path = $path
            CustomDomain = if ([string]::IsNullOrWhiteSpace([string] $customDomain)) { $null } else { [string] $customDomain }
            HttpsEnforced = if ($null -eq $httpsEnforced) { $null } else { [bool] $httpsEnforced }
        }
        CapturedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    }
}
