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
