BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:securityArchitecture = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/security/security-architecture.md') -Raw
    $script:releaseSbom = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/security/release-sbom.md') -Raw
    $script:securityPolicy = Get-Content -LiteralPath (Join-Path $repositoryRoot 'SECURITY.md') -Raw
    $script:navigation = Get-Content -LiteralPath (Join-Path $repositoryRoot '_data/navigation.yml') -Raw
    $script:documentationStrategy = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/engineering/documentation-strategy.md') -Raw
}

Describe 'Security architecture documentation contract' {
    It 'defines protected assets actors trust boundaries and privileged operations' {
        foreach ($heading in @(
                '## Protected assets',
                '## Actors and trust assumptions',
                '## Trust boundaries and sensitive-data flow',
                '## Privileged and destructive operations'
            )) {
            $script:securityArchitecture | Should -Match ([regex]::Escape($heading))
        }
    }

    It 'addresses the required threat classes and recovery semantics' {
        foreach ($term in @(
                'Shell/command injection',
                'Stale-state substitution / TOCTOU',
                'Destination overwrite / destructive confusion',
                'Credential leakage',
                'Partial mutation',
                'Release artifact substitution',
                'Dependency/workflow compromise'
            )) {
            $script:securityArchitecture | Should -Match ([regex]::Escape($term))
        }
        $script:securityArchitecture | Should -Match 'does not automatically delete repositories or rename archives back'
    }

    It 'makes credential diagnostic privacy and telemetry boundaries explicit' {
        $script:securityArchitecture | Should -Match 'does not intentionally collect, display, copy, or persist token values'
        $script:securityArchitecture | Should -Match 'must not be written intentionally to console output, reports, diagnostics, or CI artifacts'
        $script:securityArchitecture | Should -Match 'does not define a telemetry/analytics subsystem'
    }

    It 'distinguishes implemented verified platform planned and residual-risk states' {
        foreach ($status in @(
                'Implemented',
                'Automatically verified',
                'Platform-provided / live verification required',
                'Planned / open',
                'Residual risk'
            )) {
            $script:securityArchitecture | Should -Match ([regex]::Escape($status))
        }
    }

    It 'tracks current completed and remaining hardening controls directly' {
        $script:securityArchitecture | Should -Match 'PSScriptAnalyzer 1\.25\.0'
        $script:securityArchitecture | Should -Match 'Pester 6\.1\.0'
        $script:securityArchitecture | Should -Match 'Measure-CgrSecurity'
        $script:securityArchitecture | Should -Match 'PSScriptAnalyzerSecurityRules\.Tests\.ps1'
        $script:securityArchitecture | Should -Match 'CodeQL.*GitHub Actions'
        $script:securityArchitecture | Should -Match 'language `actions`'
        $script:securityArchitecture | Should -Match 'does not analyze the project''s PowerShell source'
        $script:securityArchitecture | Should -Match 'dependency-monitoring\.md'
        $script:securityArchitecture | Should -Match 'required v0\.1\.0 baseline restored and verified during release qualification'
        $script:securityArchitecture | Should -Match 'Independent release authenticity/signing'
        $script:securityArchitecture | Should -Match 'Implemented for v0\.1\.0 with GitHub artifact attestations'
        $script:securityArchitecture | Should -Match 'Authenticode publisher signing remains optional/not implemented'
        $script:securityArchitecture | Should -Match 'New-ReleaseSbom\.ps1'
        $script:securityArchitecture | Should -Match 'release-sbom\.md'
        $script:securityArchitecture | Should -Match 'SPDX 2\.3 JSON'
        $script:securityArchitecture | Should -Match 'SBOM attestation'
        $script:securityArchitecture | Should -Match 'PSGallery trust-policy preservation'
        $script:securityArchitecture | Should -Match 'Implemented \+ automatically verified'
    }

    It 'keeps the security architecture aligned with the release SBOM evidence contract' {
        $script:releaseSbom | Should -Match 'SPDX 2\.3 JSON'
        $script:releaseSbom | Should -Match 'GitHub SBOM attestation'
        $script:releaseSbom | Should -Match 'Independent publisher signing remains a separate optional control'
        $script:securityArchitecture | Should -Match '\[`release-sbom\.md`\]\(release-sbom\.md\)'
        $script:securityArchitecture | Should -Match 'GitHub artifact attestation is the selected independent release-authenticity mechanism'
        $script:securityArchitecture | Should -Match 'not Authenticode publisher signing'
    }

    It 'documents how to run the focused security static-analysis policy locally' {
        $script:securityArchitecture | Should -Match '## Security static-analysis policy'
        $script:securityArchitecture | Should -Match '\./build/Test-Project\.ps1'
        $script:securityArchitecture | Should -Match '\./build/Test-Project\.ps1 -Category Contract'
        $script:securityArchitecture | Should -Match 'high-confidence patterns'
    }

    It 'states static-analysis and release-evidence limitations honestly' {
        $script:securityArchitecture | Should -Match 'not comprehensive SAST'
        $script:securityArchitecture | Should -Match 'not proof that the software is vulnerability-free'
        $script:securityArchitecture | Should -Match 'E2E-capable also does not mean a specific release candidate was live-validated'
        $script:securityArchitecture | Should -Match 'checksum alone does not authenticate publisher'
        $script:securityArchitecture | Should -Match 'does not prove vulnerability absence'
    }

    It 'is discoverable from the security policy navigation and authority map' {
        $script:securityPolicy | Should -Match 'docs/security/security-architecture\.md'
        $script:navigation | Should -Match 'docs/security/security-architecture\.md'
        $script:documentationStrategy | Should -Match '\| Security architecture, threats, controls, credential/data flow, residual risk \| `docs/security/security-architecture\.md` \|'
    }
}
