BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $traceabilityPath = Join-Path $repositoryRoot 'tests/ProductTraceability.psd1'
    $script:traceability = Import-PowerShellDataFile -Path $traceabilityPath
    $script:productModelPath = Join-Path $repositoryRoot 'docs/product/product-model.md'
    $script:productModel = Get-Content -LiteralPath $script:productModelPath -Raw
    $script:productScenarioIds = @(
        [regex]::Matches($script:productModel, '\bSCN-[A-Z0-9-]+-\d{2}\b') |
            ForEach-Object { $_.Value } |
            Sort-Object -Unique
    )
}

Describe 'Product scenario traceability contract' {
    It 'uses a versioned machine-readable registry' {
        $script:traceability.SchemaVersion | Should -Be 1
        $script:traceability.Scenarios | Should -Not -BeNullOrEmpty
    }

    It 'maps every canonical product scenario exactly once using stable product identifiers' {
        $mappedScenarioIds = @($script:traceability.Scenarios.Keys | Sort-Object)
        $mappedScenarioIds.Count | Should -Be $script:productScenarioIds.Count
        ($mappedScenarioIds -join "`n") | Should -Be ($script:productScenarioIds -join "`n")

        foreach ($scenarioId in $mappedScenarioIds) {
            $scenarioId | Should -Match '^SCN-[A-Z0-9-]+-\d{2}$'
            $scenarioId | Should -Not -Match '^#?\d+$'
        }
    }

    It 'classifies every mapped scenario explicitly' {
        foreach ($entry in $script:traceability.Scenarios.GetEnumerator()) {
            $entry.Value.Classification | Should -BeIn @('Required', 'Deferred', 'Unsupported', 'Constrained')
        }
    }

    It 'requires deterministic automated evidence for required scenarios' {
        foreach ($entry in $script:traceability.Scenarios.GetEnumerator()) {
            if ($entry.Value.Classification -ne 'Required') {
                continue
            }

            @($entry.Value.AutomatedEvidence).Count | Should -BeGreaterThan 0
        }
    }

    It 'does not reference stale or nonexistent automated evidence files' {
        foreach ($entry in $script:traceability.Scenarios.GetEnumerator()) {
            foreach ($relativePath in @($entry.Value.AutomatedEvidence)) {
                $relativePath | Should -Match '^tests/(unit|integration|contract)/.+\.Tests\.ps1$'
                Test-Path -LiteralPath (Join-Path $repositoryRoot $relativePath) | Should -BeTrue -Because "$($entry.Key) references $relativePath"
            }
        }
    }

    It 'classifies live validation requirements explicitly' {
        foreach ($entry in $script:traceability.Scenarios.GetEnumerator()) {
            $entry.Value.LiveValidation | Should -BeIn @('Required', 'NotRequired', 'Constrained')
        }
    }

    It 'requires genuine live evidence or an explicitly blocked Required-live fixture' {
        $pending = @('SCN-DEST-PARTIAL-01', 'SCN-SET-PARTIAL-01', 'SCN-RECOVER-RECOVERY-01', 'SCN-RETRY-RESILIENCE-02')
        foreach ($entry in $script:traceability.Scenarios.GetEnumerator()) {
            if ($entry.Value.LiveValidation -ne 'Required') {
                continue
            }
            if ($entry.Key -in $pending) {
                $entry.Value.Classification | Should -Be 'Required'
                @($entry.Value.LiveEvidence).Count | Should -Be 0 -Because "$($entry.Key) has no valid authenticated failure fixture"
                $entry.Value.LiveEvidenceStatus | Should -Be 'PendingSafeFixture'
                [string] $entry.Value.LiveReason | Should -Not -BeNullOrEmpty
                continue
            }
            @($entry.Value.LiveEvidence).Count | Should -BeGreaterThan 0 -Because "$($entry.Key) requires a real live harness"
        }
        foreach ($entry in $script:traceability.Scenarios.GetEnumerator()) {
            if ($entry.Value.LiveEvidenceStatus -eq 'PendingSafeFixture') {
                $entry.Key | Should -BeIn $pending -Because 'pending required-live exceptions must be explicitly reviewed'
            }
        }
    }

    It 'does not reference stale or nonexistent live evidence harnesses' {
        foreach ($entry in $script:traceability.Scenarios.GetEnumerator()) {
            foreach ($relativePath in @($entry.Value.LiveEvidence)) {
                $relativePath | Should -Match '^tests/e2e/Invoke-.+\.ps1$'
                Test-Path -LiteralPath (Join-Path $repositoryRoot $relativePath) | Should -BeTrue -Because "$($entry.Key) references $relativePath"
            }
        }
    }

    It 'does not advertise unimplemented post-mutation scenarios as live proof' {
        $harnessPath = 'tests/e2e/Invoke-RecoveryEndToEndTests.ps1'
        $source = Get-Content -LiteralPath (Join-Path $repositoryRoot $harnessPath) -Raw

        $happy = $script:traceability.Scenarios['SCN-DEST-HAPPY-01']
        $happy.LiveValidation | Should -Be 'Required'
        @($happy.LiveEvidence) | Should -Contain $harnessPath
        ([regex]::Matches($source, "ScenarioId\s*=\s*'SCN-DEST-HAPPY-01'")).Count | Should -Be 1

        $source | Should -Match "ScenarioId\s*=\s*'SCN-LFS-VALIDATION-01'"
        $source | Should -Match 'SnapshotPlanningGitLfsFetchFailed,Get-CgrRepositoryDefaultBranchTree'
        $source | Should -Match 'lfs-planning-validation\.json'
        $source | Should -Match 'existing-destination-happy-result\.json'
        $source | Should -Match 'required-live-evidence-pending\.json'
        $source | Should -Match '\[switch\] \$SafeSubsetOnly'
        $source | Should -Match 'if \(-not \$SafeSubsetOnly\)'
        $source | Should -Match 'CompleteRequiredLiveQualification = \$false'
        $source | Should -Match 'IndependentDestinationAbsenceVerified = \$true'
        $source | Should -Match 'Assert-RecoveryE2eRepositoryAbsent -Repository \$destinationRepository'

        foreach ($id in @('SCN-DEST-PARTIAL-01', 'SCN-SET-PARTIAL-01', 'SCN-RETRY-RESILIENCE-02', 'SCN-RECOVER-RECOVERY-01')) {
            $entry = $script:traceability.Scenarios[$id]
            $entry.LiveValidation | Should -Be 'Required'
            @($entry.LiveEvidence).Count | Should -Be 0
            $entry.LiveEvidenceStatus | Should -Be 'PendingSafeFixture'
            $source | Should -Not -Match ("ScenarioId\s*=\s*'{0}'" -f $id)
        }

        $source | Should -Match 'Get-RecoveryE2eRemoteRepository'
        $source | Should -Match 'Get-RecoveryE2eRemoteCommit'
        $source | Should -Match 'ExistingDestinationArchiveName\s+\$happyArchiveName'
        $source | Should -Match 'ExistingDestinationConfirmation\s+\$confirmation'
        $source | Should -Match 'ArchivedOriginalIdentityPreserved'
        $source | Should -Match 'IndependentVerificationSucceeded'
        $source | Should -Match 'OneUnrelatedRootCommit'
        $source | Should -Match 'Assert-RecoveryE2eCleanupCapability'
        $source | Should -Match 'Remove-RecoveryE2eRepository'
        $source | Should -Not -Match 'Copy-GitHubRepository -SourceRepository \$sourceRepository -DestinationRepository \$partialDestination'
    }

    It 'preserves opt-in live recovery reports outside destructive fixture cleanup' {
        $harnessPath = Join-Path $repositoryRoot 'tests/e2e/Invoke-RecoveryEndToEndTests.ps1'
        $source = Get-Content -LiteralPath $harnessPath -Raw

        $source | Should -Match '\[string\] \$EvidenceDirectory'
        $source | Should -Match 'Refusing to overwrite existing recovery E2E evidence directory'
        $source | Should -Match 'outside the temporary fixture directory that cleanup deletes'
        $source | Should -Match 'Copy-Item -LiteralPath \$report\.FullName -Destination \$evidenceRunPath -ErrorAction Stop'
        $source | Should -Match 'if \(\$cleanupFailures\.Count -eq 0 -and \$cleanupRecordWritten -and \$evidenceCopySucceeded\)'
        $source | Should -Match 'Temporary fixture/report directory retained for manual cleanup or evidence recovery'
        $source | Should -Match 'cleanup-verification\.json'
    }

    It 'fails closed when live disposable-repository cleanup cannot prove HTTP 404 absence' {
        $harnessPath = Join-Path $repositoryRoot 'tests/e2e/Invoke-RecoveryEndToEndTests.ps1'
        $source = Get-Content -LiteralPath $harnessPath -Raw

        $source | Should -Match '\$expectedRepositoryIds\s*=\s*@\{\}'
        $source | Should -Match '\$createdRemote = Get-RecoveryE2eRemoteRepository -Repository \$fullName'
        $source | Should -Match '\$expectedRepositoryIds\[\$fullName\] = \[string\] \$createdRemote\.id'
        $source | Should -Match 'Refusing to delete.*without a recorded immutable test-created repository ID'
        $source | Should -Match '\$liveRepository = Get-RecoveryE2eRemoteRepository -Repository \$Repository'
        $source | Should -Match '\[string\] \$liveRepository\.id -ne \$expectedId'
        $source | Should -Match '\$expectedRepositoryIds\[\$happyArchive\] = \[string\] \$oldIdentity\.id'
        $source | Should -Match '\$expectedRepositoryIds\[\$happyDestination\] = \$replacementId'
        $source | Should -Match 'ExpectedRepositoryIds = \$expectedRepositoryIds'
        $source | Should -Match 'function Assert-RecoveryE2eRepositoryAbsent'
        $source | Should -Match 'gh api --include'
        $source | Should -Match 'if \(\$statusCodes\.Count -ne 1\)'
        $source | Should -Match 'if \(\$statusCodes\[0\] -ne 404\)'
        $source | Should -Match 'Remove-RecoveryE2eRepository -Repository \$repository -Confirm:\$false\s+Assert-RecoveryE2eRepositoryAbsent -Repository \$repository'
        $source | Should -Match 'CleanupVerified = -not \$KeepRepositories -and \$cleanupFailures\.Count -eq 0'
        $source | Should -Match 'if \(\$cleanupFailures\.Count -gt 0\)'
        $source | Should -Match 'Recovery E2E cleanup was not independently verified'
    }

    It 'records a primary error before cleanup and never deletes a registered name without an immutable ID' {
        $harnessPath = Join-Path $repositoryRoot 'tests/e2e/Invoke-RecoveryEndToEndTests.ps1'
        $source = Get-Content -LiteralPath $harnessPath -Raw

        # Captured migration errors and unexpected primary test failures survive
        # a later cleanup exception as persisted, copied JSON evidence.
        $source | Should -Match 'initial-migration-failure\.json'
        $source | Should -Match 'primary-failure\.json'
        $source | Should -Match 'Initial recovery E2E migration error \(before cleanup\)'
        $source | Should -Match 'Recovery E2E primary failure before cleanup'
        $source | Should -Match 'Copy-Item -LiteralPath \$report\.FullName -Destination \$evidenceRunPath -ErrorAction Stop'

        # Never attempt a deletion for a registered name without a recorded ID.
        # Authenticated HTTP 404, including the repo/delete_repo scopes, is the
        # only qualifying absence result in that branch.
        $source | Should -Match 'if \(-not \$expectedRepositoryIds\.ContainsKey\(\$repository\) -or'
        $source | Should -Match 'RegisteredNameWithoutIdentityVerifiedAbsent'
        $source | Should -Match 'DeletionAttempted = \$false'
        $source | Should -Match 'if \(\$scopeLines\.Count -ne 1\)'
        $source | Should -Match '\$scopes -notcontains ''repo'' -or \$scopes -notcontains ''delete_repo'''
        $source | Should -Match '(?s)if \(-not \$expectedRepositoryIds\.ContainsKey\(\$repository\).*?Assert-RecoveryE2eRepositoryAbsent -Repository \$repository.*?DeletionAttempted = \$false.*?VerifiedAbsent = \$true.*?continue'
        $source | Should -Match 'Remove-RecoveryE2eRepository -Repository \$repository -Confirm:\$false\s+Assert-RecoveryE2eRepositoryAbsent -Repository \$repository'
        $source | Should -Match 'Refusing to delete.*without a recorded immutable test-created repository ID'
    }

    It 'requires an explicit reason for deferred unsupported or constrained scenario classifications' {
        foreach ($entry in $script:traceability.Scenarios.GetEnumerator()) {
            if ($entry.Value.Classification -eq 'Required') {
                continue
            }

            [string]$entry.Value.Reason | Should -Not -BeNullOrEmpty
        }
    }

    It 'requires an explicit reason for constrained live validation' {
        foreach ($entry in $script:traceability.Scenarios.GetEnumerator()) {
            if ($entry.Value.LiveValidation -ne 'Constrained') {
                continue
            }

            [string]$entry.Value.LiveReason | Should -Not -BeNullOrEmpty
        }
    }
}
