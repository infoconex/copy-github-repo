BeforeAll {
    $script:repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:governancePath = Join-Path $script:repositoryRoot 'docs/engineering/governance.md'
    $script:codeOwnersPath = Join-Path $script:repositoryRoot '.github/CODEOWNERS'
    $script:contributingPath = Join-Path $script:repositoryRoot 'CONTRIBUTING.md'
    $script:documentationStrategyPath = Join-Path $script:repositoryRoot 'docs/engineering/documentation-strategy.md'

    $script:governance = Get-Content -LiteralPath $script:governancePath -Raw
    $script:codeOwners = Get-Content -LiteralPath $script:codeOwnersPath -Raw
    $script:contributing = Get-Content -LiteralPath $script:contributingPath -Raw
    $script:documentationStrategy = Get-Content -LiteralPath $script:documentationStrategyPath -Raw
}

Describe 'Project governance and ownership documentation contract' {
    It 'states the actual single-primary-maintainer governance model without inventing independent approval' {
        $script:governance | Should -Match 'one primary maintainer'
        $script:governance | Should -Match 'infoconex'
        $script:governance | Should -Match 'do \*\*not\*\* prove.*independent review'
        $script:governance | Should -Match 'self-review.*does not create independent-review evidence'
    }

    It 'assigns ownership for the required decision areas' {
        foreach ($area in @(
            'Product scope and public behavior',
            'Public API compatibility',
            'Architecture',
            'Security policy and security architecture',
            'Documentation system',
            'Release readiness decision',
            'Release/publishing execution'
        )) {
            $script:governance | Should -Match ([regex]::Escape($area))
        }
    }

    It 'defines proposal paths for compatibility architecture and security-sensitive changes' {
        $script:governance | Should -Match 'Compatibility-sensitive or product-contract changes'
        $script:governance | Should -Match 'Architecture-significant decisions'
        $script:governance | Should -Match 'Security-sensitive decisions'
        $script:governance | Should -Match 'Use an ADR when a decision is durable, cross-cutting, difficult to reverse'
        $script:governance | Should -Match 'Vulnerabilities must follow the private reporting path in `SECURITY\.md`'
    }

    It 'defines maintainership transfer and future governance evolution' {
        $script:governance | Should -Match 'Maintainer and ownership changes'
        $script:governance | Should -Match 'update `\.github/CODEOWNERS`'
        $script:governance | Should -Match 'Future evolution'
        $script:governance | Should -Match 'multiple active maintainers with stable area ownership'
    }

    It 'uses CODEOWNERS for accurate current review routing without asserting separation of duties' {
        $script:codeOwners | Should -Match '(?m)^\* @infoconex\s*$'
        $script:codeOwners | Should -Match 'does not imply independent review or separation of duties'
        $script:governance | Should -Match 'repository-security-baseline\.md'
        $script:governance | Should -Match 'Whether code-owner review is required is a live repository-setting question'
    }

    It 'links governance from contributor and documentation authority entry points' {
        $script:contributing | Should -Match 'docs/engineering/governance\.md'
        $script:documentationStrategy | Should -Match 'docs/engineering/governance\.md'
    }
}
