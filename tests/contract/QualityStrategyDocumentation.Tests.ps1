BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:qualityStrategyPath = Join-Path $repositoryRoot 'docs/engineering/quality-strategy.md'
}

Describe 'Quality strategy documentation contract' {
    It 'defines the complete test taxonomy and evidence states' {
        $content = Get-Content -LiteralPath $script:qualityStrategyPath -Raw
        foreach ($term in @('Unit', 'Integration', 'Contract', 'EndToEnd', 'E2E-capable', 'Live-validated', 'Release-validated', 'Constrained', 'Gap')) {
            $content | Should -Match ([regex]::Escape($term))
        }
    }

    It 'links product traceability IDs to automated and live evidence' {
        $content = Get-Content -LiteralPath $script:qualityStrategyPath -Raw
        foreach ($term in @(
            'CAP-PLAN', 'CAP-SNAP', 'CAP-HIST', 'CAP-DEST', 'CAP-SAME', 'CAP-LFS',
            'CAP-SET', 'CAP-PROT', 'CAP-WIZ', 'CAP-VERIFY', 'CAP-EVID', 'CAP-DIST', 'CAP-REL',
            'SCN-API-RESILIENCE-01', 'SCN-NATIVE-RESILIENCE-01', 'SCN-RESOURCE-RESILIENCE-01',
            'SCN-RETRY-RESILIENCE-01', 'SCN-RETRY-RESILIENCE-02', 'SCN-SCALE-RESILIENCE-01',
            'SCN-INTERRUPT-RESILIENCE-01'
        )) {
            $content | Should -Match ([regex]::Escape($term))
        }
    }

    It 'maps resilience scenarios to concrete automated or characterization evidence' {
        $content = Get-Content -LiteralPath $script:qualityStrategyPath -Raw
        foreach ($term in @(
            'GitHubApiAdapters.Tests.ps1', 'NativeCommandStreams.Tests.ps1', 'LocalResourcePreflight.Tests.ps1',
            'InterruptionContract.Tests.ps1', 'SnapshotPagination.Tests.ps1', 'scale characterization'
        )) {
            $content | Should -Match ([regex]::Escape($term))
        }
    }

    It 'keeps v0.1.0 live-run claims bound to immutable release evidence' {
        $content = Get-Content -LiteralPath $script:qualityStrategyPath -Raw
        $content | Should -Match 'immutable `v0\.1\.0` qualification evidence'
        $content | Should -Match 'does not independently enumerate exact live runs'
        $content | Should -Not -Match 'Not yet recorded for v0\.1\.0 release candidate'
        $content | Should -Match '`v0\.1\.0` publication, package discovery/install/import, release assets, checksum, SBOM, and attestations were completed and verified'
    }

    It 'defines decision-oriented release evidence fields' {
        $content = Get-Content -LiteralPath $script:qualityStrategyPath -Raw
        foreach ($term in @('Commit SHA', 'Version / tag', 'Validation date', 'Automated evidence', 'Live scenarios', 'Environment', 'Known exclusions', 'Accepted risk / blocker', 'Evidence links')) {
            $content | Should -Match ([regex]::Escape($term))
        }
    }

    It 'treats coverage as a regression floor rather than completeness' {
        $content = Get-Content -LiteralPath $script:qualityStrategyPath -Raw
        $content | Should -Match '65% Pester instruction-coverage floor'
        $content | Should -Match 'regression guard'
        $content | Should -Match 'not a claim'
    }

    It 'links canonical product non-functional and maintainer authorities' {
        $content = Get-Content -LiteralPath $script:qualityStrategyPath -Raw
        foreach ($path in @('product-contract.md', 'product-model.md', 'non-functional-requirements.md', 'maintainer-guide.md')) {
            $content | Should -Match ([regex]::Escape($path))
        }
    }
}
