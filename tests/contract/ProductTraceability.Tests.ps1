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

    It 'requires an existing E2E harness for scenarios whose live validation is required' {
        foreach ($entry in $script:traceability.Scenarios.GetEnumerator()) {
            if ($entry.Value.LiveValidation -ne 'Required') {
                continue
            }

            @($entry.Value.LiveEvidence).Count | Should -BeGreaterThan 0 -Because "$($entry.Key) requires live validation"
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

    It 'ties existing-destination recovery live mappings to asserted scenario output, not just a named file' {
        $harnessPath = 'tests/e2e/Invoke-RecoveryEndToEndTests.ps1'
        $source = Get-Content -LiteralPath (Join-Path $repositoryRoot $harnessPath) -Raw

        foreach ($scenarioId in @('SCN-DEST-HAPPY-01', 'SCN-DEST-PARTIAL-01', 'SCN-RETRY-RESILIENCE-02')) {
            $scenario = $script:traceability.Scenarios[$scenarioId]
            $scenario.LiveValidation | Should -Be 'Required'
            @($scenario.LiveEvidence) | Should -Contain $harnessPath
            $marker = "ScenarioId\s*=\s*'$scenarioId'"
            ([regex]::Matches($source, $marker)).Count | Should -Be 1 -Because "$scenarioId must emit a scenario-specific result after verification"
        }

        $source | Should -Match 'Get-RecoveryE2eRemoteRepository'
        $source | Should -Match 'Get-RecoveryE2eRemoteCommit'
        $source | Should -Match 'ExistingDestinationArchiveName\s+\$happyArchiveName'
        $source | Should -Match 'ExistingDestinationConfirmation\s+\$confirmation'
        $source | Should -Match 'ExistingDestinationArchiveName\s+\$partialArchiveName'
        $source | Should -Match 'ExistingDestinationConfirmation\s+\$partialConfirmation'
        $source | Should -Match 'ArchivedOriginalIdentityPreserved'
        $source | Should -Match 'AutomaticRollbackAttempted'
        $source | Should -Match 'ExistingDestinationArchiveAlreadyExists'
        $source | Should -Match 'IndependentVerificationSucceeded'
        $source | Should -Match 'Assert-RecoveryE2eCleanupCapability'
        $source | Should -Match 'Remove-RecoveryE2eRepository'

        # No successful settings-failure live scenario is claimed. That separate
        # Required-live fixture is still pending, not covered by these three cases.
        $source | Should -Not -Match "ScenarioId\s*=\s*'SCN-SET-PARTIAL-01'"
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
        $source | Should -Match '\$expectedRepositoryIds\[\$partialArchive\] = \[string\] \$priorIdentity\.id'
        $source | Should -Match '\$expectedRepositoryIds\[\$partialDestination\] = \$partialReplacementId'
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
