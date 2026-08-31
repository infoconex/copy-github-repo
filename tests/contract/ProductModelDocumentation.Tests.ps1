BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modelPath = Join-Path $repositoryRoot 'docs/product/product-model.md'
    $script:model = Get-Content -LiteralPath $script:modelPath -Raw
    $script:navigation = Get-Content -LiteralPath (Join-Path $repositoryRoot '_data/navigation.yml') -Raw
}

Describe 'Product journey and behavioral model documentation' {
    It 'defines the full product traceability chain without replacing the product contract' {
        $script:model | Should -Match 'Persona -> Journey -> Capability -> Use Case -> Product Requirement -> Acceptance Criteria -> Behavioral Scenario -> Automated Test -> Live Validation -> Release Evidence'
        $script:model | Should -Match 'does \*\*not\*\* redefine product behavior'
        $script:model | Should -Match '`docs/product/product-contract\.md` remains authoritative|product-contract\.md.*remains authoritative'
    }

    It 'defines explicit product intent goals non-goals and evidence-based success criteria' {
        foreach ($heading in @(
                '## Product intent'
                '### Problem'
                '### Intended outcome'
                '### Goals'
                '### Non-goals'
                '### Evidence-based release success criteria'
            )) {
            $script:model | Should -Match ([regex]::Escape($heading))
        }
    }

    It 'maps all seven primary personas to journeys' {
        foreach ($persona in @(
                'User / Operator'
                'Contributor / Maintainer'
                'Quality Engineer'
                'Architect / Engineering Reviewer'
                'Security Reviewer'
                'Governance / Compliance Reviewer'
                'Product / Program Manager'
            )) {
            $script:model | Should -Match ([regex]::Escape($persona))
        }
    }

    It 'defines stable capability use-case and scenario identifiers' {
        foreach ($id in @(
                'CAP-DISC', 'CAP-PLAN', 'CAP-SNAP', 'CAP-HIST', 'CAP-GHREL', 'CAP-DEST', 'CAP-SAME',
                'CAP-LFS', 'CAP-SET', 'CAP-PROT', 'CAP-WIZ', 'CAP-AUTO', 'CAP-VERIFY',
                'CAP-EVID', 'CAP-DIST', 'CAP-REL',
                'UC-SNAP-NEW', 'UC-HIST-NEW', 'UC-HIST-REL', 'UC-DEST-REPLACE', 'UC-SAME-REPLACE',
                'UC-WIZ-01', 'UC-AUTO-01', 'UC-RECOVER-01',
                'SCN-SNAP-HAPPY-01', 'SCN-SNAP-VERIFY-01', 'SCN-HIST-HAPPY-01',
                'SCN-GHREL-HAPPY-01', 'SCN-GHREL-SAFETY-01', 'SCN-GHREL-VERIFY-01', 'SCN-GHREL-PARTIAL-01',
                'SCN-DEST-SAFETY-01', 'SCN-DEST-PARTIAL-01', 'SCN-SAME-SAFETY-01',
                'SCN-WIZ-NOOP-01', 'SCN-RECOVER-RECOVERY-01',
                'SCN-API-RESILIENCE-01', 'SCN-NATIVE-RESILIENCE-01',
                'SCN-RESOURCE-RESILIENCE-01', 'SCN-RETRY-RESILIENCE-01',
                'SCN-RETRY-RESILIENCE-02', 'SCN-SCALE-RESILIENCE-01',
                'SCN-INTERRUPT-RESILIENCE-01'
            )) {
            $script:model | Should -Match ([regex]::Escape($id))
        }
    }

    It 'covers successful failing no-op partial mutation recovery automation and resilience behavior' {
        foreach ($category in @('HAPPY', 'VALIDATION', 'AUTH', 'SAFETY', 'EDGE', 'PARTIAL', 'VERIFY', 'RECOVERY', 'NOOP', 'AUTOMATION', 'RESILIENCE')) {
            $script:model | Should -Match ([regex]::Escape($category))
        }

        $script:model | Should -Match 'may already exist and contain published content'
        $script:model | Should -Match 'does not automatically rename back or delete repositories'
        $script:model | Should -Match 'non-interactive'
        $script:model | Should -Match 'Mutation boundary'
        $script:model | Should -Match 'Safe retry / recovery'
        $script:model | Should -Match 'Automated / live evidence'
    }

    It 'keeps live validation distinct from E2E capability and delegates evidence mapping to the quality strategy' {
        $script:model | Should -Match 'E2E harness existing is not the same'
        $script:model | Should -Match 'quality-strategy\.md.*owns the formal requirement/scenario-to-test/evidence mapping'
        $script:model | Should -Match 'actual live-validation evidence for the exact release candidate'
    }

    It 'is discoverable through the product navigation' {
        $script:navigation | Should -Match 'title: Product Journeys & Behavior'
        $script:navigation | Should -Match 'path: docs/product/product-model\.md'
    }
}
