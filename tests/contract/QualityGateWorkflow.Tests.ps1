BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:workflowPath = Join-Path $repositoryRoot '.github/workflows/validate-project-quality.yml'
    $script:documentationWorkflowPath = Join-Path $repositoryRoot '.github/workflows/validate-documentation.yml'
    $script:deploymentWorkflowPath = Join-Path $repositoryRoot '.github/workflows/deploy-documentation-site.yml'

    $script:workflow = (Get-Content -LiteralPath $script:workflowPath -Raw) -replace "`r`n?", "`n"
    $script:documentationWorkflow = (Get-Content -LiteralPath $script:documentationWorkflowPath -Raw) -replace "`r`n?", "`n"
    $script:deploymentWorkflow = (Get-Content -LiteralPath $script:deploymentWorkflowPath -Raw) -replace "`r`n?", "`n"

    $siteOnlyPatternMatch = [regex]::Match($script:workflow, '(?m)^\s*\$siteOnlyPattern = ''([^'']+)''$')
    if (-not $siteOnlyPatternMatch.Success) {
        throw 'Unable to locate the site-only quality-scope pattern.'
    }
    $script:siteOnlyPattern = $siteOnlyPatternMatch.Groups[1].Value

    $script:renderedSitePaths = @(
        @{ Path = '_config.yml'; Trigger = '_config.yml' },
        @{ Path = '_data/navigation.yml'; Trigger = '_data/**' },
        @{ Path = '_layouts/default.html'; Trigger = '_layouts/**' },
        @{ Path = 'assets/css/site.css'; Trigger = 'assets/**' },
        @{ Path = 'search-index.json'; Trigger = 'search-index.json' },
        @{ Path = 'docs/product/architecture.md'; Trigger = 'docs/**' },
        @{ Path = 'README.md'; Trigger = 'README.md' },
        @{ Path = 'CHANGELOG.md'; Trigger = 'CHANGELOG.md' },
        @{ Path = 'CODE_OF_CONDUCT.md'; Trigger = 'CODE_OF_CONDUCT.md' },
        @{ Path = 'CONTRIBUTING.md'; Trigger = 'CONTRIBUTING.md' },
        @{ Path = 'SECURITY.md'; Trigger = 'SECURITY.md' },
        @{ Path = 'LICENSE'; Trigger = 'LICENSE' }
    )
}

Describe 'Validate Project Quality workflow contract' {
    It 'uses the purpose-oriented workflow name' {
        $script:workflow | Should -Match '(?m)^name: Validate Project Quality$'
    }

    It 'always appears for main pushes and pull requests targeting main or release integration branches' {
        $script:workflow | Should -Match '(?ms)^  push:\s+branches:\s+- main\s*(?=^  pull_request:)'
        $script:workflow | Should -Match "(?ms)^  pull_request:\s+branches:\s+- main\s+- 'release/\*\*'\s*(?=^  workflow_dispatch:)"
        $script:workflow | Should -Not -Match '(?m)^\s+paths-ignore:'
    }

    It 'uses an internal scope decision while preserving the required Windows check for site-only changes' {
        foreach ($term in @(
                'Determine Quality Scope',
                'run-quality',
                '_config\\.yml',
                '_data/',
                '_layouts/',
                'assets/',
                'search-index\\.json',
                'docs/',
                'README\\.md',
                'CHANGELOG\\.md',
                'CODE_OF_CONDUCT\\.md',
                'CONTRIBUTING\\.md',
                'SECURITY\\.md',
                'LICENSE',
                'deploy-documentation-site',
                'validate-documentation',
                'Record documentation-only validation'
            )) {
            $script:workflow | Should -Match $term
        }

        $script:workflow | Should -Match '(?m)^  windows:$'
        $script:workflow | Should -Match '(?m)^    name: Validate PowerShell \(windows-latest\)$'
        $script:workflow | Should -Match "(?m)^        if: \$\{\{ needs\.scope\.outputs\.run-quality != 'true' \}\}$"
        $script:workflow | Should -Match "(?m)^  other-platforms:\n    name: Validate PowerShell \(\$\{\{ matrix\.os \}\}\)\n    needs: scope\n    if: \$\{\{ needs\.scope\.outputs\.run-quality == 'true' \}\}$"
    }

    It 'runs full quality validation for new ref pushes with an all-zero before SHA' {
        $script:workflow | Should -Match "(?m)^\s+if \(\$baseSha -eq \('0' \* 40\)\) \{$"
        $script:workflow | Should -Match "(?ms)if \(\$baseSha -eq \('0' \* 40\)\) \{\s+'run-quality=true' >> \$env:GITHUB_OUTPUT\s+exit 0\s+\}"
    }

    It 'classifies every rendered-site source as site-only without classifying code as site-only' {
        foreach ($entry in $script:renderedSitePaths) {
            $entry.Path | Should -Match $script:siteOnlyPattern
        }

        'src/CopyGitHubRepo/Public/Copy-GitHubRepository.ps1' | Should -Not -Match $script:siteOnlyPattern
        'tests/unit/CopyGitHubRepo.Tests.ps1' | Should -Not -Match $script:siteOnlyPattern
    }

    It 'keeps rendered-site triggers aligned across documentation validation and deployment' {
        foreach ($entry in $script:renderedSitePaths) {
            $triggerPattern = "(?m)^\s+- '$([regex]::Escape($entry.Trigger))'$"
            $script:documentationWorkflow | Should -Match $triggerPattern
            $script:deploymentWorkflow | Should -Match $triggerPattern
        }
    }

    It 'keeps validation-only tooling paths out of the rendered-site deployment contract' {
        foreach ($path in @(
                'build/DevelopmentDependencies.psd1',
                'build/Install-DevelopmentDependencies.ps1',
                'build/Test-Documentation.ps1',
                'tests/contract/**'
            )) {
            $escapedPath = [regex]::Escape($path)
            $script:documentationWorkflow | Should -Match "(?m)^\s+- '$escapedPath'$"
            $script:deploymentWorkflow | Should -Not -Match "(?m)^\s+- '$escapedPath'$"
        }
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

    It 'runs categorized tests on all supported runner platforms when required' {
        foreach ($runner in @('windows-latest', 'ubuntu-latest', 'macos-latest')) {
            $script:workflow | Should -Match ([regex]::Escape($runner))
        }

        $script:workflow | Should -Match '(?m)^\s+fail-fast: false$'
        $script:workflow | Should -Match '(?m)^\s+run: \./build/Install-DevelopmentDependencies\.ps1$'
        foreach ($category in @('Unit', 'Integration', 'Contract')) {
            $script:workflow | Should -Match ('(?m)^\s+run: \./build/Test-Project\.ps1 -Category {0} -SkipAnalysis(?: -CollectCoverage)?$' -f $category)
        }
        $script:workflow | Should -Match '(?m)^\s+name: Validate PowerShell \(\$\{\{ matrix\.os \}\}\)$'
    }

    It 'collects Windows coverage during categorized tests and aggregates without rerunning tests' {
        foreach ($category in @('Unit', 'Integration', 'Contract')) {
            $script:workflow | Should -Match ('(?m)^\s+run: \./build/Test-Project\.ps1 -Category {0} -SkipAnalysis -CollectCoverage$' -f $category)
        }

        $script:workflow | Should -Match '(?m)^\s+run: \./build/Test-Project\.ps1 -CoverageOnly$'
        $script:workflow | Should -Not -Match '(?m)^\s+run: \./build/Test-Project\.ps1 -CoverageOnly -SkipAnalysis$'
    }

    It 'separates Windows static analysis, tests, coverage, and package validation into visible phases' {
        foreach ($stepName in @(
                'Static analysis',
                'Unit tests',
                'Integration tests',
                'Contract tests',
                'Code coverage',
                'Build and validate PowerShell Gallery package'
            )) {
            $script:workflow | Should -Match ('(?m)^      - name: {0}$' -f [regex]::Escape($stepName))
        }

        $script:workflow | Should -Match '(?m)^\s+run: \./build/Test-Project\.ps1 -AnalysisOnly$'
    }
}
