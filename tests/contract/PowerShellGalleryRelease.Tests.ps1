BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:manifestPath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    $script:packageScriptPath = Join-Path $repositoryRoot 'build/New-PowerShellGalleryPackage.ps1'
    $script:releaseReadinessPath = Join-Path $repositoryRoot 'build/Test-ReleaseReadiness.ps1'
    $script:releaseWorkflowPath = Join-Path $repositoryRoot '.github/workflows/publish-release.yml'
    $script:readmePath = Join-Path $repositoryRoot 'README.md'
    $script:publishingDocumentationPath = Join-Path $repositoryRoot 'docs/release/publishing.md'
    $script:expectedCommands = @(
        'Copy-GitHubRepository'
        'Get-GitHubRepository'
        'Start-CopyGitHubRepositoryWizard'
        'Test-GitHubRepositoryMigration'
    ) | Sort-Object
}

Describe 'PowerShell Gallery package' {
    It 'stages only the runtime module and validates its public command surface' {
        $outputDirectory = Join-Path $TestDrive 'PSGallery'
        $package = & $script:packageScriptPath -OutputDirectory $outputDirectory

        $package.Version | Should -Be '0.1.0'
        Test-Path -LiteralPath $package.ManifestPath -PathType Leaf | Should -BeTrue
        Test-ModuleManifest -Path $package.ManifestPath -ErrorAction Stop | Should -Not -BeNullOrEmpty
        @($package.ExportedFunctions | Sort-Object) | Should -Be $script:expectedCommands

        foreach ($unexpectedName in @('.github', 'build', 'docs', 'tests')) {
            Test-Path -LiteralPath (Join-Path $package.PackagePath $unexpectedName) | Should -BeFalse
        }
    }

    It 'imports successfully from the staged package path without leaving the temporary module loaded' {
        $outputDirectory = Join-Path $TestDrive 'ImportTest'
        $package = & $script:packageScriptPath -OutputDirectory $outputDirectory
        $module = $null

        try {
            $module = Import-Module -Name $package.ManifestPath -Force -PassThru -Scope Local -ErrorAction Stop
            @($module.ExportedFunctions.Keys | Sort-Object) | Should -Be $script:expectedCommands
        }
        finally {
            if ($null -ne $module) {
                Remove-Module -ModuleInfo $module -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'has public publication metadata in the source manifest' {
        $manifest = Import-PowerShellDataFile -LiteralPath $script:manifestPath

        $manifest.Author | Should -Not -BeNullOrEmpty
        $manifest.CompanyName | Should -Not -BeNullOrEmpty
        $manifest.Copyright | Should -Not -BeNullOrEmpty
        $manifest.Description | Should -Not -BeNullOrEmpty
        $manifest.PrivateData.PSData.LicenseUri | Should -Match '^https://github\.com/infoconex/copy-github-repo/'
        $manifest.PrivateData.PSData.ProjectUri | Should -Be 'https://github.com/infoconex/copy-github-repo'
        $manifest.PrivateData.PSData.ReleaseNotes | Should -Be 'https://github.com/infoconex/copy-github-repo/releases'
        @($manifest.PrivateData.PSData.Tags) | Should -Contain 'PowerShell'
    }
}

Describe 'PowerShell Gallery release workflow contract' {
    BeforeAll {
        $script:releaseWorkflow = (Get-Content -LiteralPath $script:releaseWorkflowPath -Raw) -replace "`r`n?", "`n"
        $script:releaseReadiness = (Get-Content -LiteralPath $script:releaseReadinessPath -Raw) -replace "`r`n?", "`n"
    }

    It 'supports version-tag pushes and guarded manual dispatch through one release workflow' {
        $script:releaseWorkflow | Should -Match '(?m)^name: Publish Release$'
        $script:releaseWorkflow | Should -Match "(?ms)^'on':\s+push:\s+tags:\s+- 'v\*'\s+workflow_dispatch:"
        $script:releaseWorkflow | Should -Match '(?ms)workflow_dispatch:\s+inputs:\s+tag:'
        $script:releaseWorkflow | Should -Match '(?ms)confirm_publish:.*?type: boolean'
        $script:releaseWorkflow | Should -Match '(?ms)validate_quality:\s+name: Validate Release Commit\s+needs: release_context'
        $script:releaseWorkflow | Should -Match 'uses: \./\.github/workflows/validate-project-quality\.yml'
    }

    It 'validates manual publication from the current main SHA before the quality gate' {
        $script:releaseWorkflow | Should -Match 'refs/heads/main'
        $script:releaseWorkflow | Should -Match 'confirm_publish'
        $script:releaseWorkflow | Should -Match 'git/ref/heads/main'
        $script:releaseWorkflow | Should -Match 'is no longer the current main SHA'
        $script:releaseWorkflow | Should -Match 'release_tag=\$tag'
    }

    It 'delegates stable tag and manifest-version validation to the release-readiness boundary before mutation' {
        $readinessIndex = $script:releaseWorkflow.IndexOf('./build/Test-ReleaseReadiness.ps1', [StringComparison]::Ordinal)
        $artifactIndex = $script:releaseWorkflow.IndexOf('./build/New-ReleaseArtifact.ps1', [StringComparison]::Ordinal)
        $galleryIndex = $script:releaseWorkflow.IndexOf('./build/New-PowerShellGalleryPackage.ps1', [StringComparison]::Ordinal)

        $readinessIndex | Should -BeGreaterThan -1
        $artifactIndex | Should -BeGreaterThan $readinessIndex
        $galleryIndex | Should -BeGreaterThan $readinessIndex
        $script:releaseWorkflow | Should -Match "-Tag '\$\{\{ needs\.release_context\.outputs\.release_tag \}\}'"
        $script:releaseWorkflow | Should -Match '-RequireEmptyUnreleased'
        $script:releaseReadiness | Should -Match "ValidatePattern\('\^v\(\?:0\|\[1-9\]\\d\*\)"
        $script:releaseReadiness | Should -Match 'does not match module version'
    }

    It 'creates or reuses only the exact approved manual tag after duplicate checks and before publication' {
        $galleryCheckIndex = $script:releaseWorkflow.IndexOf('Reject duplicate PowerShell Gallery version', [StringComparison]::Ordinal)
        $githubCheckIndex = $script:releaseWorkflow.IndexOf('Reject duplicate GitHub release', [StringComparison]::Ordinal)
        $tagIndex = $script:releaseWorkflow.IndexOf('Ensure manual release tag', [StringComparison]::Ordinal)
        $galleryPublishIndex = $script:releaseWorkflow.IndexOf('Publish PowerShell Gallery package', [StringComparison]::Ordinal)

        $galleryCheckIndex | Should -BeGreaterThan -1
        $githubCheckIndex | Should -BeGreaterThan $galleryCheckIndex
        $tagIndex | Should -BeGreaterThan $githubCheckIndex
        $galleryPublishIndex | Should -BeGreaterThan $tagIndex
        $script:releaseWorkflow | Should -Match 'git/ref/tags/\$tag'
        $script:releaseWorkflow | Should -Match 'git/tags'
        $script:releaseWorkflow | Should -Match 'message=CopyGitHubRepo \$version'
        $script:releaseWorkflow | Should -Match 'Existing tag.*does not resolve to approved release commit'
    }

    It 'uses the protected Gallery environment and secret only in the release workflow' {
        $script:releaseWorkflow | Should -Match '(?m)^    environment: powershell-gallery$'
        $script:releaseWorkflow | Should -Match 'PSGALLERY_API_KEY: \$\{\{ secrets\.PSGALLERY_API_KEY \}\}'
        $script:releaseWorkflow | Should -Match '-ApiKey \$env:PSGALLERY_API_KEY'
    }

    It 'checks both publication destinations for duplicates before publishing' {
        $galleryCheckIndex = $script:releaseWorkflow.IndexOf('Reject duplicate PowerShell Gallery version', [StringComparison]::Ordinal)
        $githubCheckIndex = $script:releaseWorkflow.IndexOf('Reject duplicate GitHub release', [StringComparison]::Ordinal)
        $galleryPublishIndex = $script:releaseWorkflow.IndexOf('Publish PowerShell Gallery package', [StringComparison]::Ordinal)
        $githubPublishIndex = $script:releaseWorkflow.IndexOf('Publish GitHub release', [StringComparison]::Ordinal)

        $galleryCheckIndex | Should -BeGreaterThan -1
        $githubCheckIndex | Should -BeGreaterThan $galleryCheckIndex
        $galleryPublishIndex | Should -BeGreaterThan $githubCheckIndex
        $githubPublishIndex | Should -BeGreaterThan $galleryPublishIndex
        $script:releaseWorkflow | Should -Match 'Find-PSResource'
        $script:releaseWorkflow | Should -Match '-Version \$version'
        $script:releaseWorkflow | Should -Match '\$existing = @\(\)'
        $script:releaseWorkflow | Should -Match '\$expectedNotFound = "Package with name.*could not be found in repository ''PSGallery''\.'
        $script:releaseWorkflow | Should -Match 'if \(\$_\.Exception\.Message -notlike'
        $script:releaseWorkflow | Should -Match '(?ms)catch \{.*?if \(\$_\.Exception\.Message -notlike.*?throw.*?publication may proceed'
    }

    It 'publishes the validated staged module with PSResourceGet' {
        $script:releaseWorkflow | Should -Match 'Microsoft\.PowerShell\.PSResourceGet'
        $script:releaseWorkflow | Should -Match 'Publish-PSResource'
        $script:releaseWorkflow | Should -Match '-Path \./dist/PSGallery/CopyGitHubRepo'
        $script:releaseWorkflow | Should -Not -Match '(?m)^\s*pull_request:'
    }
}

Describe 'PowerShell Gallery documentation contract' {
    It 'documents the actual package name for standard install update and uninstall commands' {
        $readme = Get-Content -LiteralPath $script:readmePath -Raw

        $readme | Should -Match 'Install-PSResource CopyGitHubRepo'
        $readme | Should -Match 'Install-Module CopyGitHubRepo'
        $readme | Should -Match 'Update-PSResource CopyGitHubRepo'
        $readme | Should -Match 'Uninstall-PSResource CopyGitHubRepo'
    }

    It 'documents protected publishing credentials manual release path fallback prerelease policy and signing policy' {
        $publishingDocumentation = Get-Content -LiteralPath $script:publishingDocumentationPath -Raw

        $publishingDocumentation | Should -Match 'powershell-gallery'
        $publishingDocumentation | Should -Match 'PSGALLERY_API_KEY'
        $publishingDocumentation | Should -Match 'Run workflow'
        $publishingDocumentation | Should -Match 'confirm_publish'
        $publishingDocumentation | Should -Match 'Publish-PSResource'
        $publishingDocumentation | Should -Match '-WhatIf'
        $publishingDocumentation | Should -Match 'Prerelease Gallery publication is intentionally not enabled'
        $publishingDocumentation | Should -Match 'Authenticode signing is optional'
    }
}
