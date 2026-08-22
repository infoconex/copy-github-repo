BeforeAll {
    $script:repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:runbookPath = Join-Path $script:repositoryRoot 'docs/release/release-runbook.md'
    $script:releaseWorkflowPath = Join-Path $script:repositoryRoot '.github/workflows/publish-release.yml'
    $script:pagesWorkflowPath = Join-Path $script:repositoryRoot '.github/workflows/deploy-documentation-site.yml'
    $script:readinessPath = Join-Path $script:repositoryRoot 'docs/release/release-readiness.md'
    $script:publishingPath = Join-Path $script:repositoryRoot 'docs/release/publishing.md'

    $script:runbook = Get-Content -LiteralPath $script:runbookPath -Raw
    $script:releaseWorkflow = Get-Content -LiteralPath $script:releaseWorkflowPath -Raw
    $script:pagesWorkflow = Get-Content -LiteralPath $script:pagesWorkflowPath -Raw
    $script:readiness = Get-Content -LiteralPath $script:readinessPath -Raw
    $script:publishing = Get-Content -LiteralPath $script:publishingPath -Raw
}

Describe 'Release and deployment runbook documentation contract' {
    It 'separates readiness from execution and the three deployment concerns' {
        $script:runbook | Should -Match 'owns \*\*how\*\* an already-approved release candidate'
        $script:runbook | Should -Match 'does not decide \*\*whether\*\* a candidate is ready'
        foreach ($concern in @('Product release', 'Package distribution', 'Documentation deployment')) {
            $script:runbook | Should -Match ([regex]::Escape($concern))
        }
        $script:runbook | Should -Match '\[`release-readiness\.md`\]\(release-readiness\.md\)'
    }

    It 'documents the canonical lifecycle and exact release mutation ordering' {
        foreach ($state in @(
            'Planned', 'Release Candidate', 'Readiness Reviewed', 'Approved',
            'Release Workflow Started', 'Validated', 'Artifacts Built',
            'Integrity Evidence Generated', 'Attested', 'Tag Confirmed/Created',
            'Published to PowerShell Gallery', 'Published to GitHub Release',
            'Distribution Verified', 'Documentation Verified', 'Complete'
        )) {
            $script:runbook | Should -Match ([regex]::Escape($state))
        }

        $galleryIndex = $script:releaseWorkflow.IndexOf('Publish PowerShell Gallery package')
        $githubIndex = $script:releaseWorkflow.IndexOf('Publish GitHub release')
        $galleryIndex | Should -BeGreaterThan -1
        $githubIndex | Should -BeGreaterThan $galleryIndex
        $script:runbook | Should -Match 'publishes the validated module package to PowerShell Gallery before creating the GitHub Release'
    }

    It 'requires exact-candidate readiness and release evidence before publication' {
        foreach ($term in @(
            '40-character commit SHA',
            'Release readiness is `GO`',
            'RequireEmptyUnreleased',
            'Windows, Ubuntu, and macOS Validate Project Quality',
            'Applicable live E2E evidence',
            'PSGALLERY_API_KEY',
            'No immutable-version conflict exists'
        )) {
            $script:runbook | Should -Match ([regex]::Escape($term))
        }
        $script:readiness | Should -Match 'A later commit requires a new readiness review'
    }

    It 'matches the supported manual dispatch safety contract' {
        $script:runbook | Should -Match 'Preferred release procedure.*manual workflow dispatch'
        $script:runbook | Should -Match 'confirm_publish'
        $script:releaseWorkflow | Should -Match "github\.ref.*refs/heads/main"
        $script:releaseWorkflow | Should -Match 'currentMainSha'
        $script:releaseWorkflow | Should -Match 'github\.sha'
        $script:releaseWorkflow | Should -Match 'Ensure manual release tag'
    }

    It 'documents required integrity evidence without treating attestation as independent signing' {
        foreach ($term in @(
            'CopyGitHubRepo-X.Y.Z.zip',
            'CopyGitHubRepo-X.Y.Z.zip.sha256',
            'CopyGitHubRepo-X.Y.Z.spdx.json',
            'build-provenance attestation',
            'SBOM attestation'
        )) {
            $script:runbook | Should -Match ([regex]::Escape($term))
        }
        $script:runbook | Should -Match 'Independent publisher signing is not implied'
        $script:runbook | Should -Match 'security architecture and release-readiness process'
    }

    It 'covers post-publication verification for both package channels and the installer' {
        $script:runbook | Should -Match 'Confirm the stable tag resolves to the exact approved candidate SHA'
        $script:runbook | Should -Match 'Find-PSResource CopyGitHubRepo -Version X\.Y\.Z -Repository PSGallery'
        $script:runbook | Should -Match 'fresh `pwsh -NoProfile -NonInteractive` process'
        $script:runbook | Should -Match 'install-release\.ps1 -Version X\.Y\.Z'
        $script:runbook | Should -Match 'checksum validation succeeds before extraction'
    }

    It 'documents partial publication and immutable recovery boundaries' {
        foreach ($scenario in @(
            'Version/tag/manifest/changelog mismatch',
            'Validate Project Quality failure',
            'Required live evidence missing/failed',
            'Package/artifact/SBOM/attestation failure',
            'Publishing credential/environment approval unavailable',
            'Existing Gallery version detected',
            'Existing GitHub Release detected',
            'Tag exists but resolves to a different commit',
            'Gallery succeeds, GitHub Release fails',
            'Gallery publication succeeds but clean install/import verification fails',
            'Documentation Pages deployment fails'
        )) {
            $script:runbook | Should -Match ([regex]::Escape($scenario))
        }
        $script:runbook | Should -Match 'Do not republish Gallery'
        $script:runbook | Should -Match 'Do not clobber stable assets'
        $script:runbook | Should -Match 'Never move/reuse the tag for a different approved SHA'
        $script:publishing | Should -Match 'GitHub Release and PowerShell Gallery are separate services and cannot be updated atomically'
    }

    It 'treats Pages as an independently recoverable deployment' {
        $script:runbook | Should -Match 'Pages is an independent deployment'
        $script:runbook | Should -Match 'Jekyll build and generated-site integrity validation'
        $script:runbook | Should -Match 'published-site smoke test'
        $script:pagesWorkflow | Should -Match 'Validate generated site integrity'
        $script:pagesWorkflow | Should -Match 'Smoke test published site'
    }

    It 'requires an auditable completion record and routes serious post-release failures to incident response' {
        foreach ($term in @(
            'Publish Release workflow run ID',
            'release ZIP filename/SHA-256',
            'PowerShell Gallery publication and clean-install verification',
            'GitHub Release publication and asset verification',
            'final state: `Complete`, `Partial / recovery required`, or `Failed before publication`'
        )) {
            $script:runbook | Should -Match ([regex]::Escape($term))
        }
        $script:runbook | Should -Match 'incident-response\.md'
        $script:runbook | Should -Match 'Self-review and automation do not become independent approval evidence'
    }
}
