BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:bootstrapPath = Join-Path $repositoryRoot 'install-release.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:bootstrapPath,
        [ref] $tokens,
        [ref] $parseErrors
    )

    $parseErrors.Count | Should -Be 0

    foreach ($functionName in @('ConvertTo-CgrApplicationErrorRecord', 'Test-CgrReleaseArtifactAttestation')) {
        $functionAst = $ast.Find(
            { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName },
            $true
        )
        $functionAst | Should -Not -BeNullOrEmpty
        . ([scriptblock]::Create($functionAst.Extent.Text))
    }

    $script:testArtifact = Join-Path ([System.IO.Path]::GetTempPath()) 'CopyGitHubRepo-attestation-test.zip'
    Set-Content -LiteralPath $script:testArtifact -Value 'fixture' -NoNewline
    $script:sourceCommit = '0123456789abcdef0123456789abcdef01234567'
    $script:repository = 'infoconex/copy-github-repo'
    $script:signerWorkflow = 'infoconex/copy-github-repo/.github/workflows/publish-release.yml'
}

AfterAll {
    Remove-Item -LiteralPath $script:testArtifact -Force -ErrorAction SilentlyContinue
    Remove-Item Function:\gh -Force -ErrorAction SilentlyContinue
}

Describe 'Stable release artifact attestation verification' {
    BeforeEach {
        $script:capturedGhArguments = @()
        Remove-Item Function:\gh -Force -ErrorAction SilentlyContinue
    }

    It 'accepts a valid provenance verification and binds repository workflow and source commit' {
        function global:gh {
            $script:capturedGhArguments = @($args)
            $global:LASTEXITCODE = 0
            'Verification succeeded'
        }

        $result = Test-CgrReleaseArtifactAttestation `
            -ArtifactPath $script:testArtifact `
            -Repository $script:repository `
            -SourceCommit $script:sourceCommit `
            -SignerWorkflow $script:signerWorkflow

        $result | Should -BeTrue
        $script:capturedGhArguments | Should -Contain 'attestation'
        $script:capturedGhArguments | Should -Contain 'verify'
        $script:capturedGhArguments | Should -Contain '--repo'
        $script:capturedGhArguments | Should -Contain $script:repository
        $script:capturedGhArguments | Should -Contain '--signer-workflow'
        $script:capturedGhArguments | Should -Contain $script:signerWorkflow
        $script:capturedGhArguments | Should -Contain '--source-digest'
        $script:capturedGhArguments | Should -Contain $script:sourceCommit
    }

    It 'fails closed when no matching attestation exists' {
        function global:gh {
            $global:LASTEXITCODE = 1
            'no attestations found for subject digest'
        }

        $caught = $null
        try {
            Test-CgrReleaseArtifactAttestation `
                -ArtifactPath $script:testArtifact `
                -Repository $script:repository `
                -SourceCommit $script:sourceCommit `
                -SignerWorkflow $script:signerWorkflow
        }
        catch {
            $caught = $_
        }

        $caught | Should -Not -BeNullOrEmpty
        $caught.Exception.Data['CopyGitHubRepo.ErrorId'] | Should -Be 'CopyGitHubRepo.ReleaseAttestationInvalid'
        $caught.Exception.Message | Should -Match 'provenance verification failed'
        $caught.Exception.Message | Should -Match 'no attestations found'
    }

    It 'fails closed when attestation verification is invalid' {
        function global:gh {
            $global:LASTEXITCODE = 1
            'signature verification failed'
        }

        $caught = $null
        try {
            Test-CgrReleaseArtifactAttestation `
                -ArtifactPath $script:testArtifact `
                -Repository $script:repository `
                -SourceCommit $script:sourceCommit `
                -SignerWorkflow $script:signerWorkflow
        }
        catch {
            $caught = $_
        }

        $caught | Should -Not -BeNullOrEmpty
        $caught.Exception.Data['CopyGitHubRepo.ErrorId'] | Should -Be 'CopyGitHubRepo.ReleaseAttestationInvalid'
        $caught.Exception.Message | Should -Match 'signature verification failed'
    }

    It 'fails closed when GitHub CLI is unavailable' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'gh' }

        $caught = $null
        try {
            Test-CgrReleaseArtifactAttestation `
                -ArtifactPath $script:testArtifact `
                -Repository $script:repository `
                -SourceCommit $script:sourceCommit `
                -SignerWorkflow $script:signerWorkflow
        }
        catch {
            $caught = $_
        }

        $caught | Should -Not -BeNullOrEmpty
        $caught.Exception.Data['CopyGitHubRepo.ErrorId'] | Should -Be 'CopyGitHubRepo.ReleaseAttestationVerifierUnavailable'
        $caught.Exception.Message | Should -Match 'GitHub CLI \(gh\) is required'
    }

    It 'performs attestation verification after SHA-256 validation and before extraction' {
        $bootstrap = Get-Content -LiteralPath $script:bootstrapPath -Raw
        $checksumIndex = $bootstrap.IndexOf('if ($actualHash -ne $expectedHash)')
        $attestationIndex = $bootstrap.IndexOf('Test-CgrReleaseArtifactAttestation')
        $invocationIndex = $bootstrap.LastIndexOf('Test-CgrReleaseArtifactAttestation')
        $extractIndex = $bootstrap.IndexOf('Expand-Archive')

        $checksumIndex | Should -BeGreaterThan -1
        $attestationIndex | Should -BeGreaterThan -1
        $invocationIndex | Should -BeGreaterThan $checksumIndex
        $extractIndex | Should -BeGreaterThan $invocationIndex
        $bootstrap | Should -Match 'infoconex/copy-github-repo/\.github/workflows/publish-release\.yml'
    }
}
