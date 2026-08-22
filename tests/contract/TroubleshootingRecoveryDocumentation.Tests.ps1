BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:guidePath = Join-Path $repositoryRoot 'docs/user/troubleshooting-recovery.md'
    $script:guide = Get-Content -LiteralPath $script:guidePath -Raw
    $script:navigation = Get-Content -LiteralPath (Join-Path $repositoryRoot '_data/navigation.yml') -Raw
    $script:strategy = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/engineering/documentation-strategy.md') -Raw
}

Describe 'Troubleshooting and recovery documentation' {
    It 'distinguishes pre-mutation from post-mutation failures' {
        $script:guide | Should -Match 'could GitHub state already have changed'
        $script:guide | Should -Match 'Before the first mutation'
        $script:guide | Should -Match 'partial-mutation state'
        $script:guide | Should -Match 'preservation over automatic rollback'
    }

    It 'defines the shared mutation and recovery state model' {
        $script:guide | Should -Match '## Mutation and recovery state model'
        $script:guide | Should -Match 'flowchart TD'
        $script:guide | Should -Match 'Archive existing/source repository'
        $script:guide | Should -Match 'Verify content'
        $script:guide | Should -Match 'Restore ordinary settings'
        $script:guide | Should -Match 'Restore transferable protection'
        $script:guide | Should -Match 'Preserve known repositories and write recovery evidence'
    }

    It 'covers required symptom-oriented troubleshooting areas' {
        foreach ($text in @(
            'GitHub CLI is not authenticated'
            'host is rejected'
            'SourceStateChangedSincePlanning'
            'destination already exists'
            'archive name is already in use'
            'Exact replacement confirmation is rejected'
            'Git or Git LFS fails before publication'
            'Content publication or push fails'
            'Content verification fails'
            'Ordinary settings restoration fails'
            'Protection restoration is skipped or fails'
            'wizard cancels or returns to planning'
            'Report or recovery-evidence output cannot be written'
        )) {
            $script:guide | Should -Match ([regex]::Escape($text))
        }
    }

    It 'documents safe recovery and defect reporting' {
        $script:guide | Should -Match '## Recovery after an archive/replacement partial failure'
        $script:guide | Should -Match 'Do not delete anything'
        $script:guide | Should -Match '## Evidence to preserve'
        $script:guide | Should -Match '## Reporting a defect safely'
        $script:guide | Should -Match 'Do \*\*not\*\* include'
        $script:guide | Should -Match 'GitHub tokens'
        $script:guide | Should -Match 'secret values'
    }

    It 'reuses the canonical scenario taxonomy' {
        foreach ($id in @(
            'SCN-PLAN-SAFETY-01'
            'SCN-DEST-SAFETY-01'
            'SCN-DEST-PARTIAL-01'
            'SCN-SAME-SAFETY-01'
            'SCN-SNAP-VERIFY-01'
            'SCN-HIST-VERIFY-01'
            'SCN-SET-PARTIAL-01'
            'SCN-WIZ-NOOP-01'
            'SCN-RECOVER-RECOVERY-01'
        )) {
            $script:guide | Should -Match ([regex]::Escape($id))
        }
    }

    It 'is authoritative and discoverable' {
        $script:strategy | Should -Match '`docs/user/troubleshooting-recovery\.md`'
        $script:navigation | Should -Match 'title: Troubleshooting & Recovery'
        $script:navigation | Should -Match 'path: docs/user/troubleshooting-recovery\.md'
    }
}
