BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $documentPath = Join-Path $repositoryRoot 'docs/product/non-functional-requirements.md'
    $script:document = Get-Content -LiteralPath $documentPath -Raw
}

Describe 'Non-functional requirements documentation contract' {
    It 'defines explicit status vocabulary without inventing an SLA' {
        foreach ($term in @('Implemented', 'Automatically tested', 'Characterized', 'Accepted limitation', 'Unsupported')) {
            $script:document | Should -Match ([regex]::Escape($term))
        }
        $script:document | Should -Match 'does \*\*not\*\* promise a fixed completion time'
    }

    It 'covers the required operational dimensions' {
        foreach ($term in @(
            'repository-size',
            'branch/tag',
            'Git LFS',
            'Disk/temp',
            'Memory',
            'pagination',
            'rate limiting',
            'Native process timeout',
            'Concurrency',
            'Retry/idempotency',
            'Process interruption'
        )) {
            $script:document | Should -Match ([regex]::Escape($term))
        }
    }

    It 'documents preservation-first partial failure behavior' {
        $script:document | Should -Match 'before GitHub mutation'
        $script:document | Should -Match 'after GitHub mutation begins'
        $script:document | Should -Match 'Do not simply repeat the original command'
        $script:document | Should -Match 'does not claim distributed locking'
        $script:document | Should -Match 'does \*\*not\*\* imply rollback'
    }

    It 'records the durable resilience controls and accepted limitations directly' {
        foreach ($term in @(
            'InfiniteTimeSpan',
            'no hard repository-size',
            'known lower-bound disk shortage',
            'mutations are never automatically replayed',
            'raw Ctrl\+C',
            'no distributed lock'
        )) {
            $script:document | Should -Match $term
        }
    }

    It 'links to canonical product recovery characterization and readiness authorities' {
        foreach ($path in @(
            'product-contract.md',
            'user-guide.md',
            'troubleshooting-recovery.md',
            'product-model.md',
            'architecture.md',
            'scale-characterization.md',
            'release-readiness.md'
        )) {
            $script:document | Should -Match ([regex]::Escape($path))
        }
    }
}
