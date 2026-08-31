BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:workflowRoot = Join-Path $repositoryRoot '.github/workflows'
    $script:prWorkflows = @(
        'validate-project-quality.yml'
        'analyze-code-security.yml'
        'analyze-github-actions-security.yml'
        'validate-documentation.yml'
    )
}

Describe 'Release integration pull request validation' {
    It 'runs the required PR validation workflows for main and release integration branches' {
        foreach ($workflowName in $script:prWorkflows) {
            $workflow = (Get-Content -LiteralPath (Join-Path $script:workflowRoot $workflowName) -Raw) -replace "`r`n?", "`n"

            $workflow | Should -Match "(?ms)^  pull_request:\s+branches:\s+- main\s+- 'release/\*\*'"
            $workflow | Should -Not -Match '(?m)^\s*pull_request_target:'
        }
    }

    It 'keeps project-quality documentation-only scope optimization intact' {
        $quality = Get-Content -LiteralPath (Join-Path $script:workflowRoot 'validate-project-quality.yml') -Raw

        $quality | Should -Match 'Determine Quality Scope'
        $quality | Should -Match 'siteOnlyPattern'
        $quality | Should -Match 'Record documentation-only validation'
        $quality | Should -Match "needs\.scope\.outputs\.run-quality != 'true'"
    }

    It 'requires stable publication to be manually dispatched from the qualified main commit' {
        $publish = (Get-Content -LiteralPath (Join-Path $script:workflowRoot 'publish-release.yml') -Raw) -replace "`r`n?", "`n"

        $publish | Should -Match "(?ms)^'on':\s+workflow_dispatch:"
        $publish | Should -Not -Match '(?ms)^\s+push:'
        $publish | Should -Not -Match '(?m)^\s*pull_request:'
        $publish | Should -Match ([regex]::Escape("if ('${{ github.ref }}' -cne 'refs/heads/main')"))
        $publish | Should -Match ([regex]::Escape("if ($currentMainSha -cne '${{ github.sha }}')"))
    }

    It 'keeps documentation deployment limited to main pushes' {
        $deploy = (Get-Content -LiteralPath (Join-Path $script:workflowRoot 'deploy-documentation-site.yml') -Raw) -replace "`r`n?", "`n"

        $deploy | Should -Match '(?ms)^  push:\s+branches:\s+- main'
        $deploy | Should -Not -Match "(?m)^\s+- 'release/\*\*'$"
    }
}
