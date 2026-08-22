BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:styleGuide = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/engineering/powershell-style-guide.md') -Raw
    $script:contributing = Get-Content -LiteralPath (Join-Path $repositoryRoot 'CONTRIBUTING.md') -Raw
    $script:testProject = Get-Content -LiteralPath (Join-Path $repositoryRoot 'build/Test-Project.ps1') -Raw
    $script:analyzerSettings = Import-PowerShellDataFile -LiteralPath (Join-Path $repositoryRoot 'PSScriptAnalyzerSettings.psd1')
}

Describe 'Project PowerShell engineering policy' {
    It 'documents the Cgr private helper naming convention and approved public naming' {
        $script:styleGuide | Should -Match 'approved PowerShell verbs'
        $script:styleGuide | Should -Match 'singular nouns for public commands'
        $script:styleGuide | Should -Match 'Private helpers retain the repository-specific `Cgr` prefix'
    }

    It 'documents required language and formatting conventions' {
        $script:styleGuide | Should -Match 'Indent with four spaces'
        $script:styleGuide | Should -Match 'opening braces remain on the same line'
        $script:styleGuide | Should -Match 'Use `-not` rather than the `!` alias'
        $script:styleGuide | Should -Match 'Put `\$null` on the left side'
        $script:styleGuide | Should -Match 'Use single-quoted strings for literals'
    }

    It 'documents command-design and testing conventions' {
        $script:styleGuide | Should -Match 'Public commands live under `src/CopyGitHubRepo/Public`'
        $script:styleGuide | Should -Match 'Internal helpers live under `src/CopyGitHubRepo/Private`'
        $script:styleGuide | Should -Match 'comment-based help'
        $script:styleGuide | Should -Match 'SupportsShouldProcess'
        $script:styleGuide | Should -Match 'Use Pester for repository tests'
        $script:styleGuide | Should -Match 'structured objects on the success pipeline'
    }

    It 'distinguishes required policy from readability preferences' {
        $script:styleGuide | Should -Match '\*\*Required\*\*'
        $script:styleGuide | Should -Match '\*\*Preferred\*\*'
        $script:styleGuide | Should -Match 'Prefer splatting when an invocation has many arguments'
        $script:styleGuide | Should -Match 'Do not convert stable readable calls to splatting solely for stylistic uniformity'
    }

    It 'keeps the contributor guide linked to the project style guide' {
        $script:contributing | Should -Match 'docs/engineering/powershell-style-guide\.md'
        $script:contributing | Should -Match 'Retain the `Cgr` prefix for private helpers'
    }

    It 'enables only the selected additional analyzer rules with project settings' {
        $script:analyzerSettings.IncludeDefaultRules | Should -BeTrue
        (@($script:analyzerSettings.Severity) -join ',') | Should -Be 'Error,Warning'

        $rules = $script:analyzerSettings.Rules
        (@($rules.Keys | Sort-Object) -join ',') | Should -Be 'PSAvoidExclaimOperator,PSUseConsistentWhitespace'

        $rules.PSAvoidExclaimOperator.Enable | Should -BeTrue
        $rules.PSUseConsistentWhitespace.Enable | Should -BeTrue
        $rules.PSUseConsistentWhitespace.CheckOpenParen | Should -BeFalse
        $rules.PSUseConsistentWhitespace.CheckParameter | Should -BeFalse
    }

    It 'documents why every explicitly enabled analyzer rule exists and why noisy candidates are excluded' {
        foreach ($ruleName in $script:analyzerSettings.Rules.Keys) {
            $escapedRuleName = [regex]::Escape(('`{0}`' -f $ruleName))
            $script:styleGuide | Should -Match $escapedRuleName
        }

        $script:styleGuide | Should -Match 'whitespace consistency around braces, operators, separators, and pipelines'
        $script:styleGuide | Should -Match 'opening-parenthesis check is intentionally disabled'
        $script:styleGuide | Should -Match 'keeps boolean negation explicit as `-not`'
        $script:styleGuide | Should -Match '`PSUseConsistentIndentation` was evaluated but is not enabled'
        $script:styleGuide | Should -Match 'widespread indentation warnings even when pipeline normalization is disabled'
        $script:styleGuide | Should -Match '`PSUseCorrectCasing` is not enabled because it reports at Information severity'
    }

    It 'requires narrow justified analyzer suppressions' {
        $script:styleGuide | Should -Match 'Scope it to the narrowest function, parameter, or statement practical'
        $script:styleGuide | Should -Match 'Name the exact rule being suppressed'
        $script:styleGuide | Should -Match 'Include a nearby comment explaining why'
        $script:styleGuide | Should -Match 'Do not disable a useful rule globally'
    }

    It 'continues recursively analyzing the repository root' {
        $script:testProject | Should -Match '-Path\s+\$repositoryRoot'
        $script:testProject | Should -Match '-Settings\s+\$analyzerSettingsPath'
        $script:testProject | Should -Match '-Recurse'
    }
}
