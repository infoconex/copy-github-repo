BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:assurance = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/security/software-assurance.md') -Raw
    $script:strategy = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/engineering/documentation-strategy.md') -Raw
    $script:navigation = Get-Content -LiteralPath (Join-Path $repositoryRoot '_data/navigation.yml') -Raw
    $script:manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1')
}

Describe 'Software assurance review package documentation contract' {
    It 'is an evidence entry point rather than a compliance or organizational approval claim' {
        $script:assurance | Should -Match '(?m)^# Software assurance review package\r?$'
        $script:assurance | Should -Match 'evidence index and current-state summary'
        $script:assurance | Should -Match 'not a certification'
        $script:assurance | Should -Match 'does not claim regulatory compliance'
        $script:assurance | Should -Match 'organizational adoption approval remains the adopter''s decision'
        $script:assurance | Should -Match 'does not contain an approval checkbox'
    }

    It 'covers product identity supported scope and current stable release evidence state' {
        foreach ($term in @(
            'Copy GitHub Repository / CopyGitHubRepo',
            'PowerShell 7.4+',
            'GitHub.com only',
            'Snapshot',
            'FullHistory',
            'Exact release-candidate live evidence'
        )) {
            $script:assurance | Should -Match ([regex]::Escape($term))
        }

        $script:assurance | Should -Match '`0\.1\.0` is the initial stable release'
        $script:assurance | Should -Not -Match 'first stable release has not yet been published'

        foreach ($command in @(
            'Copy-GitHubRepository',
            'Get-GitHubRepository',
            'Start-CopyGitHubRepositoryWizard',
            'Test-GitHubRepositoryMigration'
        )) {
            $script:assurance | Should -Match ([regex]::Escape($command))
        }
    }

    It 'makes MIT licensing and redistribution boundaries auditable' {
        $script:assurance | Should -Match 'MIT License'
        $script:assurance | Should -Match '\(\.\./\.\./LICENSE\)'
        $script:assurance | Should -Match 'does \*\*not\*\* bundle PowerShell, Git, GitHub CLI, Git LFS, Pester, PSScriptAnalyzer, or GitHub Actions'
        $script:manifest.Copyright | Should -Be '(c) 2026 infoconex. Licensed under the MIT License.'
        $script:manifest.PrivateData.PSData.LicenseUri | Should -Match '/LICENSE$'
    }

    It 'separates shipped runtime external development CI and distribution dependencies' {
        foreach ($class in @(
            'Product payload',
            'Runtime PowerShell modules',
            'Runtime platform',
            'Runtime native prerequisite',
            'Conditional runtime prerequisite',
            'Development/test',
            'CI/release automation',
            'Distribution'
        )) {
            $script:assurance | Should -Match ([regex]::Escape($class))
        }
        $script:assurance | Should -Match 'Pester 6\.1\.0, PSScriptAnalyzer 1\.25\.0'
        $script:assurance | Should -Match 'No third-party PowerShell runtime module dependency currently shipped'
        $script:assurance | Should -Match 'release-sbom\.md'
        $script:assurance | Should -Match 'dependency-monitoring\.md'
    }

    It 'distinguishes runtime authority from maintainer and release permissions' {
        $script:assurance | Should -Match '## Runtime permissions and authority'
        $script:assurance | Should -Match '## Maintainer and release permissions'
        $script:assurance | Should -Match 'does not define a universal GitHub OAuth/PAT scope requirement'
        $script:assurance | Should -Match 'A normal operator does not need GitHub Actions release authority'
        $script:assurance | Should -Match 'id-token: write'
        $script:assurance | Should -Match 'attestations: write'
        $script:assurance | Should -Match 'Same-name replacement'
    }

    It 'documents network credentials sensitive data and artifact lifetime boundaries' {
        $script:assurance | Should -Match '## Network and external-service inventory'
        $script:assurance | Should -Match 'does \*\*not\*\* define an analytics/telemetry service'
        $script:assurance | Should -Match '## Credentials and sensitive-data handling'
        $script:assurance | Should -Match 'does not intentionally collect, display, copy, or persist token values'
        $script:assurance | Should -Match '## Local data, reports, and recovery artifacts'
        $script:assurance | Should -Match 'Persistent operator-controlled evidence'
        $script:assurance | Should -Match 'does not impose centralized retention or automatic deletion'
    }

    It 'links the security quality release and vulnerability authorities without overstating evidence' {
        foreach ($path in @(
            'security-architecture.md',
            '../engineering/quality-strategy.md',
            'repository-security-baseline.md',
            'release-sbom.md',
            'installation-security.md',
            '../../SECURITY.md',
            '../product/non-functional-requirements.md'
        )) {
            $script:assurance | Should -Match ([regex]::Escape($path))
        }
        $script:assurance | Should -Match 'not.*proof that the product is vulnerability-free'
        $script:assurance | Should -Match 'not comprehensive SAST'
        $script:assurance | Should -Match 'not constitute an independent security assessment'
    }

    It 'surfaces current residual risk and support lifecycle for approval' {
        $script:assurance | Should -Match 'GitHub artifact attestations are the selected v0\.1\.0 authenticity control'
        $script:assurance | Should -Match 'Authenticode publisher signing is not implemented'
        $script:assurance | Should -Match '../user/support-policy\.md'
        $script:assurance | Should -Match 'latest published stable module version is the supported line'
        $script:assurance | Should -Match 'incident-response\.md'
        $script:assurance | Should -Match 'exact release-candidate live evidence'
    }

    It 'is integrated as the governance reviewer entry point without becoming a competing authority' {
        $script:navigation | Should -Match 'title: Software Assurance Review'
        $script:navigation | Should -Match 'path: docs/security/software-assurance\.md'
        $script:strategy | Should -Match 'Governance / Compliance Reviewer.*software-assurance\.md'
        $script:strategy | Should -Match 'Organizational software-assurance review entry point / approval evidence index.*docs/security/software-assurance\.md'
        $script:strategy | Should -Match 'must not redefine their detailed contracts'
    }
}
