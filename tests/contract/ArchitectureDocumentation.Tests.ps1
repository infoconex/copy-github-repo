BeforeAll {
    $script:repositoryRoot = Split-Path -Parent $PSScriptRoot
}

Describe 'Architecture documentation contract' {
    It 'includes context, physical mapping, execution and replacement diagrams' {
        $content = Get-Content -LiteralPath (Join-Path $script:repositoryRoot 'docs/product/architecture.md') -Raw
        foreach ($term in @('## System context and trust boundaries', '## Logical-to-physical map', '## Common execution flow', '## Replacement flow', '## Architecture fitness functions', '```mermaid')) {
            $content | Should -Match ([regex]::Escape($term))
        }
    }

    It 'reuses the canonical mutation recovery model rather than forking it' {
        $content = Get-Content -LiteralPath (Join-Path $script:repositoryRoot 'docs/product/architecture.md') -Raw
        $content | Should -Match 'troubleshooting-recovery\.md#mutation-and-recovery-state-model'
        $content | Should -Match 'canonical operator-facing mutation/recovery state model'
    }

    It 'publishes accepted ADRs with required decision sections' {
        $adrRoot = Join-Path $script:repositoryRoot 'docs/product/adr'
        $adrFiles = Get-ChildItem -LiteralPath $adrRoot -Filter 'ADR-*.md' -File
        $adrFiles.Count | Should -BeGreaterOrEqual 5
        foreach ($adr in $adrFiles) {
            $content = Get-Content -LiteralPath $adr.FullName -Raw
            foreach ($heading in @('Status: Accepted', '## Context', '## Decision', '## Alternatives and tradeoffs', '## Consequences')) {
                $content | Should -Match ([regex]::Escape($heading))
            }
        }
    }

    It 'records the durable safety decisions required by the architecture review' {
        $allAdrContent = (Get-ChildItem -LiteralPath (Join-Path $script:repositoryRoot 'docs/product/adr') -Filter '*.md' -File | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
        foreach ($term in @('Snapshot is the default', 'immutable approved source state', 'fails closed', 'preserve', 'auto-rolling back', 'shared application', 'no shell evaluation', 'protection restoration', 'github.com')) {
            $allAdrContent | Should -Match ([regex]::Escape($term))
        }
    }
}
