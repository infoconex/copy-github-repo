BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:strategyPath = Join-Path $repositoryRoot 'docs/engineering/documentation-strategy.md'
    $script:navigationPath = Join-Path $repositoryRoot '_data/navigation.yml'
    $script:readmePath = Join-Path $repositoryRoot 'README.md'

    $script:strategy = Get-Content -LiteralPath $script:strategyPath -Raw
    $script:navigation = Get-Content -LiteralPath $script:navigationPath -Raw
    $script:readme = Get-Content -LiteralPath $script:readmePath -Raw
}

Describe 'Documentation strategy contract' {
    It 'defines the seven primary personas and keeps Industry Expert cross-cutting' {
        foreach ($persona in @(
                'User / Operator'
                'Contributor / Maintainer'
                'Quality Engineer'
                'Architect / Engineering Reviewer'
                'Security Reviewer'
                'Governance / Compliance Reviewer'
                'Product / Program Manager'
            )) {
            $script:strategy | Should -Match ([regex]::Escape($persona))
        }

        $script:strategy | Should -Match 'Industry Expert.*cross-cutting quality lens'
    }

    It 'defines progressive disclosure and anti-duplication guidance' {
        $script:strategy | Should -Match '## Progressive disclosure'
        $script:strategy | Should -Match '## Anti-duplication rules'
        $script:strategy | Should -Match 'one authoritative home'
        $script:strategy | Should -Match 'one detailed normative source per fact/contract'
    }

    It 'defines explicit authority for core documentation contracts' {
        $script:strategy | Should -Match '## Documentation authority map'
        $script:strategy | Should -Match '`docs/product/product-contract\.md`'
        $script:strategy | Should -Match '`docs/reference/commands/\*`'
        $script:strategy | Should -Match '`docs/product/architecture\.md`'
        $script:strategy | Should -Match '`CONTRIBUTING\.md`'
        $script:strategy | Should -Match '`SECURITY\.md`'
        $script:strategy | Should -Match '`docs/release/versioning\.md`'
        $script:strategy | Should -Match '`docs/release/publishing\.md`'
        $script:strategy | Should -Match '`LICENSE`'
    }

    It 'distinguishes implementation and evidence states' {
        foreach ($state in @(
                'Implemented'
                'Automatically tested'
                'E2E-capable'
                'Live-validated'
                'Documented'
                'Planned'
                'Unsupported / deferred'
            )) {
            $script:strategy | Should -Match ([regex]::Escape($state))
        }
    }

    It 'keeps documentation organized by topic with README landing pages' {
        $docsRoot = Join-Path $repositoryRoot 'docs'
        @(Get-ChildItem -LiteralPath $docsRoot -Filter '*.md' -File | Where-Object Name -NE 'README.md').Count | Should -Be 0

        foreach ($area in @('user', 'reference', 'product', 'engineering', 'security', 'release')) {
            Test-Path -LiteralPath (Join-Path $docsRoot "$area/README.md") -PathType Leaf | Should -BeTrue
        }
    }

    It 'exposes the strategy through README and site navigation' {
        $script:readme | Should -Match '\[Documentation strategy\]\(docs/engineering/documentation-strategy\.md\)'
        $script:navigation | Should -Match 'title: Documentation Strategy'
        $script:navigation | Should -Match 'path: docs/engineering/documentation-strategy\.md'
        $script:navigation | Should -Match 'title: Use the Product'
        $script:navigation | Should -Match 'title: Understand the Product'
        $script:navigation | Should -Match 'title: Engineering & Maintenance'
        $script:navigation | Should -Match 'title: Security & Assurance'
        $script:navigation | Should -Match 'title: Release & Operations'
    }
}
