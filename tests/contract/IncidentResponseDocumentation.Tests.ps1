BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:incidentPath = Join-Path $repositoryRoot 'docs/release/incident-response.md'
    $script:securityPath = Join-Path $repositoryRoot 'SECURITY.md'
    $script:supportPath = Join-Path $repositoryRoot 'docs/user/support-policy.md'
    $script:runbookPath = Join-Path $repositoryRoot 'docs/release/release-runbook.md'
    $script:readinessPath = Join-Path $repositoryRoot 'docs/release/release-readiness.md'

    $script:incident = Get-Content -LiteralPath $script:incidentPath -Raw
    $script:security = Get-Content -LiteralPath $script:securityPath -Raw
    $script:support = Get-Content -LiteralPath $script:supportPath -Raw
    $script:runbook = Get-Content -LiteralPath $script:runbookPath -Raw
    $script:readiness = Get-Content -LiteralPath $script:readinessPath -Raw
}

Describe 'Post-release incident and emergency maintenance documentation contract' {
    It 'defines the required incident classes and severity model' {
        foreach ($term in @(
            'critical functional defect',
            'security vulnerability',
            'publishing credential',
            'release workflow/environment',
            'tampering',
            'supply-chain vulnerability',
            'SBOM',
            'VEX applicability statement',
            'GitHub Release and PowerShell Gallery',
            'installer/update/uninstall',
            'GitHub CLI',
            'documentation or security guidance'
        )) {
            $script:incident | Should -Match ([regex]::Escape($term))
        }

        foreach ($severityPattern in @('S0.*Routine', 'S1.*Significant', 'S2.*Serious', 'S3.*Critical')) {
            $script:incident | Should -Match $severityPattern
        }
    }

    It 'defines a complete response lifecycle and evidence preservation boundary' {
        foreach ($state in @('Detected', 'Triaged', 'Contained', 'Scope Assessed', 'Remediation Planned', 'Fixed', 'Verified', 'Communicated', 'Follow-up Complete')) {
            $script:incident | Should -Match ([regex]::Escape($state))
        }

        foreach ($evidence in @(
            '40-character commit SHA',
            'release workflow run ID',
            'ZIP/checksum/SBOM/attestation identities',
            'timeline and key decisions',
            'remediation commit/release identity',
            'verification evidence'
        )) {
            $script:incident | Should -Match ([regex]::Escape($evidence))
        }

        $script:incident | Should -Match 'Do not preserve secrets merely for completeness'
    }

    It 'forbids unsafe mutation of immutable releases' {
        foreach ($term in @(
            'never overwrite or republish the same Gallery version',
            'never move a published stable tag to a different commit',
            'never silently replace stable release assets',
            'use a new semantic version for corrected shipped code/package content'
        )) {
            $script:incident | Should -Match ([regex]::Escape($term))
        }
    }

    It 'keeps the emergency patch path inside normal integrity controls' {
        foreach ($term in @(
            'Increment the version',
            'Run release readiness',
            'Run the Quality Gate',
            'Run applicable live E2E evidence',
            'Generate normal integrity evidence',
            'Publish through the normal release workflow/runbook',
            'Post-publication verify',
            'Communicate'
        )) {
            $script:incident | Should -Match ([regex]::Escape($term))
        }

        $script:incident | Should -Match 'release-readiness\.md'
        $script:incident | Should -Match 'urgency does not justify silently skipping the repository quality baseline'
        $script:incident | Should -Match 'explicit readiness exception/residual-risk decision'
    }

    It 'defines safe handling for credential and security incidents' {
        $script:incident | Should -Match 'Revoke/rotate the credential'
        $script:incident | Should -Match 'under investigation'
        $script:incident | Should -Match 'private vulnerability report'
        $script:incident | Should -Match 'GitHub private vulnerability reporting/Security Advisory'
        $script:incident | Should -Match 'Do not disclose exploit-enabling details prematurely'
        $script:security | Should -Match 'privately'
    }

    It 'covers partial distribution and prerequisite-specific incidents' {
        foreach ($scenario in @(
            'Gallery package is bad; GitHub Release artifact is correct',
            'GitHub Release artifact/evidence is bad; Gallery package is correct',
            'Installer points to an unsafe/incorrect version',
            'One capability/mode is affected',
            'External prerequisite is affected'
        )) {
            $script:incident | Should -Match ([regex]::Escape($scenario))
        }
    }

    It 'integrates with existing support readiness and normal-release authorities' {
        $script:incident | Should -Match '\[`support-policy\.md`\]\(\.\./user/support-policy\.md\)'
        $script:incident | Should -Match '\[`release-readiness\.md`\]\(release-readiness\.md\)'
        $script:incident | Should -Match '\[`release-runbook\.md`\]\(release-runbook\.md\)'
        $script:incident | Should -Match '\[`governance\.md`\]\(\.\./engineering/governance\.md\)'
        $script:support | Should -Match 'latest published stable module version'
        $script:readiness | Should -Match 'exact release candidate'
        $script:runbook | Should -Match 'incident-response\.md'
    }

    It 'requires lightweight systemic follow-up instead of ceremonial postmortems' {
        $script:incident | Should -Match 'For an S2/S3 incident'
        $script:incident | Should -Match 'which automated test/workflow/documentation/architecture change prevents recurrence'
        $script:incident | Should -Match 'The goal is corrective action, not a ceremonial postmortem document'
    }
}
