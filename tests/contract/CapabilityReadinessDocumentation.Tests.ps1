BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:readinessPath = Join-Path $repositoryRoot 'docs/release/release-readiness.md'
    $script:productModelPath = Join-Path $repositoryRoot 'docs/product/product-model.md'
    $script:governancePath = Join-Path $repositoryRoot 'docs/engineering/governance.md'
    $script:navigationPath = Join-Path $repositoryRoot '_data/navigation.yml'
    $script:strategyPath = Join-Path $repositoryRoot 'docs/engineering/documentation-strategy.md'

    $script:readiness = Get-Content -LiteralPath $script:readinessPath -Raw
    $script:productModel = Get-Content -LiteralPath $script:productModelPath -Raw
    $script:governance = Get-Content -LiteralPath $script:governancePath -Raw
    $script:navigation = Get-Content -LiteralPath $script:navigationPath -Raw
    $script:strategy = Get-Content -LiteralPath $script:strategyPath -Raw
}

Describe 'Capability release readiness documentation contract' {
    It 'uses the canonical capability IDs from the product model' {
        $capabilityIds = @(
            'CAP-DISC', 'CAP-PLAN', 'CAP-SNAP', 'CAP-HIST', 'CAP-DEST',
            'CAP-SAME', 'CAP-LFS', 'CAP-SET', 'CAP-PROT', 'CAP-WIZ',
            'CAP-AUTO', 'CAP-VERIFY', 'CAP-EVID', 'CAP-DIST', 'CAP-REL'
        )

        foreach ($capabilityId in $capabilityIds) {
            $script:productModel | Should -Match ([regex]::Escape("``$capabilityId``"))
            $script:readiness | Should -Match ([regex]::Escape("``$capabilityId``")) -Because "$capabilityId must be represented in the v0.1.0 readiness scope"
        }
    }

    It 'keeps scope and evidence/readiness semantics explicit' {
        foreach ($term in @(
            'Required', 'Optional', 'Deferred', 'Unsupported',
            'Not started', 'Implemented', 'Automatically tested', 'E2E-capable',
            'Live-validated for RC', 'Documented', 'Blocked', 'Accepted limitation',
            'Release-ready', 'Deferred / not in scope'
        )) {
            $script:readiness | Should -Match ([regex]::Escape($term))
        }

        $script:readiness | Should -Match 'planning baseline, not a go/no-go record'
        $script:readiness | Should -Match 'mutable `main`-branch matrix is planning evidence only'
    }

    It 'binds a go/no-go decision to one exact immutable release candidate' {
        foreach ($field in @(
            'Version', 'Candidate commit', 'Candidate tag', 'Artifact identity', 'Decision',
            'Decision timestamp', 'Decision authority', 'Quality Gate evidence',
            'Required live E2E evidence', 'Security/readiness disposition',
            'Non-functional disposition', 'Known limitations', 'Publication prerequisites', 'Final result'
        )) {
            $script:readiness | Should -Match ([regex]::Escape($field))
        }

        $script:readiness | Should -Match 'Exact 40-character commit SHA'
        $script:readiness | Should -Match 'A later commit requires a new readiness review'
        $script:readiness | Should -Match '`GO`, `NO-GO`, or `PENDING`'
    }

    It 'makes current cross-cutting readiness concerns visible without issue-number dependencies' {
        foreach ($term in @(
            'Repository security baseline',
            'Independent publisher signing',
            'Non-functional resilience controls',
            'Product scenario traceability',
            'Release/deployment runbook',
            'Repository-hosted installation rehearsal',
            'Clean Snapshot qualification',
            'Exact release-candidate evidence'
        )) {
            $script:readiness | Should -Match ([regex]::Escape($term))
        }

        $script:readiness | Should -Match 'planning or tracking artifact is not automatically a release blocker'
        $script:readiness | Should -Match 'undispositioned release blocker'
    }

    It 'records explicit v0.1.0 non-functional dispositions by control rather than tracking number' {
        foreach ($term in @(
            'Native child-process timeout/cancellation',
            'GitHub API throttling/transient retry',
            'Large-repository/resource characterization',
            'Local disk/temp resource preflight',
            'Repeated-invocation retry/idempotency',
            'Cross-platform interruption/signal handling'
        )) {
            $script:readiness | Should -Match ([regex]::Escape($term))
        }

        $script:readiness | Should -Match 'InfiniteTimeSpan'
        $script:readiness | Should -Match 'no supported hard maximum'
        $script:readiness | Should -Match 'raw Ctrl\+C'
        $script:readiness | Should -Match 'Not a release blocker'
    }

    It 'requires complete release-specific accepted-limitation evidence' {
        foreach ($term in @(
            'exact release candidate commit/tag/artifact identity',
            'affected capability/use case/scenario',
            'why release is still acceptable',
            'residual risk',
            'compensating control or evidence',
            'current decision authority',
            'durable follow-up requirement/reference',
            'effect on support/security/release messaging'
        )) {
            $script:readiness | Should -Match ([regex]::Escape($term))
        }

        $script:readiness | Should -Match 'Do not convert it into an exception simply to obtain a `GO` result'
    }

    It 'defines the clean Snapshot as a release qualification boundary' {
        $script:readiness | Should -Match 'Clean Snapshot release boundary'
        $script:readiness | Should -Match 'unrelated clean root commit'
        $script:readiness | Should -Match 'historical repository must not be used as the source of the first stable tag'
        $script:readiness | Should -Match 'create `v0\.1\.0` only on that clean replacement commit'
    }

    It 'aligns decision authority with governance without claiming independent review' {
        $script:governance | Should -Match 'Release readiness decision'
        $script:readiness | Should -Match '\[`governance\.md`\]\(\.\./engineering/governance\.md\)'
        $script:readiness | Should -Match 'does not create independent review evidence'
    }

    It 'is exposed through documentation strategy and site navigation' {
        $script:strategy | Should -Match '`docs/release/release-readiness\.md`'
        $script:navigation | Should -Match 'title: Release Readiness'
        $script:navigation | Should -Match 'path: docs/release/release-readiness\.md'
    }
}
