function Copy-CgrGitHubRelease {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'The public Copy-GitHubRepository command performs the ShouldProcess check before calling this GitHub release migration boundary.'
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

    $listResult = Invoke-CgrNativeCommand `
        -FilePath 'gh' `
        -ArgumentList @(
            'api', '--hostname', $HostName,
            '--paginate', '--slurp',
            "repos/$($SourceRepository.FullName)/releases?per_page=100"
        )

    if ($listResult.ExitCode -ne 0) {
        $message = "GitHub CLI failed to enumerate releases for '$($SourceRepository.FullName)'. $($listResult.ErrorText)"
        $exception = [System.InvalidOperationException]::new($message.Trim())
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'SourceGitHubReleaseEnumerationFailed',
            [System.Management.Automation.ErrorCategory]::ReadError,
            $SourceRepository.FullName
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $json = ($listResult.Output | ForEach-Object { [string] $_ }) -join "`n"
    $pages = if ([string]::IsNullOrWhiteSpace($json)) { @() } else { @($json | ConvertFrom-Json -Depth 100) }
    $sourceReleases = [System.Collections.Generic.List[object]]::new()
    foreach ($page in $pages) {
        foreach ($release in @($page)) {
            if ($null -ne $release) {
                $sourceReleases.Add($release)
            }
        }
    }

    if ($sourceReleases.Count -eq 0) {
        return [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.ReleaseMigrationResult'
            SourceRepository = $SourceRepository.FullName
            DestinationRepository = $DestinationRepository.FullName
            SourceReleaseCount = 0
            DestinationReleaseCount = 0
            Releases = @()
            Unsupported = @('OriginalReleaseId', 'OriginalCreatedAt', 'OriginalPublishedAt', 'ReleaseDownloadCounts')
            IsSuccessful = $true
        }
    }

    $workspacePath = Join-Path ([System.IO.Path]::GetTempPath()) "copy-github-repo-releases-$([guid]::NewGuid().ToString('N'))"
    $migrated = [System.Collections.Generic.List[object]]::new()

    try {
        New-Item -Path $workspacePath -ItemType Directory -Force | Out-Null

        foreach ($sourceRelease in $sourceReleases) {
            $tagName = [string] $sourceRelease.tag_name
            if ([string]::IsNullOrWhiteSpace($tagName)) {
                $message = "Source release id '$($sourceRelease.id)' does not have a tag name and cannot be migrated safely."
                $exception = [System.InvalidOperationException]::new($message)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'SourceGitHubReleaseTagMissing',
                    [System.Management.Automation.ErrorCategory]::InvalidData,
                    $sourceRelease.id
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            $sourceCommitResult = Invoke-CgrNativeCommand `
                -FilePath 'gh' `
                -ArgumentList @('api', '--hostname', $HostName, "repos/$($SourceRepository.FullName)/commits/$([uri]::EscapeDataString($tagName))", '--jq', '.sha')
            $destinationCommitResult = Invoke-CgrNativeCommand `
                -FilePath 'gh' `
                -ArgumentList @('api', '--hostname', $HostName, "repos/$($DestinationRepository.FullName)/commits/$([uri]::EscapeDataString($tagName))", '--jq', '.sha')

            if ($sourceCommitResult.ExitCode -ne 0 -or $destinationCommitResult.ExitCode -ne 0) {
                $message = "Release tag '$tagName' must resolve to an existing FullHistory commit in both source and destination before the GitHub Release can be restored."
                $exception = [System.InvalidOperationException]::new($message)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'GitHubReleaseTagResolutionFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidResult,
                    $tagName
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            $sourceCommitSha = [string] @($sourceCommitResult.Output)[0]
            $destinationCommitSha = [string] @($destinationCommitResult.Output)[0]
            if ($sourceCommitSha -ne $destinationCommitSha) {
                $message = "Release tag '$tagName' resolves to '$sourceCommitSha' in the source but '$destinationCommitSha' in the destination. Release restoration stopped because FullHistory identity is not preserved."
                $exception = [System.InvalidOperationException]::new($message)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'GitHubReleaseTagTargetMismatch',
                    [System.Management.Automation.ErrorCategory]::InvalidResult,
                    $tagName
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            $existingReleaseResult = Invoke-CgrNativeCommand `
                -FilePath 'gh' `
                -ArgumentList @('release', 'view', $tagName, '--repo', $DestinationRepository.FullName)
            if ($existingReleaseResult.ExitCode -eq 0) {
                $message = "Destination '$($DestinationRepository.FullName)' already contains a GitHub Release for tag '$tagName'. The tool will not overwrite an existing release."
                $exception = [System.InvalidOperationException]::new($message)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'DestinationGitHubReleaseAlreadyExists',
                    [System.Management.Automation.ErrorCategory]::ResourceExists,
                    $tagName
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            $releasePath = Join-Path $workspacePath ([uri]::EscapeDataString($tagName))
            $assetPath = Join-Path $releasePath 'assets'
            $notesPath = Join-Path $releasePath 'release-notes.md'
            New-Item -Path $assetPath -ItemType Directory -Force | Out-Null
            [System.IO.File]::WriteAllText($notesPath, [string] $sourceRelease.body, [System.Text.UTF8Encoding]::new($false))

            $sourceAssets = @($sourceRelease.assets)
            if ($sourceAssets.Count -gt 0) {
                $downloadResult = Invoke-CgrNativeCommand `
                    -FilePath 'gh' `
                    -ArgumentList @('release', 'download', $tagName, '--repo', $SourceRepository.FullName, '--dir', $assetPath)
                if ($downloadResult.ExitCode -ne 0) {
                    $message = "GitHub CLI failed to download assets for release '$tagName'. $($downloadResult.ErrorText)"
                    $exception = [System.InvalidOperationException]::new($message.Trim())
                    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                        $exception,
                        'SourceGitHubReleaseAssetDownloadFailed',
                        [System.Management.Automation.ErrorCategory]::ReadError,
                        $tagName
                    )
                    $PSCmdlet.ThrowTerminatingError($errorRecord)
                }
            }

            $createArguments = [System.Collections.Generic.List[string]]::new()
            foreach ($argument in @('release', 'create', $tagName, '--repo', $DestinationRepository.FullName, '--verify-tag', '--notes-file', $notesPath)) {
                $createArguments.Add($argument)
            }
            if (-not [string]::IsNullOrWhiteSpace([string] $sourceRelease.name)) {
                $createArguments.Add('--title')
                $createArguments.Add([string] $sourceRelease.name)
            }
            if ([bool] $sourceRelease.draft) {
                $createArguments.Add('--draft')
            }
            if ([bool] $sourceRelease.prerelease) {
                $createArguments.Add('--prerelease')
            }

            $createResult = Invoke-CgrNativeCommand -FilePath 'gh' -ArgumentList $createArguments.ToArray()
            if ($createResult.ExitCode -ne 0) {
                $message = "GitHub CLI failed to create destination release '$tagName'. $($createResult.ErrorText)"
                $exception = [System.InvalidOperationException]::new($message.Trim())
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'DestinationGitHubReleaseCreateFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $tagName
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            if ($sourceAssets.Count -gt 0) {
                $uploadArguments = [System.Collections.Generic.List[string]]::new()
                foreach ($argument in @('release', 'upload', $tagName, '--repo', $DestinationRepository.FullName)) {
                    $uploadArguments.Add($argument)
                }

                foreach ($sourceAsset in $sourceAssets) {
                    $assetFilePath = Join-Path $assetPath ([string] $sourceAsset.name)
                    if (-not (Test-Path -LiteralPath $assetFilePath -PathType Leaf)) {
                        $message = "Downloaded release asset '$($sourceAsset.name)' for '$tagName' was not found at the expected local path."
                        $exception = [System.IO.FileNotFoundException]::new($message, $assetFilePath)
                        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                            $exception,
                            'SourceGitHubReleaseAssetMissingAfterDownload',
                            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                            $assetFilePath
                        )
                        $PSCmdlet.ThrowTerminatingError($errorRecord)
                    }

                    $uploadValue = if ([string]::IsNullOrWhiteSpace([string] $sourceAsset.label)) {
                        $assetFilePath
                    }
                    else {
                        "$assetFilePath#$([string] $sourceAsset.label)"
                    }
                    $uploadArguments.Add($uploadValue)
                }

                $uploadResult = Invoke-CgrNativeCommand -FilePath 'gh' -ArgumentList $uploadArguments.ToArray()
                if ($uploadResult.ExitCode -ne 0) {
                    $message = "GitHub CLI failed to upload assets for destination release '$tagName'. $($uploadResult.ErrorText)"
                    $exception = [System.InvalidOperationException]::new($message.Trim())
                    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                        $exception,
                        'DestinationGitHubReleaseAssetUploadFailed',
                        [System.Management.Automation.ErrorCategory]::InvalidOperation,
                        $tagName
                    )
                    $PSCmdlet.ThrowTerminatingError($errorRecord)
                }
            }

            $destinationReleaseResult = Invoke-CgrNativeCommand `
                -FilePath 'gh' `
                -ArgumentList @('api', '--hostname', $HostName, "repos/$($DestinationRepository.FullName)/releases/tags/$([uri]::EscapeDataString($tagName))")
            if ($destinationReleaseResult.ExitCode -ne 0) {
                $message = "GitHub CLI failed to reload destination release '$tagName' for verification. $($destinationReleaseResult.ErrorText)"
                $exception = [System.InvalidOperationException]::new($message.Trim())
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'DestinationGitHubReleaseVerificationReadFailed',
                    [System.Management.Automation.ErrorCategory]::ReadError,
                    $tagName
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            $destinationReleaseJson = ($destinationReleaseResult.Output | ForEach-Object { [string] $_ }) -join "`n"
            $destinationRelease = $destinationReleaseJson | ConvertFrom-Json -Depth 100
            $mismatches = [System.Collections.Generic.List[string]]::new()

            if ([string] $destinationRelease.tag_name -ne $tagName) { $mismatches.Add('TagName') }
            if ([string] $destinationRelease.name -ne [string] $sourceRelease.name) { $mismatches.Add('Name') }
            if ([string] $destinationRelease.body -ne [string] $sourceRelease.body) { $mismatches.Add('Body') }
            if ([bool] $destinationRelease.draft -ne [bool] $sourceRelease.draft) { $mismatches.Add('Draft') }
            if ([bool] $destinationRelease.prerelease -ne [bool] $sourceRelease.prerelease) { $mismatches.Add('Prerelease') }

            $destinationAssets = @($destinationRelease.assets)
            if ($destinationAssets.Count -ne $sourceAssets.Count) {
                $mismatches.Add("AssetCount:$($sourceAssets.Count)!=$($destinationAssets.Count)")
            }
            foreach ($sourceAsset in $sourceAssets) {
                $destinationAsset = @($destinationAssets | Where-Object { [string] $_.name -eq [string] $sourceAsset.name }) | Select-Object -First 1
                if ($null -eq $destinationAsset) {
                    $mismatches.Add("AssetMissing:$($sourceAsset.name)")
                    continue
                }
                if ([long] $destinationAsset.size -ne [long] $sourceAsset.size) {
                    $mismatches.Add("AssetSize:$($sourceAsset.name)")
                }
                if (-not [string]::IsNullOrWhiteSpace([string] $sourceAsset.digest) -and
                    [string] $destinationAsset.digest -ne [string] $sourceAsset.digest) {
                    $mismatches.Add("AssetDigest:$($sourceAsset.name)")
                }
            }

            if ($mismatches.Count -gt 0) {
                $message = "Destination GitHub Release verification failed for '$tagName': $($mismatches -join ', ')."
                $exception = [System.InvalidOperationException]::new($message)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'DestinationGitHubReleaseVerificationFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidResult,
                    $tagName
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            $migrated.Add([pscustomobject] @{
                    TagName = $tagName
                    SourceReleaseId = $sourceRelease.id
                    DestinationReleaseId = $destinationRelease.id
                    SourceCommitSha = $sourceCommitSha
                    DestinationCommitSha = $destinationCommitSha
                    Name = $sourceRelease.name
                    Draft = [bool] $sourceRelease.draft
                    Prerelease = [bool] $sourceRelease.prerelease
                    SourceCreatedAt = $sourceRelease.created_at
                    SourcePublishedAt = $sourceRelease.published_at
                    DestinationCreatedAt = $destinationRelease.created_at
                    DestinationPublishedAt = $destinationRelease.published_at
                    AssetCount = $sourceAssets.Count
                    IsVerified = $true
                })
        }

        return [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.ReleaseMigrationResult'
            SourceRepository = $SourceRepository.FullName
            DestinationRepository = $DestinationRepository.FullName
            SourceReleaseCount = $sourceReleases.Count
            DestinationReleaseCount = $migrated.Count
            Releases = $migrated.ToArray()
            Unsupported = @('OriginalReleaseId', 'OriginalCreatedAt', 'OriginalPublishedAt', 'ReleaseDownloadCounts')
            IsSuccessful = $migrated.Count -eq $sourceReleases.Count
        }
    }
    finally {
        if (Test-Path -LiteralPath $workspacePath) {
            Remove-Item -LiteralPath $workspacePath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
