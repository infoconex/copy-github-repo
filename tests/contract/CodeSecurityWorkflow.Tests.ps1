BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:workflowPath = Join-Path $repositoryRoot '.github/workflows/analyze-code-security.yml'
    $script:workflow = (Get-Content -LiteralPath $script:workflowPath -Raw) -replace "`r`n?", "`n"
    $script:settingsPath = Join-Path $repositoryRoot 'PSScriptAnalyzerSecuritySettings.psd1'
    $script:settings = Import-PowerShellDataFile -LiteralPath $script:settingsPath
}

Describe 'Analyze Code Security workflow contract' {
    It 'always appears for main pushes and pull requests and scopes expensive work internally' {
        $script:workflow | Should -Match '(?m)^name: Analyze Code Security$'
        $script:workflow | Should -Match '(?ms)^  push:\s+branches:\s+- main\s*(?=^  pull_request:)'
        $script:workflow | Should -Match '(?ms)^  pull_request:\s+branches:\s+- main\s*(?=^  workflow_dispatch:)'
        $script:workflow | Should -Not -Match '(?m)^\s+paths:'
        $script:workflow | Should -Match 'Determine Security Scope'
        $script:workflow | Should -Match 'run-security'
        foreach ($term in @('src/', 'build/', 'tests/', 'PSScriptAnalyzerSecuritySettings', 'analyze-code-security')) {
            $script:workflow | Should -Match ([regex]::Escape($term))
        }
        $script:workflow | Should -Match "(?m)^    if: \$\{\{ needs\.scope\.outputs\.run-security == 'true' \}\}$"
        $script:workflow | Should -Match '(?m)^  workflow_dispatch:$'
    }

    It 'uses read-only repository permissions and immutable action pins' {
        $script:workflow | Should -Match '(?ms)^permissions:\s+contents: read\s*$'
        $script:workflow | Should -Not -Match '(?m)^\s*pull_request_target:'
        $script:workflow | Should -Not -Match '(?i)secrets\.'
        $script:workflow | Should -Match 'actions/checkout@[0-9a-f]{40}'
        $script:workflow | Should -Match 'actions/cache@[0-9a-f]{40}'
        $script:workflow | Should -Match 'actions/upload-artifact@[0-9a-f]{40}'
        $script:workflow | Should -Match '(?m)^\s+persist-credentials: false$'
    }

    It 'uses PSScriptAnalyzer and targeted security behavior tests rather than CodeQL for PowerShell' {
        $script:workflow | Should -Match 'Invoke-ScriptAnalyzer'
        $script:workflow | Should -Match 'PSScriptAnalyzerSecuritySettings\.psd1'
        $script:workflow | Should -Match 'PSScriptAnalyzerSecurityRules\.Tests\.ps1'
        $script:workflow | Should -Match 'GitHubApiAdapters\.Tests\.ps1'
        $script:workflow | Should -Match 'SameNameSafety\.Tests\.ps1'
        $script:workflow | Should -Match 'StaleStateSafety\.Tests\.ps1'
        $script:workflow | Should -Not -Match 'github/codeql-action/'
        $script:workflow | Should -Not -Match '(?m)^\s+languages: powershell$'
    }

    It 'defines a narrow PowerShell security analyzer profile' {
        $script:settings.IncludeDefaultRules | Should -BeFalse
        $script:settings.CustomRulePath | Should -Contain './build/PSScriptAnalyzerRules/CopyGitHubRepo.AnalyzerRules.psm1'
        $script:settings.IncludeRules | Should -Contain 'Measure-CgrSecurity'
        $script:settings.IncludeRules | Should -Contain 'PSAvoidUsingInvokeExpression'
        $script:settings.IncludeRules | Should -Contain 'PSAvoidUsingPlainTextForPassword'
        $script:settings.IncludeRules.Count | Should -BeLessThan 10
    }
}
