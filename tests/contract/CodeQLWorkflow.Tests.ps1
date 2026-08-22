BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:workflowPath = Join-Path $repositoryRoot '.github/workflows/analyze-github-actions-security.yml'
    $script:workflow = (Get-Content -LiteralPath $script:workflowPath -Raw) -replace "`r`n?", "`n"
}

Describe 'GitHub Actions security analysis workflow contract' {
    It 'uses the purpose-oriented workflow name' {
        $script:workflow | Should -Match '(?m)^name: Analyze GitHub Actions Security$'
    }

    It 'analyzes GitHub Actions workflows on relevant changes and on a schedule' {
        $script:workflow | Should -Match '(?m)^  push:$'
        $script:workflow | Should -Match '(?m)^  pull_request:$'
        $script:workflow | Should -Match "(?m)^      - '\.github/workflows/\*\*'$"
        $script:workflow | Should -Match '(?m)^  schedule:$'
        $script:workflow | Should -Match '(?m)^    - cron:'
        $script:workflow | Should -Match '(?m)^  workflow_dispatch:$'
    }

    It 'uses least-privilege permissions required for code scanning' {
        $script:workflow | Should -Match '(?ms)^permissions:\s+contents: read\s*$'
        $script:workflow | Should -Match '(?ms)^    permissions:\s+actions: read\s+contents: read\s+security-events: write\s*$'
        $script:workflow | Should -Not -Match '(?m)^\s+(issues|pull-requests|packages|id-token): write$'
        $script:workflow | Should -Not -Match '(?m)^\s*pull_request_target:'
    }

    It 'pins checkout and CodeQL actions to immutable commit SHAs' {
        $script:workflow | Should -Match 'actions/checkout@[0-9a-f]{40}'
        $script:workflow | Should -Match 'github/codeql-action/init@[0-9a-f]{40}'
        $script:workflow | Should -Match 'github/codeql-action/analyze@[0-9a-f]{40}'
        $script:workflow | Should -Not -Match 'github/codeql-action/(?:init|analyze)@v[0-9]'
        $script:workflow | Should -Match '(?m)^\s+persist-credentials: false$'
    }

    It 'scans only the supported GitHub Actions language with extended security queries' {
        $script:workflow | Should -Match '(?m)^\s+languages: actions$'
        $script:workflow | Should -Match '(?m)^\s+queries: security-extended$'
        $script:workflow | Should -Match '(?m)^\s+category: /language:actions$'
        $script:workflow | Should -Not -Match '(?m)^\s+languages: powershell$'
    }
}
