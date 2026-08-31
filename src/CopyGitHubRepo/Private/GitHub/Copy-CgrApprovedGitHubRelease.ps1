function Copy-CgrApprovedGitHubRelease {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'The public Copy-GitHubRepository command performs the ShouldProcess check before calling this approved GitHub release migration boundary.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $SourceRepository,

        [Parameter(Mandatory)]
        [psobject] $DestinationRepository,

        [Parameter(Mandatory)]
        [psobject] $ApprovedSelection,

        [psobject[]] $DestinationTagTargets,

        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com'
    )

    $approvedReleases = @($ApprovedSelection.Releases)
    if ($approvedReleases.Count -eq 0) {
        return [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.ReleaseMigrationResult'
            SourceRepository = $SourceRepository.FullName
            DestinationRepository = $DestinationRepository.FullName
            ApprovedReleaseCount = 0
            DestinationReleaseCount = 0
            Releases = @()
            Unsupported = @('OriginalReleaseId', 'OriginalCreatedAt', 'OriginalPublishedAt', 'ReleaseDownloadCounts', 'ReleaseImmutability', 'LinkedDiscussion')
            IsSuccessful = $true
        }
    }

    $expectedDestinationTagTargets = @{}
    if ($PSBoundParameters.ContainsKey('DestinationTagTargets')) {
        foreach ($target in @($DestinationTagTargets)) {
            $targetTagName = [string] (Get-CgrObjectProperty -InputObject $target -Name 'TagName')
            $targetCommitSha = [string] (Get-CgrObjectProperty -InputObject $target -Name 'DestinationCommitSha')
            if ([string]::IsNullOrWhiteSpace($targetTagName) -or
                [string]::IsNullOrWhiteSpace($targetCommitSha) -or
                $expectedDestinationTagTargets.ContainsKey($targetTagName)) {
                $message = 'Approved destination release-tag target evidence is incomplete or ambiguous. Recreate and review the migration plan before execution.'
                $exception = [System.InvalidOperationException]::new($message)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'ApprovedDestinationReleaseTagTargetsInvalid',
                    [System.Management.Automation.ErrorCategory]::InvalidData,
                    $targetTagName
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
            $expectedDestinationTagTargets[$targetTagName] = $targetCommitSha
        }

        $approvedTagNames = @($approvedReleases | ForEach-Object { [string] $_.TagName })
        if ($expectedDestinationTagTargets.Count -ne $approvedTagNames.Count -or
            @($approvedTagNames | Where-Object { -not $expectedDestinationTagTargets.ContainsKey($_) }).Count -gt 0) {
            $message = 'Approved destination release-tag target evidence does not match the exact reviewed release selection. Release restoration was not attempted.'
            $exception = [System.InvalidOperationException]::new($message)
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'ApprovedDestinationReleaseTagTargetsMismatch',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $DestinationRepository.FullName
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }

    $approvedLatestIncluded = @($approvedReleases | Where-Object { [bool] $_.IsLatest }).Count -gt 0
    $approvedLatestTag = if ($approvedLatestIncluded) {
        [string] (@($approvedReleases | Where-Object { [bool] $_.IsLatest }) | Select-Object -First 1).TagName
    }
    else {
        $null
    }

    $workspacePath = Join-Path ([System.IO.Path]::GetTempPath()) "copy-github-repo-approved-releases-$([guid]::NewGuid().ToString('N'))"
    $migrated = [System.Collections.Generic.List[object]]::new()

    try {
        New-Item -Path $workspacePath -ItemType Directory -Force | Out-Null

        foreach ($approved in $approvedReleases) {
            $tagName = [string] $approved.TagName
            $escapedTag = [uri]::EscapeDataString($tagName)

            $sourceReleaseResult = Invoke-CgrGitHubApiReadRequest -ArgumentList @(
                'api', '--hostname', $HostName,
                "repos/$($SourceRepository.FullName)/releases/tags/$escapedTag"
            )
            if ($sourceReleaseResult.ExitCode -ne 0) {
                $diagnostic = Protect-CgrDiagnosticText -Text ([string] $sourceReleaseResult.ErrorText)
                $message = "Approved source release '$tagName' is no longer available. Recreate and review the migration plan before execution. $diagnostic"
                $exception = [System.InvalidOperationException]::new($message.Trim())
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'SourceReleaseStateChangedSincePlanning',
                    [System.Management.Automation.ErrorCategory]::InvalidData,
                    $tagName
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            $sourceReleaseJson = ($sourceReleaseResult.Output | ForEach-Object { [string] $_ }) -join "`n"
            $sourceRelease = $sourceReleaseJson | ConvertFrom-Json -Depth 100
            $sourceCommitResult = Invoke-CgrGitHubApiReadRequest -ArgumentList @(
                'api', '--hostname', $HostName,
                "repos/$($SourceRepository.FullName)/commits/$escapedTag", '--jq', '.sha'
            )
            $destinationCommitResult = Invoke-CgrGitHubApiReadRequest -ArgumentList @(
                'api', '--hostname', $HostName,
                "repos/$($DestinationRepository.FullName)/commits/$escapedTag", '--jq', '.sha'
            )
            if ($sourceCommitResult.ExitCode -ne 0 -or $destinationCommitResult.ExitCode -ne 0) {
                $message = "Approved release tag '$tagName' must resolve in both source and destination before release restoration."
                $exception = [System.InvalidOperationException]::new($message)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'GitHubReleaseTagResolutionFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $tagName)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            $sourceCommitSha = [string] @($sourceCommitResult.Output)[0]
            $destinationCommitSha = [string] @($destinationCommitResult.Output)[0]
            $currentAssets = @($sourceRelease.assets | ForEach-Object {
                    [pscustomobject] @{
                        Id = $_.id
                        Name = [string] $_.name
                        Label = [string] $_.label
                        Size = [long] $_.size
                        ContentType = [string] $_.content_type
                        Digest = [string] $_.digest
                    }
                })

            $stateChanged = [long] $sourceRelease.id -ne [long] $approved.ReleaseId -or
            [string] $sourceRelease.tag_name -ne $tagName -or
            [string] $sourceRelease.name -ne [string] $approved.Name -or
            [string] $sourceRelease.body -ne [string] $approved.Body -or
            [bool] $sourceRelease.draft -ne [bool] $approved.Draft -or
            [bool] $sourceRelease.prerelease -ne [bool] $approved.Prerelease -or
            $sourceCommitSha -ne [string] $approved.TargetCommitSha -or
            $currentAssets.Count -ne @($approved.Assets).Count

            if (-not $stateChanged) {
                foreach ($approvedAsset in @($approved.Assets)) {
                    $currentAsset = @($currentAssets | Where-Object { $_.Name -eq [string] $approvedAsset.Name }) | Select-Object -First 1
                    if ($null -eq $currentAsset -or
                        $currentAsset.Size -ne [long] $approvedAsset.Size -or
                        $currentAsset.Label -ne [string] $approvedAsset.Label -or
                        $currentAsset.ContentType -ne [string] $approvedAsset.ContentType -or
                        (-not [string]::IsNullOrWhiteSpace([string] $approvedAsset.Digest) -and $currentAsset.Digest -ne [string] $approvedAsset.Digest)) {
                        $stateChanged = $true
                        break
                    }
                }
            }

            if ($stateChanged) {
                $message = "Approved source release '$tagName' changed after planning. Recreate and review the migration plan before execution."
                $exception = [System.InvalidOperationException]::new($message)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'SourceReleaseStateChangedSincePlanning',
                    [System.Management.Automation.ErrorCategory]::InvalidData,
                    $tagName
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            $expectedDestinationCommitSha = if ($expectedDestinationTagTargets.Count -gt 0) {
                [string] $expectedDestinationTagTargets[$tagName]
            }
            else {
                [string] $approved.TargetCommitSha
            }
            if ($destinationCommitSha -ne $expectedDestinationCommitSha) {
                $message = "Destination release tag '$tagName' resolves to '$destinationCommitSha' instead of approved destination commit '$expectedDestinationCommitSha'."
                $exception = [System.InvalidOperationException]::new($message)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'GitHubReleaseTagTargetMismatch', [System.Management.Automation.ErrorCategory]::InvalidResult, $tagName)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            $existingReleaseResult = Invoke-CgrGitHubApiReadRequest -ArgumentList @(
                'api', '--hostname', $HostName,
                "repos/$($DestinationRepository.FullName)/releases/tags/$escapedTag"
            )
            if ($existingReleaseResult.ExitCode -eq 0) {
                $message = "Destination '$($DestinationRepository.FullName)' already contains a GitHub Release for tag '$tagName'. The tool will not overwrite it."
                $exception = [System.InvalidOperationException]::new($message)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationGitHubReleaseAlreadyExists', [System.Management.Automation.ErrorCategory]::ResourceExists, $tagName)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
            if ([string] $existingReleaseResult.ErrorText -notmatch '(?i)404|not found') {
                $diagnostic = Protect-CgrDiagnosticText -Text ([string] $existingReleaseResult.ErrorText)
                $message = "Unable to determine whether destination '$($DestinationRepository.FullName)' already contains a GitHub Release for tag '$tagName'. Release creation was not attempted. $diagnostic"
                $exception = [System.InvalidOperationException]::new($message.Trim())
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationGitHubReleaseReadFailed', [System.Management.Automation.ErrorCategory]::ReadError, $tagName)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            $releasePath = Join-Path $workspacePath ([Convert]::ToHexString([System.Text.Encoding]::UTF8.GetBytes($tagName)))
            $assetPath = Join-Path $releasePath 'assets'
            $notesPath = Join-Path $releasePath 'release-notes.md'
            New-Item -Path $assetPath -ItemType Directory -Force | Out-Null
            [System.IO.File]::WriteAllText($notesPath, [string] $approved.Body, [System.Text.UTF8Encoding]::new($false))

            if (@($approved.Assets).Count -gt 0) {
                $downloadResult = Invoke-CgrNativeCommand -FilePath 'gh' -ArgumentList @('release', 'download', $tagName, '--repo', $SourceRepository.FullName, '--dir', $assetPath)
                if ($downloadResult.ExitCode -ne 0) {
                    $diagnostic = Protect-CgrDiagnosticText -Text ([string] $downloadResult.ErrorText)
                    $message = "GitHub CLI failed to download approved assets for release '$tagName'. $diagnostic"
                    $exception = [System.InvalidOperationException]::new($message.Trim())
                    $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'SourceGitHubReleaseAssetDownloadFailed', [System.Management.Automation.ErrorCategory]::ReadError, $tagName)
                    $PSCmdlet.ThrowTerminatingError($errorRecord)
                }
            }

            $createArguments = [System.Collections.Generic.List[string]]::new()
            foreach ($argument in @('release', 'create', $tagName, '--repo', $DestinationRepository.FullName, '--verify-tag', '--notes-file', $notesPath)) { $createArguments.Add($argument) }
            if (-not [string]::IsNullOrWhiteSpace([string] $approved.Name)) { $createArguments.Add('--title'); $createArguments.Add([string] $approved.Name) }
            if ([bool] $approved.Draft) { $createArguments.Add('--draft') }
            if ([bool] $approved.Prerelease) { $createArguments.Add('--prerelease') }
            if (-not [bool] $approved.Draft -and -not [bool] $approved.Prerelease -and $approvedLatestIncluded) {
                if ([bool] $approved.IsLatest) {
                    $createArguments.Add('--latest')
                }
                else {
                    $createArguments.Add('--latest=false')
                }
            }

            $createResult = Invoke-CgrNativeCommand -FilePath 'gh' -ArgumentList $createArguments.ToArray()
            if ($createResult.ExitCode -ne 0) {
                $diagnostic = Protect-CgrDiagnosticText -Text ([string] $createResult.ErrorText)
                $message = "GitHub CLI failed to create destination release '$tagName'. $diagnostic"
                $exception = [System.InvalidOperationException]::new($message.Trim())
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationGitHubReleaseCreateFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $tagName)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            if (@($approved.Assets).Count -gt 0) {
                $uploadArguments = [System.Collections.Generic.List[string]]::new()
                foreach ($argument in @('release', 'upload', $tagName, '--repo', $DestinationRepository.FullName)) { $uploadArguments.Add($argument) }
                foreach ($asset in @($approved.Assets)) {
                    $assetFilePath = Join-Path $assetPath ([string] $asset.Name)
                    if (-not (Test-Path -LiteralPath $assetFilePath -PathType Leaf)) {
                        $message = "Downloaded release asset '$($asset.Name)' was not found at the expected workspace path."
                        $exception = [System.IO.FileNotFoundException]::new($message, $assetFilePath)
                        $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'SourceGitHubReleaseAssetMissingAfterDownload', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $assetFilePath)
                        $PSCmdlet.ThrowTerminatingError($errorRecord)
                    }
                    $uploadArguments.Add($(if ([string]::IsNullOrWhiteSpace([string] $asset.Label)) { $assetFilePath } else { "$assetFilePath#$($asset.Label)" }))
                }
                $uploadResult = Invoke-CgrNativeCommand -FilePath 'gh' -ArgumentList $uploadArguments.ToArray()
                if ($uploadResult.ExitCode -ne 0) {
                    $diagnostic = Protect-CgrDiagnosticText -Text ([string] $uploadResult.ErrorText)
                    $message = "GitHub CLI failed to upload assets for destination release '$tagName'. $diagnostic"
                    $exception = [System.InvalidOperationException]::new($message.Trim())
                    $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationGitHubReleaseAssetUploadFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $tagName)
                    $PSCmdlet.ThrowTerminatingError($errorRecord)
                }
            }

            $destinationReleaseResult = Invoke-CgrGitHubApiReadRequest -ArgumentList @('api', '--hostname', $HostName, "repos/$($DestinationRepository.FullName)/releases/tags/$escapedTag")
            if ($destinationReleaseResult.ExitCode -ne 0) {
                $diagnostic = Protect-CgrDiagnosticText -Text ([string] $destinationReleaseResult.ErrorText)
                $message = "Unable to reload destination release '$tagName' for verification. $diagnostic"
                $exception = [System.InvalidOperationException]::new($message.Trim())
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationGitHubReleaseVerificationReadFailed', [System.Management.Automation.ErrorCategory]::ReadError, $tagName)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
            $destinationReleaseJson = ($destinationReleaseResult.Output | ForEach-Object { [string] $_ }) -join "`n"
            $destinationRelease = $destinationReleaseJson | ConvertFrom-Json -Depth 100
            $destinationAssets = @($destinationRelease.assets)
            $mismatches = [System.Collections.Generic.List[string]]::new()
            if ([string] $destinationRelease.tag_name -ne $tagName) { $mismatches.Add('TagName') }
            if ([string] $destinationRelease.name -ne [string] $approved.Name) { $mismatches.Add('Name') }
            if ([string] $destinationRelease.body -ne [string] $approved.Body) { $mismatches.Add('Body') }
            if ([bool] $destinationRelease.draft -ne [bool] $approved.Draft) { $mismatches.Add('Draft') }
            if ([bool] $destinationRelease.prerelease -ne [bool] $approved.Prerelease) { $mismatches.Add('Prerelease') }
            if ($destinationAssets.Count -ne @($approved.Assets).Count) { $mismatches.Add('AssetCount') }
            foreach ($asset in @($approved.Assets)) {
                $actual = @($destinationAssets | Where-Object { [string] $_.name -eq [string] $asset.Name }) | Select-Object -First 1
                if ($null -eq $actual) { $mismatches.Add("AssetMissing:$($asset.Name)"); continue }
                if ([long] $actual.size -ne [long] $asset.Size) { $mismatches.Add("AssetSize:$($asset.Name)") }
                if ([string] $actual.label -ne [string] $asset.Label) { $mismatches.Add("AssetLabel:$($asset.Name)") }
                if ([string] $actual.content_type -ne [string] $asset.ContentType) { $mismatches.Add("AssetContentType:$($asset.Name)") }
                if (-not [string]::IsNullOrWhiteSpace([string] $asset.Digest) -and [string] $actual.digest -ne [string] $asset.Digest) { $mismatches.Add("AssetDigest:$($asset.Name)") }
            }
            if ($mismatches.Count -gt 0) {
                $message = "Destination GitHub Release verification failed for '$tagName': $($mismatches -join ', ')."
                $exception = [System.InvalidOperationException]::new($message)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationGitHubReleaseVerificationFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $tagName)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            $migrated.Add([pscustomobject] @{
                    TagName = $tagName
                    SourceReleaseId = $approved.ReleaseId
                    DestinationReleaseId = $destinationRelease.id
                    SourceCommitSha = $sourceCommitSha
                    DestinationCommitSha = $destinationCommitSha
                    IsLatest = [bool] $approved.IsLatest
                    AssetCount = @($approved.Assets).Count
                    IsVerified = $true
                })
        }

        if ($approvedLatestIncluded) {
            $destinationLatestResult = Invoke-CgrGitHubApiReadRequest -ArgumentList @(
                'api', '--hostname', $HostName,
                "repos/$($DestinationRepository.FullName)/releases/latest"
            )
            if ($destinationLatestResult.ExitCode -ne 0) {
                $diagnostic = Protect-CgrDiagnosticText -Text ([string] $destinationLatestResult.ErrorText)
                $message = "Unable to verify destination latest-release designation for approved release '$approvedLatestTag'. $diagnostic"
                $exception = [System.InvalidOperationException]::new($message.Trim())
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationGitHubLatestReleaseVerificationFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $approvedLatestTag)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            $destinationLatestJson = ($destinationLatestResult.Output | ForEach-Object { [string] $_ }) -join "`n"
            $destinationLatest = $destinationLatestJson | ConvertFrom-Json -Depth 100
            if ([string] $destinationLatest.tag_name -ne $approvedLatestTag) {
                $message = "Destination latest release is '$($destinationLatest.tag_name)' instead of approved source latest release '$approvedLatestTag'."
                $exception = [System.InvalidOperationException]::new($message)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationGitHubLatestReleaseVerificationFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $approvedLatestTag)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
        }

        [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.ReleaseMigrationResult'
            SourceRepository = $SourceRepository.FullName
            DestinationRepository = $DestinationRepository.FullName
            ApprovedReleaseCount = $approvedReleases.Count
            DestinationReleaseCount = $migrated.Count
            LatestReleasePreserved = [bool] $approvedLatestIncluded
            LatestReleaseTag = $approvedLatestTag
            Releases = $migrated.ToArray()
            Unsupported = @('OriginalReleaseId', 'OriginalCreatedAt', 'OriginalPublishedAt', 'ReleaseDownloadCounts', 'ReleaseImmutability', 'LinkedDiscussion')
            IsSuccessful = $migrated.Count -eq $approvedReleases.Count
        }
    }
    finally {
        if (Test-Path -LiteralPath $workspacePath) { Remove-Item -LiteralPath $workspacePath -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
