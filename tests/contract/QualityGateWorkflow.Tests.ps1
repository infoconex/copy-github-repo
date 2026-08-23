BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:workflowPath = Join-Path $repositoryRoot '.github/workflows/validate-project-quality.yml'
    $script:workflow = (Get-Content -LiteralPath $script:workflowPath -Raw) -replace "`r`n?", "`n"
}

Describe 'Validate Project Quality workflow contract' {
    It 'uses the purpose-oriented workflow name' {
        $script:workflow | Should -Match '(?m)^name: Validate Project Quality$'
    }

    It 'always appears for pushes and pull requests targeting main' {
        $script:workflow | Should -Match '(?ms)^  push:\s+branches:\s+- main\s*(?=^  pull_request:)'
        $script:workflow | Should -Match '(?ms)^  pull_request:\s+branches:\s+- main\s*(?=^  workflow_dispatch:)'
        $script:workflow | Should -Not -Match '(?m)^\s+paths-ignore:'
    }

    It 'uses an internal scope decision while preserving matrix check contexts for site-only changes' {
        foreach ($term in @(
            'Determine Quality Scope',
            'run-quality',
            '_config\\.yml',
            '_data/',
            '_layouts/',
            'assets/',
            'docs/',
            'README\\.md',
            'CHANGELOG\\.md',
            'SECURITY\\.md',
            'deploy-documentation-site',
            'validate-documentation',
            'Record documentation-only skip'
        )) {
            $script:workflow | Should -Match $term
        }

        $script:workflow | Should -Not -Match "(?m)^    if: \$\{\{ needs\.scope\.outputs\.run-quality == 'true' \}\}$"
        $script:workflow | Should -Match "(?m)^        if: \$\{\{ needs\.scope\.outputs\.run-quality != 'true' \}\}$"
        $script:workflow | Should -Match "(?m)^        if: \$\{\{ needs\.scope\.outputs\.run-quality == 'true' \}\}$"
    }

    It 'preserves reusable and manual workflow entry points' {
        $script:workflow | Should -Match '(?m)^  workflow_dispatch:$'
        $script:workflow | Should -Match '(?m)^  workflow_call:$'
        $script:workflow | Should -Match "workflow_dispatch', 'workflow_call"
    }

    It 'keeps pull request validation read-only and fork safe' {
        $script:workflow | Should -Match '(?ms)^permissions:\s+contents: read\s*$'
        $script:workflow | Should -Not -Match '(?m)^\s*pull_request_target:'
        $script:workflow | Should -Not -Match '(?i)(PSGallery|NUGET_API_KEY|API_KEY|secrets\.)'
        $script:workflow | Should -Match '(?ms)persist-credentials: false'
    }

    It 'runs the same quality gate on all supported runner platforms when required' {
        foreach ($runner in @('windows-latest', 'ubuntu-latest', 'macos-latest')) {
            $script:workflow | Should -Match ([regex]::Escape("- $runner"))
        }

        $script:workflow | Should -Match '(?m)^\s+fail-fast: false$'
        $script:workflow | Should -Match '(?m)^\s+run: \./build/Install-DevelopmentDependencies\.ps1$'
        $script:workflow | Should -Match '(?m)^\s+run: \./build/Test-Project\.ps1$'
        $script:workflow | Should -Match '(?m)^\s+name: Validate PowerShell \(\$\{\{ matrix\.os \}\}\)$'
    }
}
