BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:readmePath = Join-Path $repositoryRoot 'README.md'
    $script:securityPath = Join-Path $repositoryRoot 'docs/security/installation-security.md'
    $script:releaseBootstrapPath = Join-Path $repositoryRoot 'install-release.ps1'
    $script:prereleaseBootstrapPath = Join-Path $repositoryRoot 'install-prerelease.ps1'
    $script:manifestPath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'

    $script:readme = Get-Content -LiteralPath $script:readmePath -Raw
    $script:security = Get-Content -LiteralPath $script:securityPath -Raw
    $script:manifest = Import-PowerShellDataFile -LiteralPath $script:manifestPath
    $script:version = [string] $script:manifest.ModuleVersion
    $script:normalizedReadme = (($script:readme -replace '(?m)^>\s?', '') -replace '\s+', ' ')
}

Describe 'Installer supply-chain trust documentation' {
    It 'identifies PowerShell Gallery as the normal stable installation path' {
        $script:readme | Should -Match 'recommended normal installation path is PowerShell Gallery'
        $script:readme | Should -Match 'Install-PSResource CopyGitHubRepo'
        $script:security | Should -Match '## PowerShell Gallery installation'
        $script:security | Should -Match 'recommended normal installation path for stable releases'
        $script:security | Should -Match 'Install-PSResource CopyGitHubRepo'
        $script:security | Should -Match 'Update-PSResource CopyGitHubRepo'
        $script:security | Should -Match 'Uninstall-PSResource CopyGitHubRepo'
        $script:security | Should -Match 'repository-hosted stable convenience bootstrap is an alternative'
        $script:security | Should -Not -Match 'The normal stable one-line command downloads `install-release\.ps1`'
    }

    It 'distinguishes Gallery package installation from GitHub Release provenance verification' {
        $script:security | Should -Match 'does not independently download the project''s GitHub Release `\.sha256` sidecar'
        $script:security | Should -Match 'does not independently perform the GitHub Release ZIP checksum/attestation procedure'
        $script:security | Should -Match 'require the project''s checksum-and-GitHub-provenance verification contract'
    }

    It 'identifies mutable main bootstraps as explicit trust boundaries' {
        $script:readme | Should -Match 'mutable `main`'
        $script:normalizedReadme | Should -Match 'bootstrap is therefore part of the trust boundary'
        $script:readme | Should -Match 'docs/security/installation-security\.md'
        $script:security | Should -Match 'mutable `main`'
        $script:security | Should -Match 'bootstrap itself is fetched from mutable repository content'
        $script:security | Should -Match 'convenience bootstrap remains inside the trust boundary'
    }

    It 'documents v0.1.0 as the available initial stable release' {
        $script:readme | Should -Match 'Version `0\.1\.0` is the initial stable release'
        $script:security | Should -Match 'Version `v0\.1\.0` is the initial stable release'
        $script:security | Should -Match 'Use PowerShell Gallery for normal released installations'
        $script:readme | Should -Not -Match 'No stable GitHub Release has been published yet'
        $script:security | Should -Not -Match 'No stable GitHub Release has been published yet'
    }

    It 'documents a pinned release path for the module version without executing main content' {
        $pinnedSection = ($script:security -split '## Pinned release installation', 2)[1]
        $pinnedSection = ($pinnedSection -split '## Independent signing decision', 2)[0]
        $expectedVersionPattern = [regex]::Escape("v$($script:version)")
        $pinnedSection | Should -Match $expectedVersionPattern
        $pinnedSection | Should -Match 'releases/download/\$tag'
        $pinnedSection | Should -Match 'CopyGitHubRepo-\$version\.zip'
        $pinnedSection | Should -Match 'Get-FileHash.*SHA256'
        $pinnedSection | Should -Match 'gh attestation verify'
        $pinnedSection | Should -Match '--signer-workflow'
        $pinnedSection | Should -Match 'publish-release\.yml'
        $pinnedSection | Should -Match '--source-digest'
        $pinnedSection | Should -Match 'Expand-Archive'
        $pinnedSection | Should -Not -Match 'raw\.githubusercontent\.com'
    }

    It 'distinguishes checksum integrity from independent provenance' {
        $script:security | Should -Match 'does \*\*not\*\*, by itself, prove who produced the artifact'
        $script:security | Should -Match 'replace both the artifact and its checksum'
        $script:security | Should -Match 'cryptographically verified identity statement'
        $script:security | Should -Match 'GitHub artifact attestations as the independent release-authenticity mechanism'
        $script:security | Should -Match 'rather than purchasing and managing an Authenticode code-signing certificate'
    }

    It 'requires checksum and provenance verification before stable bootstrap extraction and execution' {
        $bootstrap = Get-Content -LiteralPath $script:releaseBootstrapPath -Raw
        $hashIndex = $bootstrap.IndexOf('Get-FileHash')
        $comparisonIndex = $bootstrap.IndexOf('if ($actualHash -ne $expectedHash)')
        $attestationIndex = $bootstrap.LastIndexOf('Test-CgrReleaseArtifactAttestation')
        $extractIndex = $bootstrap.IndexOf('Expand-Archive')
        $invokeIndex = $bootstrap.IndexOf('& $installerPath')

        $hashIndex | Should -BeGreaterThan -1
        $comparisonIndex | Should -BeGreaterThan $hashIndex
        $attestationIndex | Should -BeGreaterThan $comparisonIndex
        $extractIndex | Should -BeGreaterThan $attestationIndex
        $invokeIndex | Should -BeGreaterThan $extractIndex

        $bootstrap | Should -Match 'gh attestation verify'
        $bootstrap | Should -Match '--repo \$Repository'
        $bootstrap | Should -Match '--signer-workflow \$SignerWorkflow'
        $bootstrap | Should -Match '--source-digest \$SourceCommit'
        $bootstrap | Should -Match 'publish-release\.yml'
        $bootstrap | Should -Match 'ReleaseAttestationVerifierUnavailable'
        $bootstrap | Should -Match 'ReleaseAttestationInvalid'
    }

    It 'documents both bootstrap entry points and their release state' {
        $script:readme | Should -Match 'install-release\.ps1 \| iex'
        $script:readme | Should -Match 'install-prerelease\.ps1 \| iex'
        Test-Path -LiteralPath $script:releaseBootstrapPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $script:prereleaseBootstrapPath -PathType Leaf | Should -BeTrue
    }
}
