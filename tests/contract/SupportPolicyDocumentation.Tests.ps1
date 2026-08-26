BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:supportPolicy = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/user/support-policy.md') -Raw
    $script:securityPolicy = Get-Content -LiteralPath (Join-Path $repositoryRoot 'SECURITY.md') -Raw
    $script:versioning = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/release/versioning.md') -Raw
    $script:hostSupport = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/user/host-support.md') -Raw
    $script:assurance = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/security/software-assurance.md') -Raw
    $script:strategy = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/engineering/documentation-strategy.md') -Raw
    $script:navigation = Get-Content -LiteralPath (Join-Path $repositoryRoot '_data/navigation.yml') -Raw
    $script:readme = Get-Content -LiteralPath (Join-Path $repositoryRoot 'README.md') -Raw
    $script:manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1')
}

Describe 'Support compatibility and deprecation policy documentation contract' {
    It 'defines a conservative current support line without inventing LTS commitments' {
        $script:supportPolicy | Should -Match '^# Support, compatibility, and deprecation policy'
        $script:supportPolicy | Should -Match 'Version `0\.1\.0` is the initial stable release'
        $script:supportPolicy | Should -Match 'latest published stable version'
        $script:supportPolicy | Should -Match 'older stable versions are not maintained as parallel supported branches'
        $script:supportPolicy | Should -Match 'Long-term-support branches \| None currently defined'
        $script:supportPolicy | Should -Match 'does not currently promise a fixed calendar support duration'
        $script:supportPolicy | Should -Not -Match 'has not yet published its first stable release'
    }

    It 'keeps security-fix support aligned with the supported version policy' {
        $script:supportPolicy | Should -Match 'Security fixes target the latest supported stable version'
        $script:supportPolicy | Should -Match 'does not promise backports to older pre-1\.0 releases'
        $script:supportPolicy | Should -Match 'Unreleased `main` content.*not a separately supported production line'
        $script:securityPolicy | Should -Match '(?s)latest supported stable\s+module version under.*support-policy\.md'
        $script:securityPolicy | Should -Match 'older stable versions are not promised parallel security-fix branches'
    }

    It 'defines pre-1.0 breaking-change notice and migration expectations' {
        $script:supportPolicy | Should -Match 'Before `1\.0\.0`, incompatible changes may occur in a \*\*minor\*\* release'
        $script:supportPolicy | Should -Match 'CHANGELOG\.md'
        $script:supportPolicy | Should -Match 'release notes'
        $script:supportPolicy | Should -Match 'include migration guidance'
        $script:supportPolicy | Should -Match 'Patch releases should remain backward-compatible'
        $script:versioning | Should -Match 'support-policy\.md'
        $script:versioning | Should -Match 'notice/migration rules'
    }

    It 'defines the PowerShell prerequisite and host baselines precisely' {
        $script:supportPolicy | Should -Match 'current normative minimum is \*\*PowerShell 7\.4\*\*'
        $script:supportPolicy | Should -Match 'does not imply Windows PowerShell 5\.1 support'
        $script:supportPolicy | Should -Match 'current `0\.1\.x` release line supports \*\*GitHub\.com only\*\*'
        $script:manifest.PowerShellVersion | Should -Be '7.4'
        $script:hostSupport | Should -Match 'current `0\.1\.x` release line supports GitHub\.com only'
        $script:hostSupport | Should -Match 'support-policy\.md'
    }

    It 'treats native prerequisites as capability-based release-tested external dependencies' {
        foreach ($prerequisite in @('Git', 'GitHub CLI', 'Git LFS')) {
            $script:supportPolicy | Should -Match ([regex]::Escape($prerequisite))
        }
        $script:supportPolicy | Should -Match 'capability-based and release-tested'
        $script:supportPolicy | Should -Match 'supported by its upstream/vendor'
        $script:supportPolicy | Should -Match 'older or unusual prerequisite versions that have not been exercised are best-effort'
        $script:supportPolicy | Should -Match 'Git LFS remains conditional'
    }

    It 'defines supported OS families without claiming every historical OS release' {
        foreach ($platform in @('Windows', 'Ubuntu', 'macOS')) {
            $script:supportPolicy | Should -Match ([regex]::Escape($platform))
        }
        $script:supportPolicy | Should -Match 'does not claim that every historical release or distribution version within those families has been tested'
        $script:supportPolicy | Should -Match 'Organizations with stricter OS-version requirements should validate the intended module release'
    }

    It 'covers compatibility-sensitive deprecation and accelerated safety removals' {
        foreach ($surface in @(
            'exported commands',
            'public parameters',
            'structured output/report fields',
            'error identifiers',
            'default behaviors and safety semantics',
            'supported installation/release workflows',
            'documented features'
        )) {
            $script:supportPolicy | Should -Match ([regex]::Escape($surface))
        }
        $script:supportPolicy | Should -Match 'at least one subsequent stable release before removal'
        $script:supportPolicy | Should -Match 'severe security, data-loss, platform, or correctness risk may require faster removal'
        $script:supportPolicy | Should -Match 'Any accelerated removal must be documented with the reason and migration guidance'
    }

    It 'defines end-of-support and communication authority without competing policies' {
        $script:supportPolicy | Should -Match 'A module release becomes unsupported when a newer stable release supersedes it'
        $script:supportPolicy | Should -Match 'End-of-support decisions must be intentional and communicated through the changelog/release notes'
        $script:strategy | Should -Match 'Support lifecycle, compatibility, prerequisite/platform support, deprecation, end of support.*docs/user/support-policy\.md'
        $script:strategy | Should -Match 'support policy owns lifecycle/compatibility/deprecation semantics'
    }

    It 'is discoverable from user security versioning assurance and site entry points' {
        $script:readme | Should -Match 'Support, compatibility, and deprecation policy.*docs/user/support-policy\.md'
        $script:securityPolicy | Should -Match 'docs/user/support-policy\.md'
        $script:versioning | Should -Match 'support-policy\.md'
        $script:assurance | Should -Match 'support-policy\.md'
        $script:assurance | Should -Match 'latest published stable module version is the supported line'
        $script:navigation | Should -Match 'title: Support & Compatibility'
        $script:navigation | Should -Match 'path: docs/user/support-policy\.md'
    }
}
