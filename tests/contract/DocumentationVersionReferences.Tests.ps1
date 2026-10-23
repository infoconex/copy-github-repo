#requires -Version 7.4

BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:versionAuditPath = Join-Path $repositoryRoot 'build/Test-DocumentationVersionReferences.ps1'
    $script:documentationRunner = Join-Path $repositoryRoot 'build/Test-Documentation.ps1'
    $script:releaseReadiness = Join-Path $repositoryRoot 'build/Test-ReleaseReadiness.ps1'
    $script:sourceRoot = $repositoryRoot
    $script:fixtureFiles = @(
        'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
        'docs/security/installation-security.md'
        'docs/release/publishing.md'
        'docs/user/user-guide.md'
        '.github/workflows/publish-release.yml'
        'README.md'
    )
    $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $repositoryRoot $script:fixtureFiles[0])
    $script:version = [string] $manifest.ModuleVersion
}

Describe 'Release-sensitive documentation version guard' {
    BeforeEach {
        $script:fixtureRoot = Join-Path $TestDrive 'reference-audit-fixture'
        foreach ($relativePath in $script:fixtureFiles) {
            $destination = Join-Path $script:fixtureRoot $relativePath
            New-Item -Path (Split-Path -Parent $destination) -ItemType Directory -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $script:sourceRoot $relativePath) -Destination $destination -Force
        }
    }

    It 'passes the current candidate documentation while allowing historical versions' {
        $result = & $script:versionAuditPath -RepositoryRoot $script:fixtureRoot
        $result.PSTypeNames[0] | Should -Be 'CopyGitHubRepo.DocumentationVersionAudit'
        $result.IntendedVersion | Should -BeExactly $script:version
        $result.GalleryExamples | Should -Be 1
        $result.HostedStableExamples | Should -Be 2
        $result.PinnedZipExamples | Should -Be 1
        $result.IsValid | Should -BeTrue
    }

    It 'rejects a stale exact-version Gallery installation example' {
        $path = Join-Path $script:fixtureRoot 'docs/security/installation-security.md'
        $content = Get-Content -LiteralPath $path -Raw
        $content = $content.Replace(
            ('Install-PSResource CopyGitHubRepo -Version {0}' -f $script:version),
            'Install-PSResource CopyGitHubRepo -Version 9.9.8'
        )
        Set-Content -LiteralPath $path -Value $content
        { & $script:versionAuditPath -RepositoryRoot $script:fixtureRoot } |
            Should -Throw -ExpectedMessage '*installation-security.md:*stale Gallery install version 9.9.8*'
    }

    It 'rejects a stale hosted-bootstrap version without weakening verification code' {
        $path = Join-Path $script:fixtureRoot 'docs/security/installation-security.md'
        $content = Get-Content -LiteralPath $path -Raw
        $content = $content.Replace(
            ('-Version {0} -Force' -f $script:version),
            '-Version 9.9.8 -Force'
        )
        Set-Content -LiteralPath $path -Value $content
        { & $script:versionAuditPath -RepositoryRoot $script:fixtureRoot } |
            Should -Throw -ExpectedMessage '*stale hosted stable bootstrap version 9.9.8*'
    }

    It 'rejects a stale pinned-release ZIP assignment' {
        $path = Join-Path $script:fixtureRoot 'docs/security/installation-security.md'
        $content = Get-Content -LiteralPath $path -Raw
        $current = '$version = ''{0}''' -f $script:version
        $content = $content.Replace($current, '$version = ''9.9.8''')
        Set-Content -LiteralPath $path -Value $content
        { & $script:versionAuditPath -RepositoryRoot $script:fixtureRoot } |
            Should -Throw -ExpectedMessage '*stale pinned ZIP procedure version 9.9.8*'
    }

    It 'rejects removing a required pinned security example' {
        $path = Join-Path $script:fixtureRoot 'docs/security/installation-security.md'
        $content = Get-Content -LiteralPath $path -Raw
        $content = $content.Replace(
            ('Install-PSResource CopyGitHubRepo -Version {0}' -f $script:version),
            'Install-PSResource CopyGitHubRepo'
        )
        Set-Content -LiteralPath $path -Value $content
        { & $script:versionAuditPath -RepositoryRoot $script:fixtureRoot } |
            Should -Throw -ExpectedMessage '*expected one explicit candidate-version Gallery example; found 0*'
    }

    It 'rejects stale literal installation versions in ordinary user guidance' {
        $path = Join-Path $script:fixtureRoot 'docs/user/user-guide.md'
        $content = Get-Content -LiteralPath $path -Raw
        $content = $content.Replace('Install-PSResource CopyGitHubRepo', 'Install-PSResource CopyGitHubRepo -Version 0.1.0')
        Set-Content -LiteralPath $path -Value $content
        { & $script:versionAuditPath -RepositoryRoot $script:fixtureRoot } |
            Should -Throw -ExpectedMessage '*user-guide.md:*ordinary installation guidance must be version-neutral*'
    }

    It 'rejects literal versions in release workflow dispatch help' {
        $path = Join-Path $script:fixtureRoot '.github/workflows/publish-release.yml'
        $content = (Get-Content -LiteralPath $path -Raw).Replace('for example vX.Y.Z', 'for example v0.1.0')
        Set-Content -LiteralPath $path -Value $content
        { & $script:versionAuditPath -RepositoryRoot $script:fixtureRoot } |
            Should -Throw -ExpectedMessage '*publish-release.yml:*release-dispatch tag help must use vX.Y.Z*'
    }

    It 'rejects stale release-readiness commands in the publication guide' {
        $path = Join-Path $script:fixtureRoot 'docs/release/publishing.md'
        $content = Get-Content -LiteralPath $path -Raw
        $content += [Environment]::NewLine + './build/Test-ReleaseReadiness.ps1 -Tag v0.1.0 -RequireEmptyUnreleased'
        Set-Content -LiteralPath $path -Value $content
        { & $script:versionAuditPath -RepositoryRoot $script:fixtureRoot } |
            Should -Throw -ExpectedMessage '*publishing.md:*publication commands must derive the candidate version from ModuleVersion*'
    }

    It 'runs the same guard in documentation and release candidate readiness' {
        Get-Content -LiteralPath $script:documentationRunner -Raw |
            Should -Match 'Test-DocumentationVersionReferences.ps1'
        Get-Content -LiteralPath $script:releaseReadiness -Raw |
            Should -Match 'Test-DocumentationVersionReferences.ps1'
    }
}
