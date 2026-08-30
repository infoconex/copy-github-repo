BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:baseline = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/security/repository-security-baseline.md') -Raw
    $script:securityPolicy = Get-Content -LiteralPath (Join-Path $repositoryRoot 'SECURITY.md') -Raw
    $script:navigation = Get-Content -LiteralPath (Join-Path $repositoryRoot '_data/navigation.yml') -Raw
}

Describe 'Repository security baseline documentation contract' {
    It 'records verified live controls without inferring defaults' {
        $script:baseline | Should -Match 'A feature is never described as enabled merely because GitHub may enable it by default'
        $script:baseline | Should -Match 'Private vulnerability reporting.*Verified enabled'
        $script:baseline | Should -Match 'GitHub Actions CodeQL analysis.*Verified enabled'
    }

    It 'records the active main ruleset as owner verified' {
        $script:baseline | Should -Match 'Repository ruleset for `main`.*Owner verified'
        $script:baseline | Should -Match 'active branch ruleset named `main`'
        $script:baseline | Should -Match 'Owner verified.*repository owner inspected the live GitHub web UI'
        $script:securityPolicy | Should -Match 'active branch ruleset named `main` targeting\s+the default branch'
    }

    It 'keeps integration permission limits distinct from security state' {
        foreach ($term in @(
                'Dependabot alerts',
                'Dependabot security updates',
                'Secret scanning',
                'Push protection for secrets',
                'Code scanning alert state',
                'Default GitHub Actions workflow permissions'
            )) {
            $script:baseline | Should -Match ([regex]::Escape($term))
        }

        $script:baseline | Should -Match 'Live verification required'
        $script:baseline | Should -Match 'A permissions limitation in the verification integration is not evidence that a control is either enabled or disabled'
    }

    It 'defines the required owner-side hardening steps and status-check migration rule' {
        $script:baseline | Should -Match '## Required `main` ruleset'
        $script:baseline | Should -Match 'block branch deletion'
        $script:baseline | Should -Match 'block force pushes'
        $script:baseline | Should -Match 'require changes to arrive through a pull request'
        $script:baseline | Should -Match 'require required status checks before merge'
        $script:baseline | Should -Match 'Validate Project Quality'
        $script:baseline | Should -Match 'Analyze Code Security'
        $script:baseline | Should -Match 'Workflow and job names are part of the observable status-check surface'
        $script:baseline | Should -Match '## Advanced Security settings to verify'
        $script:baseline | Should -Match '## Code scanning review'
        $script:baseline | Should -Match '## GitHub Actions permissions'
    }

    It 'preserves separate GitHub Actions CodeQL and PowerShell-aware security coverage' {
        $script:baseline | Should -Match '\.github/workflows/analyze-github-actions-security\.yml'
        $script:baseline | Should -Match '\.github/workflows/analyze-code-security\.yml'
        $script:baseline | Should -Match 'PowerShell source is not represented as CodeQL-covered'
        $script:baseline | Should -Match 'PSScriptAnalyzerSecuritySettings\.psd1'
        $script:baseline | Should -Match 'targeted Pester safety/security behavior tests'
    }

    It 'is discoverable from security policy and site navigation' {
        $script:securityPolicy | Should -Match 'docs/security/repository-security-baseline\.md'
        $script:navigation | Should -Match 'docs/security/repository-security-baseline\.md'
    }
}
