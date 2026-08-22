BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:releaseBuildPath = Join-Path $repositoryRoot 'build/New-ReleaseArtifact.ps1'
    $script:manifestPath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
}

Describe 'Release artifact packaging' {
    It 'produces a deterministic checksummed installable module archive' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "copy-github-repo-package-test-$([guid]::NewGuid().ToString('N'))"
        $extractPath = Join-Path $tempRoot 'expanded'
        $installRoot = Join-Path $tempRoot 'modules'

        try {
            New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

            $manifest = Import-PowerShellDataFile -LiteralPath $script:manifestPath
            $version = [string] $manifest.ModuleVersion
            $artifactFileName = "CopyGitHubRepo-$version.zip"

            $firstResult = & $script:releaseBuildPath -OutputDirectory $tempRoot
            $firstHash = (Get-FileHash -LiteralPath $firstResult.ArtifactPath -Algorithm SHA256).Hash.ToLowerInvariant()

            $secondResult = & $script:releaseBuildPath -OutputDirectory $tempRoot
            $secondHash = (Get-FileHash -LiteralPath $secondResult.ArtifactPath -Algorithm SHA256).Hash.ToLowerInvariant()

            $secondHash | Should -Be $firstHash
            $secondResult.Sha256 | Should -Be $secondHash
            (Get-Content -LiteralPath $secondResult.ChecksumPath -Raw).Trim() |
                Should -Be "$secondHash  $artifactFileName"

            Expand-Archive -LiteralPath $secondResult.ArtifactPath -DestinationPath $extractPath -Force
            $packagedManifestPath = Join-Path $extractPath "CopyGitHubRepo/$version/CopyGitHubRepo.psd1"
            $packagedInstallerPath = Join-Path $extractPath 'install.ps1'
            Test-Path -LiteralPath $packagedManifestPath | Should -BeTrue
            Test-Path -LiteralPath $packagedInstallerPath | Should -BeTrue

            $packagedModule = Test-ModuleManifest -Path $packagedManifestPath -ErrorAction Stop
            $packagedModule.Version.ToString() | Should -Be $version
            @($packagedModule.ExportedFunctions.Keys) | Should -Contain 'Start-CopyGitHubRepositoryWizard'

            $installResult = & $packagedInstallerPath -DestinationRoot $installRoot -Confirm:$false
            $installedManifestPath = Join-Path $installRoot "CopyGitHubRepo/$version/CopyGitHubRepo.psd1"
            Test-Path -LiteralPath $installedManifestPath | Should -BeTrue
            $installResult.IsSuccessful | Should -BeTrue
            $installResult.Version | Should -Be $version

            Import-Module $installedManifestPath -Force
            $installedCommands = Get-Command -Module CopyGitHubRepo |
                Select-Object -ExpandProperty Name |
                Sort-Object
            $expectedInstalledCommands = @(
                'Copy-GitHubRepository'
                'Get-GitHubRepository'
                'Start-CopyGitHubRepositoryWizard'
                'Test-GitHubRepositoryMigration'
            ) | Sort-Object
            ($installedCommands -join ',') | Should -Be ($expectedInstalledCommands -join ',')
            Remove-Module CopyGitHubRepo -Force

            $caughtError = $null
            try {
                & $packagedInstallerPath -DestinationRoot $installRoot -Confirm:$false
            }
            catch {
                $caughtError = $_
            }

            $caughtError | Should -Not -BeNullOrEmpty
            $caughtError.Exception.Message | Should -BeLike '*already installed*'
            $caughtError.FullyQualifiedErrorId | Should -Match '^CopyGitHubRepo\.VersionAlreadyInstalled'
            $caughtError.Exception.Data['CopyGitHubRepo.ApplicationError'] | Should -BeTrue
            $caughtError.Exception.Data['CopyGitHubRepo.ErrorId'] | Should -Be 'CopyGitHubRepo.VersionAlreadyInstalled'

            $replacementResult = & $packagedInstallerPath -DestinationRoot $installRoot -Force -Confirm:$false
            $replacementResult.IsSuccessful | Should -BeTrue
            $replacementResult.ReplacedExistingVersion | Should -BeTrue
            $secondResult.FileCount | Should -BeGreaterThan 1
        }
        finally {
            Remove-Module CopyGitHubRepo -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Stable GitHub release publication' {
    BeforeAll {
        $script:releaseWorkflowPath = Join-Path $repositoryRoot '.github/workflows/publish-release.yml'
        $script:qualityWorkflowPath = Join-Path $repositoryRoot '.github/workflows/validate-project-quality.yml'
    }

    It 'creates a new release with the deterministic archive and checksum' {
        $content = Get-Content -LiteralPath $script:releaseWorkflowPath -Raw

        $content | Should -Match 'gh release create \$tag \$artifactPath \$checksumPath'
        $content | Should -Match '--verify-tag'
        $content | Should -Match 'dist/CopyGitHubRepo-\$version\.zip'
        $content | Should -Match '\$checksumPath = "\$artifactPath\.sha256"'
    }

    It 'stops when the stable release already exists instead of replacing assets' {
        $content = Get-Content -LiteralPath $script:releaseWorkflowPath -Raw
        $releaseViewIndex = $content.IndexOf('& gh release view $tag')
        $immutableFailureIndex = $content.IndexOf('Stable GitHub release ''$tag'' already exists')
        $releaseCreateIndex = $content.IndexOf('& gh release create $tag')

        $content | Should -Not -Match 'gh release upload'
        $content | Should -Not -Match '--clobber'
        $content | Should -Match 'stable release assets are immutable'
        $content | Should -Match 'release repair is not part of the normal publication workflow'
        $releaseViewIndex | Should -BeGreaterThan -1
        $immutableFailureIndex | Should -BeGreaterThan $releaseViewIndex
        $releaseCreateIndex | Should -BeGreaterThan $immutableFailureIndex
    }

    It 'requires the exact release commit to pass reusable cross-platform project quality before publication' {
        $releaseContent = Get-Content -LiteralPath $script:releaseWorkflowPath -Raw
        $qualityContent = Get-Content -LiteralPath $script:qualityWorkflowPath -Raw

        $releaseContent | Should -Match '(?ms)^permissions:\s+contents: read\s+jobs:'
        $releaseContent | Should -Match '(?ms)^  validate_quality:.*?needs: release_context.*?permissions:\s+contents: read.*?uses: \./\.github/workflows/validate-project-quality\.yml'
        $releaseContent | Should -Match '(?ms)^  release:.*?needs:\s+- release_context\s+- validate_quality.*?permissions:\s+contents: write'
        $releaseContent | Should -Not -Match 'run: \./build/Test-Project\.ps1'
        $releaseContent | Should -Match 'ref: \$\{\{ github\.sha \}\}'

        $qualityContent | Should -Match '(?m)^  workflow_call:\r?$'
        $qualityContent | Should -Match 'windows-latest'
        $qualityContent | Should -Match 'ubuntu-latest'
        $qualityContent | Should -Match 'macos-latest'
        $qualityContent | Should -Match 'run: \./build/Test-Project\.ps1'
        $qualityContent | Should -Match 'ref: \$\{\{ github\.sha \}\}'
    }
}

Describe 'Release bootstrap installer' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent $PSScriptRoot
        $script:bootstrapInstallerPath = Join-Path $repositoryRoot 'install-release.ps1'
    }

    It 'verifies SHA-256 before extracting and invoking the packaged installer' {
        Test-Path -LiteralPath $script:bootstrapInstallerPath -PathType Leaf | Should -BeTrue

        $content = Get-Content -LiteralPath $script:bootstrapInstallerPath -Raw
        $hashVerificationIndex = $content.IndexOf('Get-FileHash')
        $archiveExtractionIndex = $content.IndexOf('Expand-Archive')
        $installerInvocationIndex = $content.IndexOf('& $installerPath')

        $content | Should -Match '/releases/latest'
        $content | Should -Match 'SHA-256 verification failed'
        $hashVerificationIndex | Should -BeGreaterThan -1
        $archiveExtractionIndex | Should -BeGreaterThan $hashVerificationIndex
        $installerInvocationIndex | Should -BeGreaterThan $archiveExtractionIndex
    }

    It 'defaults to latest stable and supports an exact stable version' {
        $content = Get-Content -LiteralPath $script:bootstrapInstallerPath -Raw

        $content | Should -Match '\[string\] \$Version'
        $content | Should -Match "ValidatePattern\('\^\\d\+\\\.\\d\+\\\.\\d\+\$'\)"
        $content | Should -Match '/releases/latest'
        $content | Should -Match '/releases/tags/v\$Version'
        $content | Should -Match '\$resolvedVersion -ne \$Version'
        $content | Should -Match 'while version.*was requested'
    }

    It 'recognizes deliberate application errors without diagnostic noise' {
        $content = Get-Content -LiteralPath $script:bootstrapInstallerPath -Raw

        $content | Should -Match 'CopyGitHubRepo\.ApplicationError'
        $content | Should -Match 'CopyGitHubRepo\.ErrorId'
        $content | Should -Match 'Test-CgrApplicationErrorRecord -ErrorRecord \$_'
        $content | Should -Match '\$errorId -eq ''CopyGitHubRepo\.VersionAlreadyInstalled'''
        $content | Should -Match 'No changes were made\. Use -Force to replace that version\.'
        $content | Should -Match 'Write-Warning \$friendlyMessage'
        $content | Should -Match 'Write-Error -Message "CopyGitHubRepo: \$message"'
    }

    It 'formats unexpected exceptions with diagnostics before rethrowing' {
        $content = Get-Content -LiteralPath $script:bootstrapInstallerPath -Raw
        $diagnosticIndex = $content.IndexOf('Write-CgrUnhandledError -ErrorRecord $_')
        $rethrowMatch = [regex]::Match($content.Substring($diagnosticIndex), '(?m)^\s{4}throw\r?$')

        $content | Should -Match 'CopyGitHubRepo encountered an unexpected error\.'
        $content | Should -Match 'ExceptionType:'
        $content | Should -Match 'FullyQualifiedErrorId:'
        $content | Should -Match 'ScriptStackTrace:'
        $content | Should -Match 'InnerException\['
        $diagnosticIndex | Should -BeGreaterThan -1
        $rethrowMatch.Success | Should -BeTrue
    }
}
