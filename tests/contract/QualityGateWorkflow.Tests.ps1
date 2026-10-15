BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:workflowPath = Join-Path $repositoryRoot '.github/workflows/validate-project-quality.yml'
    $script:documentationWorkflowPath = Join-Path $repositoryRoot '.github/workflows/validate-documentation.yml'
    $script:deploymentWorkflowPath = Join-Path $repositoryRoot '.github/workflows/deploy-documentation-site.yml'
    $script:codeSecurityWorkflowPath = Join-Path $repositoryRoot '.github/workflows/analyze-code-security.yml'
    $script:actionsSecurityWorkflowPath = Join-Path $repositoryRoot '.github/workflows/analyze-github-actions-security.yml'

    $script:workflow = (Get-Content -LiteralPath $script:workflowPath -Raw) -replace "`r`n?", "`n"
    $script:documentationWorkflow = (Get-Content -LiteralPath $script:documentationWorkflowPath -Raw) -replace "`r`n?", "`n"
    $script:deploymentWorkflow = (Get-Content -LiteralPath $script:deploymentWorkflowPath -Raw) -replace "`r`n?", "`n"
    $script:codeSecurityWorkflow = (Get-Content -LiteralPath $script:codeSecurityWorkflowPath -Raw) -replace "`r`n?", "`n"
    $script:actionsSecurityWorkflow = (Get-Content -LiteralPath $script:actionsSecurityWorkflowPath -Raw) -replace "`r`n?", "`n"

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
        $script:workflow | Should -Match '(?m)^\s+if \(\$baseSha -eq \(''0'' \* 40\)\) \{$'
        $script:workflow | Should -Match '(?ms)if \(\$baseSha -eq \(''0'' \* 40\)\) \{\s+''run-quality=true'' >> \$env:GITHUB_OUTPUT\s+exit 0\s+\}'
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

    It 'requires full Windows Linux and macOS quality results through an always-present gate' {
        $script:workflow | Should -Match '(?m)^    name: Required Project Quality Gate$'
        $script:workflow | Should -Match '(?m)^    needs: \[scope, windows, other-platforms\]$'
        $script:workflow | Should -Match '(?m)^    if: .+always\(\)'
        foreach ($term in @('needs.scope.result', 'needs.windows.result', 'needs.other-platforms.result',
                'needs.scope.outputs.run-quality', "'true', 'false'", "'success'", "'skipped'")) {
            $script:workflow | Should -Match ([regex]::Escape($term))
        }
    }

    It 'creates an always-present documentation PR gate with scoped validation' {
        $pullRequestSection = [regex]::Match(
            $script:documentationWorkflow,
            '(?ms)^  pull_request:\n(.*?)(?=^  workflow_dispatch:)'
        ).Groups[1].Value
        $pullRequestSection | Should -Not -BeNullOrEmpty
        $pullRequestSection | Should -Not -Match '(?m)^    paths:'

        $script:documentationWorkflow | Should -Match '(?m)^    name: Determine Documentation Scope$'
        $script:documentationWorkflow | Should -Match '(?m)^    name: Required Documentation Gate$'
        $script:documentationWorkflow | Should -Match '(?m)^    needs: \[scope, validate\]$'
        $script:documentationWorkflow | Should -Match '(?m)^    if: .+always\(\)'
        foreach ($term in @('needs.scope.result', 'needs.validate.result',
                'needs.scope.outputs.run-documentation', 'git diff --name-only',
                "'true', 'false'", "'success'", "'skipped'",
                'tests/contract/', 'docs/', 'Test-Documentation', 'DevelopmentDependencies')) {
            $script:documentationWorkflow | Should -Match ([regex]::Escape($term))
        }
    }

    It 'classifies representative source documentation workflow and Dependabot PR paths consistently' {
        $qualityMatch = [regex]::Match($script:workflow, '(?m)\$siteOnlyPattern = ''([^'']+)''')
        $securityMatch = [regex]::Match($script:codeSecurityWorkflow, '(?m)\$securityPattern = ''([^'']+)''')
        $documentationMatch = [regex]::Match($script:documentationWorkflow, '(?m)\$documentationPattern = ''([^'']+)''')
        $qualityMatch.Success | Should -BeTrue
        $securityMatch.Success | Should -BeTrue
        $documentationMatch.Success | Should -BeTrue
        $script:actionsSecurityWorkflow | Should -Match ([regex]::Escape('Where-Object { $_ -match ''^\.github/workflows/'' }'))

        $siteOnlyPattern = $qualityMatch.Groups[1].Value
        $securityPattern = $securityMatch.Groups[1].Value
        $documentationPattern = $documentationMatch.Groups[1].Value
        $actionsPattern = '^\.github/workflows/'

        $scenarios = @(
            @{ Label = 'module source'; Paths = @('src/CopyGitHubRepo/Private/Get-CgrSample.ps1'); Quality = $true; Security = $true; Documentation = $false; Actions = $false },
            @{ Label = 'documentation-only'; Paths = @('docs/user/installation.md'); Quality = $false; Security = $false; Documentation = $true; Actions = $false },
            @{ Label = 'CodeQL workflow'; Paths = @('.github/workflows/analyze-github-actions-security.yml'); Quality = $true; Security = $false; Documentation = $false; Actions = $true },
            @{ Label = 'documentation workflow'; Paths = @('.github/workflows/validate-documentation.yml'); Quality = $false; Security = $false; Documentation = $true; Actions = $true },
            @{ Label = 'Dependabot workflow update'; Paths = @('.github/workflows/monitor-dependencies.yml'); Quality = $true; Security = $false; Documentation = $false; Actions = $true },
            @{ Label = 'Dependabot configuration'; Paths = @('.github/dependabot.yml'); Quality = $true; Security = $false; Documentation = $false; Actions = $false },
            @{ Label = 'contract test'; Paths = @('tests/contract/QualityGateWorkflow.Tests.ps1'); Quality = $true; Security = $true; Documentation = $true; Actions = $false },
            @{ Label = 'source and documentation'; Paths = @('src/CopyGitHubRepo/CopyGitHubRepo.psd1', 'docs/product/product-contract.md'); Quality = $true; Security = $true; Documentation = $true; Actions = $false }
        )

        foreach ($scenario in $scenarios) {
            $quality = @($scenario.Paths | Where-Object { $_ -notmatch $siteOnlyPattern }).Count -gt 0
            $security = @($scenario.Paths | Where-Object { $_ -match $securityPattern }).Count -gt 0
            $documentation = @($scenario.Paths | Where-Object { $_ -match $documentationPattern }).Count -gt 0
            $actions = @($scenario.Paths | Where-Object { $_ -match $actionsPattern }).Count -gt 0

            $quality | Should -Be $scenario.Quality -Because $scenario.Label
            $security | Should -Be $scenario.Security -Because $scenario.Label
            $documentation | Should -Be $scenario.Documentation -Because $scenario.Label
            $actions | Should -Be $scenario.Actions -Because $scenario.Label
        }
    }

    It 'executes final gate scripts against accepted and rejected upstream result combinations' {
        $gates = @(
            @{ Name = 'project quality'; Workflow = $script:workflow; Job = 'required-project-quality'; ScopeOutput = 'run-quality'; Dependency = 'other-platforms' },
            @{ Name = 'PowerShell security'; Workflow = $script:codeSecurityWorkflow; Job = 'required-code-security'; ScopeOutput = 'run-security'; Dependency = 'analyze' },
            @{ Name = 'GitHub Actions CodeQL'; Workflow = $script:actionsSecurityWorkflow; Job = 'required-actions-security'; ScopeOutput = 'run-analysis'; Dependency = 'analyze-actions' },
            @{ Name = 'documentation'; Workflow = $script:documentationWorkflow; Job = 'required-documentation'; ScopeOutput = 'run-documentation'; Dependency = 'validate' }
        )
        $scenarios = @(
            @{ Name = 'mandatory success'; Scope = 'success'; Required = 'true'; Dep = 'success'; Windows = 'success'; Pass = $true },
            @{ Name = 'intentional skip'; Scope = 'success'; Required = 'false'; Dep = 'skipped'; Windows = 'success'; Pass = $true },
            @{ Name = 'scope failed'; Scope = 'failure'; Required = 'true'; Dep = 'success'; Windows = 'success'; Pass = $false },
            @{ Name = 'scope cancelled'; Scope = 'cancelled'; Required = 'false'; Dep = 'skipped'; Windows = 'success'; Pass = $false },
            @{ Name = 'scope output missing'; Scope = 'success'; Required = ''; Dep = 'success'; Windows = 'success'; Pass = $false },
            @{ Name = 'scope output invalid'; Scope = 'success'; Required = 'unknown'; Dep = 'success'; Windows = 'success'; Pass = $false },
            @{ Name = 'mandatory job unexpectedly skipped'; Scope = 'success'; Required = 'true'; Dep = 'skipped'; Windows = 'success'; Pass = $false },
            @{ Name = 'inapplicable job unexpectedly ran'; Scope = 'success'; Required = 'false'; Dep = 'success'; Windows = 'success'; Pass = $false },
            @{ Name = 'mandatory job failed'; Scope = 'success'; Required = 'true'; Dep = 'failure'; Windows = 'success'; Pass = $false },
            @{ Name = 'mandatory job cancelled'; Scope = 'success'; Required = 'true'; Dep = 'cancelled'; Windows = 'success'; Pass = $false }
        )

        foreach ($gate in $gates) {
            $jobAnchor = "  $($gate.Job):`n"
            $jobStart = $gate.Workflow.IndexOf($jobAnchor, [StringComparison]::Ordinal)
            $jobStart | Should -BeGreaterOrEqual 0 -Because $gate.Name
            $jobText = $gate.Workflow.Substring($jobStart + $jobAnchor.Length)
            $runAnchor = "        run: |`n"
            $runStart = $jobText.IndexOf($runAnchor, [StringComparison]::Ordinal)
            $runStart | Should -BeGreaterOrEqual 0 -Because $gate.Name
            $body = $jobText.Substring($runStart + $runAnchor.Length) -replace '(?m)^ {10}', ''

            foreach ($scenario in $scenarios) {
                $scriptText = $body.Replace('${{ needs.scope.result }}', $scenario.Scope)
                $scopeExpression = '${{ needs.scope.outputs.' + $gate.ScopeOutput + ' }}'
                $scriptText = $scriptText.Replace($scopeExpression, $scenario.Required)
                $dependencyExpression = '${{ needs.' + $gate.Dependency + '.result }}'
                $scriptText = $scriptText.Replace($dependencyExpression, $scenario.Dep)
                $scriptText = $scriptText.Replace('${{ needs.windows.result }}', $scenario.Windows)
                $scriptText | Should -Not -Match '\$\{\{' -Because "$($gate.Name): $($scenario.Name)"
                $scriptBlock = [scriptblock]::Create($scriptText)

                if ($scenario.Pass) {
                    { & $scriptBlock } | Should -Not -Throw -Because "$($gate.Name): $($scenario.Name)"
                }
                else {
                    { & $scriptBlock } | Should -Throw -Because "$($gate.Name): $($scenario.Name)"
                }
            }

            if ($gate.Job -eq 'required-project-quality') {
                foreach ($windowsResult in @('failure', 'cancelled', 'skipped', '')) {
                    $scriptText = $body.Replace('${{ needs.scope.result }}', 'success')
                    $scriptText = $scriptText.Replace('${{ needs.scope.outputs.run-quality }}', 'false')
                    $scriptText = $scriptText.Replace('${{ needs.windows.result }}', $windowsResult)
                    $scriptText = $scriptText.Replace('${{ needs.other-platforms.result }}', 'skipped')
                    $scriptBlock = [scriptblock]::Create($scriptText)
                    { & $scriptBlock } | Should -Throw -Because "Windows '$windowsResult' must succeed even on documentation-only PRs"
                }
            }
        }
    }
}
