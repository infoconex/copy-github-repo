BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:releaseReadinessPath = Join-Path $repositoryRoot 'build/Test-ReleaseReadiness.ps1'
    $script:manifestPath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    $script:releaseWorkflowPath = Join-Path $repositoryRoot '.github/workflows/publish-release.yml'
    $script:changelogPath = Join-Path $repositoryRoot 'CHANGELOG.md'
}

Describe 'Stable release readiness validation' {
    It 'accepts the current manifest version when release metadata is aligned' {
        $manifest = Import-PowerShellDataFile -LiteralPath $script:manifestPath
        $version = [string] $manifest.ModuleVersion

        $result = & $script:releaseReadinessPath -Tag "v$version" -RequireEmptyUnreleased

        $result.PSTypeNames[0] | Should -Be 'CopyGitHubRepo.ReleaseReadiness'
        $result.Version | Should -Be $version
        $result.ExpectedTag | Should -Be "v$version"
        $result.ReleaseDate | Should -Match '^\d{4}-\d{2}-\d{2}$'
        $result.IsReady | Should -BeTrue
    }

    It 'rejects a stable tag that does not match ModuleVersion' {
        { & $script:releaseReadinessPath -Tag 'v9.9.9' } |
            Should -Throw -ExpectedMessage '*does not match module version*'
    }

    It 'keeps the Unreleased section empty at the stable publication boundary' {
        $changelog = Get-Content -LiteralPath $script:changelogPath -Raw
        $unreleased = [regex]::Match(
            $changelog,
            '(?ms)^## \[Unreleased\]\r?\n(?<Body>.*?)(?=^## \[\d+\.\d+\.\d+\])'
        )

        $unreleased.Success | Should -BeTrue
        $unreleased.Groups['Body'].Value.Trim() | Should -BeNullOrEmpty
    }

    It 'routes tag and changelog validation through the release-readiness script before packaging' {
        $workflow = Get-Content -LiteralPath $script:releaseWorkflowPath -Raw
        $readinessIndex = $workflow.IndexOf('./build/Test-ReleaseReadiness.ps1')
        $artifactIndex = $workflow.IndexOf('./build/New-ReleaseArtifact.ps1')
        $galleryIndex = $workflow.IndexOf('./build/New-PowerShellGalleryPackage.ps1')

        $workflow | Should -Match "-Tag '\$\{\{ needs\.release_context\.outputs\.release_tag \}\}'"
        $workflow | Should -Match '-RequireEmptyUnreleased'
        $workflow | Should -Match "'\$\{\{ github\.ref_name \}\}'"
        $workflow | Should -Match "'\$\{\{ inputs\.tag \}\}'"
        $readinessIndex | Should -BeGreaterThan -1
        $artifactIndex | Should -BeGreaterThan $readinessIndex
        $galleryIndex | Should -BeGreaterThan $readinessIndex
    }
}
