Describe 'Maintainer guide documentation contract' {
    It 'maps the major repository areas' {
        $documentPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'docs/engineering/maintainer-guide.md'
        $content = Get-Content -LiteralPath $documentPath -Raw
        foreach ($term in @('src/CopyGitHubRepo/Public/', 'src/CopyGitHubRepo/Private/', 'tests/e2e/', 'build/', '.github/workflows/', 'docs/', 'CHANGELOG.md')) {
            $content | Should -Match ([regex]::Escape($term))
        }
    }

    It 'defines a change impact matrix and Definition of Done' {
        $documentPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'docs/engineering/maintainer-guide.md'
        $content = Get-Content -LiteralPath $documentPath -Raw
        $content | Should -Match '## Change-impact matrix'
        $content | Should -Match '## Definition of Done'
        $content | Should -Match 'Public command/API'
        $content | Should -Match 'Safety or mutation behavior'
        $content | Should -Match 'Git/GitHub/native adapter'
        $content | Should -Match 'Documentation-only'
        $content | Should -Match 'Security-sensitive behavior'
    }

    It 'defines live E2E semantics without conflating capability and evidence' {
        $documentPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'docs/engineering/maintainer-guide.md'
        $content = Get-Content -LiteralPath $documentPath -Raw
        $content | Should -Match '## When live E2E is required'
        $content | Should -Match 'E2E-capable'
        $content | Should -Match 'live-validated'
        $content | Should -Match 'exact release-candidate commit'
    }

    It 'includes maintainer failure triage' {
        $documentPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'docs/engineering/maintainer-guide.md'
        $content = Get-Content -LiteralPath $documentPath -Raw
        foreach ($term in @('PSScriptAnalyzer failure', 'Test-taxonomy failure', 'Coverage failure', 'Documentation-contract failure', 'Package/release failure', 'Cross-platform failure', 'Live E2E failure')) {
            $content | Should -Match ([regex]::Escape($term))
        }
    }

    It 'links rather than redefines existing authorities' {
        $documentPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'docs/engineering/maintainer-guide.md'
        $content = Get-Content -LiteralPath $documentPath -Raw
        foreach ($path in @('documentation-strategy.md', 'engineering-principles.md', 'powershell-style-guide.md', 'source-code-documentation.md', 'product-contract.md', 'product-model.md', 'non-functional-requirements.md', 'troubleshooting-recovery.md', 'versioning.md', 'publishing.md')) {
            $content | Should -Match ([regex]::Escape($path))
        }
    }
}
