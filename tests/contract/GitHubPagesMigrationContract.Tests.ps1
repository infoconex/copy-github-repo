BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $contractPath = Join-Path $repoRoot 'docs/product/github-pages-migration-contract.md'
    $script:contract = Get-Content -LiteralPath $contractPath -Raw
}

Describe 'GitHub Pages migration product contract' {
    It 'distinguishes copied repository content from GitHub-side Pages state' {
        $script:contract | Should -Match 'Git content is not GitHub Pages state'
        $script:contract | Should -Match 'successful Pages workflow run.*not proof'
        $script:contract | Should -Match 'Plain migrations without `-RestorePages`.*do not gain an implicit guarantee'
    }

    It 'defines Actions-based and branch-path Pages as distinct modes' {
        $script:contract | Should -Match 'For Actions-based Pages.*publishing mode is `workflow`'
        $script:contract | Should -Match 'For branch/path-based Pages.*publishing branch'
        $script:contract | Should -Match 'must not silently substitute a branch/path build mode'
        $script:contract | Should -Match 'must not invent a missing source publishing branch'
    }

    It 'classifies transferable and external Pages state explicitly' {
        $script:contract | Should -Match 'Custom domain \(`cname`\)'
        $script:contract | Should -Match 'HTTPS enforcement intent'
        $script:contract | Should -Match 'Certificate state/readiness.*Externally dependent'
        $script:contract | Should -Match 'DNS records.*External and unsupported for mutation'
        $script:contract | Should -Match 'Secrets, tokens, environment secrets.*Unsupported/sensitive'
    }

    It 'defines fail-closed replacement custom-domain ownership handoff' {
        $script:contract | Should -Match 'preserve and verify archive repository identity before any archive-side Pages mutation'
        $script:contract | Should -Match 'fail closed before releasing a domain'
        $script:contract | Should -Match 'never leave archive and replacement independently claiming the same production custom domain'
        $script:contract | Should -Match 'do not perform destructive automatic rollback'
    }

    It 'defines Pages ordering after content verification and before final protection restoration' {
        $script:contract | Should -Match 'verify destination Git/LFS content against approved evidence'
        $script:contract | Should -Match 'revalidate the reviewed Pages evidence immediately before Pages mutation'
        $script:contract | Should -Match 'restore supported destination Pages configuration from reviewed evidence'
        $script:contract | Should -Match 'restore transferable repository/branch protection last'
        $script:contract | Should -Match 'Pages restoration never precedes successful content verification'
    }

    It 'preserves immutable reviewed evidence and independent verification boundaries' {
        $script:contract | Should -Match 'planning must capture immutable reviewed Pages evidence'
        $script:contract | Should -Match 'consume that reviewed evidence rather than rerun mutable source selection/discovery as authority'
        $script:contract | Should -Match 'Pages verification is read-only and independent from restoration logic'
        $script:contract | Should -Match 'DNS records, account/organization domain verification, certificate issuance/propagation.*reported separately'
    }

    It 'records evidence for current implicit Actions-based Pages behavior' {
        $script:contract | Should -Match '33456980366'
        $script:contract | Should -Match 'Configure GitHub Pages'
        $script:contract | Should -Match 'Deploy to GitHub Pages'
        $script:contract | Should -Match 'implicit-activation risk, not successful Pages migration'
    }

    It 'keeps contract-only scope and retains the existing public switch' {
        $script:contract | Should -Match 'does not implement Pages restoration'
        $script:contract | Should -Match 'existing `-RestorePages` switch remains intentional and opt-in'
        $script:contract | Should -Match 'does not implement Pages restoration, general GitHub Actions restoration, external DNS changes'
    }
}
