function Invoke-RecoveryE2eScopedSettingsReadbackDrift {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock] $Action,
        [Parameter(Mandatory)][string] $ExpectedDestination,
        [Parameter(Mandatory)][string] $ExpectedArchive,
        [Parameter(Mandatory)][string] $ExpectedOriginalRepositoryId,
        [Parameter(Mandatory)][string] $ApprovedDescription,
        [Parameter(Mandatory)][string] $DriftDescription,
        [Parameter(Mandatory)][string] $HostName
    )

    # Both names must identify this run's distinct disposable repositories.
    if ($ExpectedDestination -notmatch '^infoconex/copy-github-repo-recovery-e2e-[0-9a-f]{10}-settingsfault-destination$' -or
        $ExpectedArchive -notmatch '^infoconex/copy-github-repo-recovery-e2e-[0-9a-f]{10}-settingsfault-archive$' -or
        (($ExpectedDestination -replace '-settingsfault-destination$', '') -cne
        ($ExpectedArchive -replace '-settingsfault-archive
        $ExpectedOriginalRepositoryId -notmatch '^[0-9]+$' -or
        $HostName -cne 'github.com' -or
        [string]::IsNullOrWhiteSpace($ApprovedDescription) -or
        [string]::IsNullOrWhiteSpace($DriftDescription) -or
        $ApprovedDescription -ceq $DriftDescription) {
        throw 'Settings drift fault requires exact matching, run-scoped test identities and distinct descriptions.'
    }

    $module = Get-Module CopyGitHubRepo -ErrorAction Stop
    if (-not $module) { throw 'Settings drift probe requires the loaded CopyGitHubRepo module.' }

    $capturedError = $null
    $actionOutput = @()
    $patchCalls = 0
    $driftWrites = 0
    $replacementId = $null
    try {
        & $module {
            param($destinationName, $archiveName, $originalId, $approved, $drift, $hostName)
            $script:RecoveryE2eSettingsOriginalNativeCommand = (Get-Item Function:Invoke-CgrNativeCommand -ErrorAction Stop).ScriptBlock
            $script:RecoveryE2eSettingsFault = @{
                Destination = $destinationName
                Archive = $archiveName
                OriginalId = $originalId
                Approved = $approved
                Drift = $drift
                HostName = $hostName
                PatchCalls = 0
                DriftWrites = 0
                ReplacementId = $null
            }
            Set-Item -Path Function:script:Invoke-CgrNativeCommand -Value {
                [CmdletBinding()]
                param(
                    [Parameter(Mandatory)][string] $FilePath,
                    [string[]] $ArgumentList = @(),
                    [string[]] $PrefixArgumentList = @(),
                    [hashtable] $Environment = @{},
                    [TimeSpan] $Timeout = [System.Threading.Timeout]::InfiniteTimeSpan,
                    [System.Threading.CancellationToken] $CancellationToken = [System.Threading.CancellationToken]::None
                )
                $argsList = @($ArgumentList)
                $isPatch = $FilePath -ceq 'gh' -and $argsList.Count -ge 6 -and
                $argsList[0] -ceq 'api' -and $argsList[1] -ceq '--hostname' -and
                $argsList[2] -ceq $script:RecoveryE2eSettingsFault.HostName -and
                $argsList[3] -ceq '-X' -and $argsList[4] -ceq 'PATCH'

                if (-not $isPatch) {
                    return & $script:RecoveryE2eSettingsOriginalNativeCommand @PSBoundParameters
                }

                $fault = $script:RecoveryE2eSettingsFault
                if ($argsList[5] -cne "repos/$($fault.Destination)" -or
                    $argsList -cnotcontains "description=$($fault.Approved)" -or
                    $fault.PatchCalls -ne 0) {
                    throw 'Scoped settings fault rejected an unexpected PATCH target, payload or repeated call.'
                }
                $fault.PatchCalls++

                # Independent real GitHub reads before letting the mutation run.
                # They confirm the old immutable ID has moved to this test archive
                # and that the reused name is a distinct, private test replacement.
                $archiveRead = & $script:RecoveryE2eSettingsOriginalNativeCommand -FilePath 'gh' -ArgumentList @('api', '--hostname', $fault.HostName, "repos/$($fault.Archive)")
                $replacementRead = & $script:RecoveryE2eSettingsOriginalNativeCommand -FilePath 'gh' -ArgumentList @('api', '--hostname', $fault.HostName, "repos/$($fault.Destination)")
                if ($archiveRead.ExitCode -ne 0 -or $replacementRead.ExitCode -ne 0) {
                    throw 'Scoped settings fault could not independently read both test repositories.'
                }
                $archive = (@($archiveRead.Output) -join [Environment]::NewLine) | ConvertFrom-Json -ErrorAction Stop
                $replacement = (@($replacementRead.Output) -join [Environment]::NewLine) | ConvertFrom-Json -ErrorAction Stop
                if ([string] $archive.id -cne [string] $fault.OriginalId -or
                    $archive.full_name -cne $fault.Archive -or $archive.private -ne $true -or
                    $replacement.full_name -cne $fault.Destination -or $replacement.private -ne $true -or
                    [string] $replacement.id -ceq [string] $fault.OriginalId -or
                    [string]::IsNullOrWhiteSpace([string] $replacement.id)) {
                    throw 'Scoped settings fault remote identity/private-state preflight failed. No test drift PATCH attempted.'
                }
                $fault.ReplacementId = [string] $replacement.id

                # Allow the unmodified production operation to PATCH the actual
                # supported setting. Never pretend a failed PATCH succeeded.
                $productionPatch = & $script:RecoveryE2eSettingsOriginalNativeCommand @PSBoundParameters
                if ($productionPatch.ExitCode -ne 0) { return $productionPatch }

                $afterProduction = & $script:RecoveryE2eSettingsOriginalNativeCommand -FilePath 'gh' -ArgumentList @('api', '--hostname', $fault.HostName, "repos/$($fault.Destination)")
                if ($afterProduction.ExitCode -ne 0) { throw 'Could not read back genuine production settings PATCH.' }
                $restored = (@($afterProduction.Output) -join [Environment]::NewLine) | ConvertFrom-Json -ErrorAction Stop
                if ([string] $restored.id -cne $fault.ReplacementId -or
                    $restored.full_name -cne $fault.Destination -or
                    $restored.private -ne $true -or
                    [string] $restored.description -cne $fault.Approved) {
                    throw 'Real production settings PATCH did not persist the approved test description.'
                }

                # Deliberately change ONLY this new private test replacement.
                # The unmodified production Get-CgrRepository readback must
                # catch the genuine server-side description mismatch.
                $driftPatch = & $script:RecoveryE2eSettingsOriginalNativeCommand -FilePath 'gh' -ArgumentList @('api', '--hostname', $fault.HostName, '-X', 'PATCH', "repos/$($fault.Destination)", '-f', "description=$($fault.Drift)")
                if ($driftPatch.ExitCode -ne 0) { throw 'Real disposable settings-drift PATCH failed.' }
                $fault.DriftWrites++
                $afterDrift = & $script:RecoveryE2eSettingsOriginalNativeCommand -FilePath 'gh' -ArgumentList @('api', '--hostname', $fault.HostName, "repos/$($fault.Destination)")
                if ($afterDrift.ExitCode -ne 0) { throw 'Could not independently verify test settings drift.' }
                $drifted = (@($afterDrift.Output) -join [Environment]::NewLine) | ConvertFrom-Json -ErrorAction Stop
                if ([string] $drifted.id -cne $fault.ReplacementId -or
                    $drifted.full_name -cne $fault.Destination -or
                    $drifted.private -ne $true -or
                    [string] $drifted.description -cne $fault.Drift) {
                    throw 'Disposable replacement did not retain independently verified settings drift.'
                }
                return $productionPatch
            }
        } $ExpectedDestination $ExpectedArchive $ExpectedOriginalRepositoryId $ApprovedDescription $DriftDescription $HostName

        try { $actionOutput = @(& $Action) }
        catch { $capturedError = $_ }
    }
    finally {
        $finalState = & $module {
            try {
                [pscustomobject] @{
                    PatchCalls = $script:RecoveryE2eSettingsFault.PatchCalls
                    DriftWrites = $script:RecoveryE2eSettingsFault.DriftWrites
                    ReplacementId = $script:RecoveryE2eSettingsFault.ReplacementId
                }
            }
            finally {
                if ($script:RecoveryE2eSettingsOriginalNativeCommand) {
                    Set-Item -Path Function:script:Invoke-CgrNativeCommand -Value $script:RecoveryE2eSettingsOriginalNativeCommand
                }
                Remove-Variable -Name RecoveryE2eSettingsOriginalNativeCommand -Scope Script -ErrorAction SilentlyContinue
                Remove-Variable -Name RecoveryE2eSettingsFault -Scope Script -ErrorAction SilentlyContinue
            }
        }
        if ($finalState) {
            $patchCalls = $finalState.PatchCalls
            $driftWrites = $finalState.DriftWrites
            $replacementId = $finalState.ReplacementId
        }
    }

    [pscustomobject] @{
        OriginalError = $capturedError
        ProductionPatchCalls = $patchCalls
        AuthenticatedDriftWrites = $driftWrites
        ReplacementRepositoryId = $replacementId
        Output = @($actionOutput)
    }
}
, '')) -or
        $ExpectedOriginalRepositoryId -notmatch '^[0-9]+$' -or
        $HostName -cne 'github.com' -or
        [string]::IsNullOrWhiteSpace($ApprovedDescription) -or
        [string]::IsNullOrWhiteSpace($DriftDescription) -or
        $ApprovedDescription -ceq $DriftDescription) {
        throw 'Settings drift fault requires exact matching, run-scoped test identities and distinct descriptions.'
    }

    $module = Get-Module CopyGitHubRepo -ErrorAction Stop
    if (-not $module) { throw 'Settings drift probe requires the loaded CopyGitHubRepo module.' }

    $capturedError = $null
    $actionOutput = @()
    $patchCalls = 0
    $driftWrites = 0
    $replacementId = $null
    try {
        & $module {
            param($destinationName, $archiveName, $originalId, $approved, $drift, $hostName)
            $script:RecoveryE2eSettingsOriginalNativeCommand = (Get-Item Function:Invoke-CgrNativeCommand -ErrorAction Stop).ScriptBlock
            $script:RecoveryE2eSettingsFault = @{
                Destination = $destinationName
                Archive = $archiveName
                OriginalId = $originalId
                Approved = $approved
                Drift = $drift
                HostName = $hostName
                PatchCalls = 0
                DriftWrites = 0
                ReplacementId = $null
            }
            Set-Item -Path Function:script:Invoke-CgrNativeCommand -Value {
                [CmdletBinding()]
                param(
                    [Parameter(Mandatory)][string] $FilePath,
                    [string[]] $ArgumentList = @(),
                    [string[]] $PrefixArgumentList = @(),
                    [hashtable] $Environment = @{},
                    [TimeSpan] $Timeout = [System.Threading.Timeout]::InfiniteTimeSpan,
                    [System.Threading.CancellationToken] $CancellationToken = [System.Threading.CancellationToken]::None
                )
                $argsList = @($ArgumentList)
                $isPatch = $FilePath -ceq 'gh' -and $argsList.Count -ge 6 -and
                    $argsList[0] -ceq 'api' -and $argsList[1] -ceq '--hostname' -and
                    $argsList[2] -ceq $script:RecoveryE2eSettingsFault.HostName -and
                    $argsList[3] -ceq '-X' -and $argsList[4] -ceq 'PATCH'

                if (-not $isPatch) {
                    return & $script:RecoveryE2eSettingsOriginalNativeCommand @PSBoundParameters
                }

                $fault = $script:RecoveryE2eSettingsFault
                if ($argsList[5] -cne "repos/$($fault.Destination)" -or
                    $argsList -cnotcontains "description=$($fault.Approved)" -or
                    $fault.PatchCalls -ne 0) {
                    throw 'Scoped settings fault rejected an unexpected PATCH target, payload or repeated call.'
                }
                $fault.PatchCalls++

                # Independent real GitHub reads before letting the mutation run.
                # They confirm the old immutable ID has moved to this test archive
                # and that the reused name is a distinct, private test replacement.
                $archiveRead = & $script:RecoveryE2eSettingsOriginalNativeCommand -FilePath 'gh' -ArgumentList @('api', '--hostname', $fault.HostName, "repos/$($fault.Archive)")
                $replacementRead = & $script:RecoveryE2eSettingsOriginalNativeCommand -FilePath 'gh' -ArgumentList @('api', '--hostname', $fault.HostName, "repos/$($fault.Destination)")
                if ($archiveRead.ExitCode -ne 0 -or $replacementRead.ExitCode -ne 0) {
                    throw 'Scoped settings fault could not independently read both test repositories.'
                }
                $archive = (@($archiveRead.Output) -join [Environment]::NewLine) | ConvertFrom-Json -ErrorAction Stop
                $replacement = (@($replacementRead.Output) -join [Environment]::NewLine) | ConvertFrom-Json -ErrorAction Stop
                if ([string] $archive.id -cne [string] $fault.OriginalId -or
                    $archive.full_name -cne $fault.Archive -or $archive.private -ne $true -or
                    $replacement.full_name -cne $fault.Destination -or $replacement.private -ne $true -or
                    [string] $replacement.id -ceq [string] $fault.OriginalId -or
                    [string]::IsNullOrWhiteSpace([string] $replacement.id)) {
                    throw 'Scoped settings fault remote identity/private-state preflight failed. No test drift PATCH attempted.'
                }
                $fault.ReplacementId = [string] $replacement.id

                # Allow the unmodified production operation to PATCH the actual
                # supported setting. Never pretend a failed PATCH succeeded.
                $productionPatch = & $script:RecoveryE2eSettingsOriginalNativeCommand @PSBoundParameters
                if ($productionPatch.ExitCode -ne 0) { return $productionPatch }

                $afterProduction = & $script:RecoveryE2eSettingsOriginalNativeCommand -FilePath 'gh' -ArgumentList @('api', '--hostname', $fault.HostName, "repos/$($fault.Destination)")
                if ($afterProduction.ExitCode -ne 0) { throw 'Could not read back genuine production settings PATCH.' }
                $restored = (@($afterProduction.Output) -join [Environment]::NewLine) | ConvertFrom-Json -ErrorAction Stop
                if ([string] $restored.id -cne $fault.ReplacementId -or
                    $restored.full_name -cne $fault.Destination -or
                    $restored.private -ne $true -or
                    [string] $restored.description -cne $fault.Approved) {
                    throw 'Real production settings PATCH did not persist the approved test description.'
                }

                # Deliberately change ONLY this new private test replacement.
                # The unmodified production Get-CgrRepository readback must
                # catch the genuine server-side description mismatch.
                $driftPatch = & $script:RecoveryE2eSettingsOriginalNativeCommand -FilePath 'gh' -ArgumentList @('api', '--hostname', $fault.HostName, '-X', 'PATCH', "repos/$($fault.Destination)", '-f', "description=$($fault.Drift)")
                if ($driftPatch.ExitCode -ne 0) { throw 'Real disposable settings-drift PATCH failed.' }
                $fault.DriftWrites++
                $afterDrift = & $script:RecoveryE2eSettingsOriginalNativeCommand -FilePath 'gh' -ArgumentList @('api', '--hostname', $fault.HostName, "repos/$($fault.Destination)")
                if ($afterDrift.ExitCode -ne 0) { throw 'Could not independently verify test settings drift.' }
                $drifted = (@($afterDrift.Output) -join [Environment]::NewLine) | ConvertFrom-Json -ErrorAction Stop
                if ([string] $drifted.id -cne $fault.ReplacementId -or
                    $drifted.full_name -cne $fault.Destination -or
                    $drifted.private -ne $true -or
                    [string] $drifted.description -cne $fault.Drift) {
                    throw 'Disposable replacement did not retain independently verified settings drift.'
                }
                return $productionPatch
            }
        } $ExpectedDestination $ExpectedArchive $ExpectedOriginalRepositoryId $ApprovedDescription $DriftDescription $HostName

        try { $actionOutput = @(& $Action) }
        catch { $capturedError = $_ }
    }
    finally {
        $finalState = & $module {
            try {
                [pscustomobject] @{
                    PatchCalls = $script:RecoveryE2eSettingsFault.PatchCalls
                    DriftWrites = $script:RecoveryE2eSettingsFault.DriftWrites
                    ReplacementId = $script:RecoveryE2eSettingsFault.ReplacementId
                }
            }
            finally {
                if ($script:RecoveryE2eSettingsOriginalNativeCommand) {
                    Set-Item -Path Function:script:Invoke-CgrNativeCommand -Value $script:RecoveryE2eSettingsOriginalNativeCommand
                }
                Remove-Variable -Name RecoveryE2eSettingsOriginalNativeCommand -Scope Script -ErrorAction SilentlyContinue
                Remove-Variable -Name RecoveryE2eSettingsFault -Scope Script -ErrorAction SilentlyContinue
            }
        }
        if ($finalState) {
            $patchCalls = $finalState.PatchCalls
            $driftWrites = $finalState.DriftWrites
            $replacementId = $finalState.ReplacementId
        }
    }

    [pscustomobject] @{
        OriginalError = $capturedError
        ProductionPatchCalls = $patchCalls
        AuthenticatedDriftWrites = $driftWrites
        ReplacementRepositoryId = $replacementId
        Output = @($actionOutput)
    }
}
