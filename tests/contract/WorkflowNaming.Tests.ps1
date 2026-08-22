BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:workflowRoot = Join-Path $repositoryRoot '.github/workflows'
    $script:expectedWorkflows = [ordered] @{
        'analyze-code-security.yml' = 'Analyze Code Security'
        'analyze-github-actions-security.yml' = 'Analyze GitHub Actions Security'
        'characterize-repository-scale.yml' = 'Characterize Repository Scale'
        'deploy-documentation-site.yml' = 'Deploy Documentation Site'
        'monitor-dependencies.yml' = 'Monitor Dependencies'
        'publish-release.yml' = 'Publish Release'
        'validate-documentation.yml' = 'Validate Documentation'
        'validate-project-quality.yml' = 'Validate Project Quality'
    }
}

Describe 'GitHub Actions workflow naming contract' {
    It 'uses the exact supported workflow file inventory' {
        $actualNames = @(
            Get-ChildItem -LiteralPath $script:workflowRoot -Filter '*.yml' -File |
                Select-Object -ExpandProperty Name |
                Sort-Object
        )
        $expectedNames = @($script:expectedWorkflows.Keys | Sort-Object)

        $actualNames | Should -Be $expectedNames
    }

    It 'uses lowercase kebab-case filenames and exact purpose-oriented display names' {
        foreach ($entry in $script:expectedWorkflows.GetEnumerator()) {
            $entry.Key | Should -Match '^[a-z0-9]+(?:-[a-z0-9]+)*\.yml$'

            $workflowPath = Join-Path $script:workflowRoot $entry.Key
            $firstLine = Get-Content -LiteralPath $workflowPath -TotalCount 1
            $firstLine | Should -Be "name: $($entry.Value)"
        }
    }
}
