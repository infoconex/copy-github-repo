BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:releaseBuildPath = Join-Path $repositoryRoot 'build/New-ReleaseArtifact.ps1'
    $script:sbomBuildPath = Join-Path $repositoryRoot 'build/New-ReleaseSbom.ps1'
    $script:manifestPath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    $script:releaseWorkflowPath = Join-Path $repositoryRoot '.github/workflows/publish-release.yml'
}

Describe 'Stable release SPDX SBOM' {
    It 'describes the exact deterministic release ZIP and its shipped files' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "copy-github-repo-sbom-test-$([guid]::NewGuid().ToString('N'))"
        $sourceCommit = '0123456789abcdef0123456789abcdef01234567'
        $createdAt = [datetimeoffset]'2026-08-16T20:00:00Z'

        try {
            New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
            $artifact = & $script:releaseBuildPath -OutputDirectory $tempRoot
            $first = & $script:sbomBuildPath -ArtifactPath $artifact.ArtifactPath -SourceCommit $sourceCommit -CreatedAt $createdAt
            $firstJson = Get-Content -LiteralPath $first.SbomPath -Raw
            $firstHash = (Get-FileHash -LiteralPath $first.SbomPath -Algorithm SHA256).Hash

            $second = & $script:sbomBuildPath -ArtifactPath $artifact.ArtifactPath -SourceCommit $sourceCommit -CreatedAt $createdAt
            $secondHash = (Get-FileHash -LiteralPath $second.SbomPath -Algorithm SHA256).Hash
            $sbom = $firstJson | ConvertFrom-Json -Depth 20
            $manifest = Import-PowerShellDataFile -LiteralPath $script:manifestPath
            $version = [string] $manifest.ModuleVersion

            $secondHash | Should -Be $firstHash
            $sbom.spdxVersion | Should -Be 'SPDX-2.3'
            $sbom.dataLicense | Should -Be 'CC0-1.0'
            $sbom.SPDXID | Should -Be 'SPDXRef-DOCUMENT'
            $sbom.documentNamespace | Should -Match ([regex]::Escape($sourceCommit))
            $sbom.creationInfo.created.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') | Should -Be '2026-08-16T20:00:00Z'
            @($sbom.packages).Count | Should -Be 1

            $package = $sbom.packages[0]
            $package.name | Should -Be 'CopyGitHubRepo'
            $package.versionInfo | Should -Be $version
            $package.packageFileName | Should -Be "CopyGitHubRepo-$version.zip"
            $package.filesAnalyzed | Should -BeTrue
            $package.licenseDeclared | Should -Be 'MIT'
            $package.primaryPackagePurpose | Should -Be 'LIBRARY'
            $package.sourceInfo | Should -Match ([regex]::Escape($sourceCommit))

            $artifactSha256 = (Get-FileHash -LiteralPath $artifact.ArtifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
            ($package.checksums | Where-Object algorithm -eq 'SHA256').checksumValue | Should -Be $artifactSha256

            $archive = [System.IO.Compression.ZipFile]::OpenRead($artifact.ArtifactPath)
            try {
                $entryNames = @($archive.Entries | Where-Object { $_.Name } | ForEach-Object { "./$($_.FullName)" } | Sort-Object)
            }
            finally {
                $archive.Dispose()
            }

            $sbomNames = @($sbom.files.fileName | Sort-Object)
            ($sbomNames -join "`n") | Should -Be ($entryNames -join "`n")
            @($sbom.files | Where-Object { @($_.checksums | Where-Object algorithm -eq 'SHA256').Count -ne 1 }).Count | Should -Be 0
            @($sbom.relationships | Where-Object relationshipType -eq 'CONTAINS').Count | Should -Be $entryNames.Count
        }
        finally {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'keeps development CI and external prerequisites out of the shipped dependency graph' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "copy-github-repo-sbom-classification-$([guid]::NewGuid().ToString('N'))"

        try {
            New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
            $artifact = & $script:releaseBuildPath -OutputDirectory $tempRoot
            $result = & $script:sbomBuildPath `
                -ArtifactPath $artifact.ArtifactPath `
                -SourceCommit '0123456789abcdef0123456789abcdef01234567' `
                -CreatedAt ([datetimeoffset]'2026-08-16T20:00:00Z')
            $sbom = Get-Content -LiteralPath $result.SbomPath -Raw | ConvertFrom-Json -Depth 20
            $serialized = $sbom | ConvertTo-Json -Depth 20

            @($sbom.packages).Count | Should -Be 1 -Because 'only the shipped CopyGitHubRepo package belongs in the runtime SBOM package graph'
            @($sbom.relationships | Where-Object relationshipType -eq 'DEPENDS_ON').Count | Should -Be 0
            $sbom.packages[0].comment | Should -Match 'Runtime PowerShell module dependencies: none'
            $sbom.packages[0].comment | Should -Match 'PowerShell 7\.4\+, Git, GitHub CLI, and Git LFS'
            $sbom.packages[0].comment | Should -Match 'Development-only dependencies such as Pester and PSScriptAnalyzer'
            $serialized | Should -Not -Match '"name"\s*:\s*"Pester"'
            $serialized | Should -Not -Match '"name"\s*:\s*"PSScriptAnalyzer"'
        }
        finally {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'fails closed for an artifact whose name does not match the manifest version' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "copy-github-repo-sbom-wrong-version-$([guid]::NewGuid().ToString('N'))"

        try {
            New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
            $artifact = & $script:releaseBuildPath -OutputDirectory $tempRoot
            $wrongPath = Join-Path $tempRoot 'CopyGitHubRepo-999.999.999.zip'
            Copy-Item -LiteralPath $artifact.ArtifactPath -Destination $wrongPath

            {
                & $script:sbomBuildPath `
                    -ArtifactPath $wrongPath `
                    -SourceCommit '0123456789abcdef0123456789abcdef01234567' `
                    -CreatedAt ([datetimeoffset]'2026-08-16T20:00:00Z')
            } | Should -Throw '*does not match expected module version*'
        }
        finally {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Release SBOM attestation workflow' {
    It 'generates publishes and attests the SPDX SBOM for the release ZIP' {
        $content = Get-Content -LiteralPath $script:releaseWorkflowPath -Raw

        $content | Should -Match 'id-token: write'
        $content | Should -Match 'attestations: write'
        $content | Should -Match 'New-ReleaseSbom\.ps1'
        $content | Should -Match "actions/attest@59d89421af93a897026c735860bf21b6eb4f7b26"
        $content | Should -Match 'subject-path: dist/CopyGitHubRepo-\*\.zip'
        $content | Should -Match 'sbom-path: dist/CopyGitHubRepo-\*\.spdx\.json'
        $content | Should -Match '\$sbomPath = "dist/CopyGitHubRepo-\$version\.spdx\.json"'
        $content | Should -Match 'gh release create \$tag \$artifactPath \$checksumPath \$sbomPath'
    }

    It 'binds deterministic SBOM creation metadata to the exact release commit' {
        $content = Get-Content -LiteralPath $script:releaseWorkflowPath -Raw
        $generator = Get-Content -LiteralPath $script:sbomBuildPath -Raw

        $content | Should -Match "git show -s --format=%cI '\$\{\{ github\.sha \}\}'"
        $content | Should -Match "-SourceCommit '\$\{\{ github\.sha \}\}'"
        $generator | Should -Match 'File inventory and checksums were calculated from the completed release ZIP'
        $generator | Should -Match 'SPDX-2\.3'
    }
}
