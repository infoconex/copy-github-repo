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

    It 'documents public advanced-function and automation semantics' {
        $script:styleGuide | Should -Match 'Every manifest-exported public function uses `\[CmdletBinding\(\)\]`'
        $script:styleGuide | Should -Match 'Every state-changing exported command enables `SupportsShouldProcess`'
        $script:styleGuide | Should -Match 'declares an explicit `ConfirmImpact`'
        $script:styleGuide | Should -Match 'gates mutation through `ShouldProcess\(\)` using the command''s PowerShell cmdlet context'
        $script:styleGuide | Should -Match 'delegated execution guard may use a captured `\$PSCmdlet` reference'
        $script:styleGuide | Should -Match 'Supported automation scenarios must not depend on `Read-Host`'
        $script:styleGuide | Should -Match '`Copy-GitHubRepository` is the automation boundary'
        $script:styleGuide | Should -Match 'Routine confirmation bypass and independent safety confirmation are distinct contracts'
        $script:styleGuide | Should -Match 'Use `\[OutputType\(\)\]` when it accurately and stably describes'
    }

    It 'documents deliberate positional-parameter policy rather than analyzer-severity accident' {
        $script:styleGuide | Should -Match 'Avoid positional-parameter invocation where `PSAvoidUsingPositionalParameters` applies'
        $script:styleGuide | Should -Match '`PSAvoidUsingPositionalParameters` promotion is a deliberate project decision'
        (@($script:analyzerSettings.Severity) -join ',') | Should -Be 'Error,Warning'
    }

    It 'defines policy categories used by engineering reviews' {
        foreach ($category in @('Required', 'Preferred', 'Allowed', 'Discouraged', 'Prohibited')) {
            $script:styleGuide | Should -Match ('\*\*{0}\*\*' -f $category)
        }

        $script:styleGuide | Should -Match 'Required.*mandatory engineering contract'
        $script:styleGuide | Should -Match 'Preferred.*normal/default choice'
        $script:styleGuide | Should -Match 'Allowed.*explicitly acceptable alternative'
        $script:styleGuide | Should -Match 'Discouraged.*avoid in new or modified code'
        $script:styleGuide | Should -Match 'Prohibited.*must not be introduced'
    }

    It 'documents the standards decision hierarchy without overriding deliberate project policy' {
        $script:styleGuide | Should -Match 'documented CopyGitHubRepo rule.*takes precedence'
        $script:styleGuide | Should -Match 'Microsoft PowerShell documentation and design guidance'
        $script:styleGuide | Should -Match 'applicable PSScriptAnalyzer rules'
        $script:styleGuide | Should -Match 'PowerShell Practice and Style'
        $script:styleGuide | Should -Match 'established PowerShell community practice'
        $script:styleGuide | Should -Match 'local consistency'
        $script:styleGuide | Should -Match 'Before classifying an inconsistency as a defect'
    }

    It 'keeps the main analyzer gate focused on Error and Warning findings' {
        $script:analyzerSettings.IncludeDefaultRules | Should -BeTrue
        (@($script:analyzerSettings.Severity) -join ',') | Should -Be 'Error,Warning'
        $script:styleGuide | Should -Match '`PSScriptAnalyzerSettings.psd1` is the authoritative machine-readable analyzer configuration'
    }

    It 'enables the adopted industry-standard formatting and language rules' {
        $rules = $script:analyzerSettings.Rules

        foreach ($ruleName in @(
                'PSAvoidExclaimOperator',
                'PSAvoidSemicolonsAsLineTerminators',
                'PSPlaceOpenBrace',
                'PSPlaceCloseBrace',
                'PSUseConsistentIndentation',
                'PSUseConsistentWhitespace',
                'PSUseConsistentParameterSetName',
                'PSUseConsistentParametersKind',
                'PSUseSingleValueFromPipelineParameter',
                'PSUseCorrectCasing',
                'PSAvoidUsingDoubleQuotesForConstantString'
            )) {
            $rules[$ruleName].Enable | Should -BeTrue -Because "$ruleName is part of the adopted PowerShell engineering baseline"
        }

        $rules.PSPlaceOpenBrace.OnSameLine | Should -BeTrue
        $rules.PSPlaceCloseBrace.NoEmptyLineBefore | Should -BeTrue
        $rules.PSUseConsistentIndentation.Kind | Should -Be 'space'
        $rules.PSUseConsistentIndentation.IndentationSize | Should -Be 4
        $rules.PSUseConsistentParametersKind.ParametersKind | Should -Be 'ParamBlock'
        $rules.PSUseConsistentWhitespace.CheckOpenParen | Should -BeTrue
        $rules.PSUseConsistentWhitespace.CheckParameter | Should -BeTrue
        $rules.PSUseConsistentWhitespace.CheckPipeForRedundantWhitespace | Should -BeTrue
        $rules.PSUseCorrectCasing.CheckCommands | Should -BeTrue
        $rules.PSUseCorrectCasing.CheckKeyword | Should -BeTrue
        $rules.PSUseCorrectCasing.CheckOperator | Should -BeTrue
    }

    It 'does not turn subjective or specialized rules into mandatory policy' {
        $rules = $script:analyzerSettings.Rules
        $rules.ContainsKey('PSAvoidLongLines') | Should -BeFalse
        $rules.ContainsKey('PSAlignAssignmentStatement') | Should -BeFalse
        $rules.ContainsKey('PSUseConstrainedLanguageMode') | Should -BeFalse
    }

    It 'documents the analyzer and AST/Pester enforcement boundary' {
        $script:styleGuide | Should -Match '### Pester and AST enforcement'
        $script:styleGuide | Should -Match '`tests/contract/PowerShellSourceConventions\.Tests\.ps1`'
        $script:styleGuide | Should -Match 'explicitly declared parameters use PascalCase'
        $script:styleGuide | Should -Match 'private functions use approved PowerShell verbs with the `Cgr` noun prefix'
        $script:styleGuide | Should -Match 'Public/Private PowerShell source does not use tab indentation'
        $script:styleGuide | Should -Match 'Public command coverage is derived from `FunctionsToExport`'
        $script:styleGuide | Should -Match '`tests/contract/PublicCommandAutomationSemantics\.Tests\.ps1`'
    }

    It 'requires narrow justified analyzer suppressions' {
        $script:styleGuide | Should -Match 'Scope it to the narrowest function, parameter, or statement practical'
        $script:styleGuide | Should -Match 'Name the exact rule being suppressed'
        $script:styleGuide | Should -Match 'Include a nearby comment explaining why'
        $script:styleGuide | Should -Match 'Do not disable a useful rule globally'
    }

    It 'links to durable external PowerShell standards references' {
        $script:styleGuide | Should -Match 'learn\.microsoft\.com/powershell/'
        $script:styleGuide | Should -Match 'github\.com/PoshCode/PowerShellPracticeAndStyle'
    }

    It 'continues recursively analyzing the repository root' {
        $script:testProject | Should -Match '-Path\s+\$repositoryRoot'
        $script:testProject | Should -Match '-Settings\s+\$analyzerSettingsPath'
        $script:testProject | Should -Match '-Recurse'
    }
}
