BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:rulesPath = Join-Path $repositoryRoot 'build/PSScriptAnalyzerRules/CopyGitHubRepo.AnalyzerRules.psm1'
    $script:settingsPath = Join-Path $repositoryRoot 'PSScriptAnalyzerSettings.psd1'

    Import-Module $script:rulesPath -Force

    function ConvertTo-CgrDocumentationRuleTestAst {
        param(
            [Parameter(Mandatory)]
            [string] $Source,

            [Parameter(Mandatory)]
            [string] $RelativePath
        )

        $tokens = $null
        $parseErrors = $null
        $filePath = Join-Path $repositoryRoot $RelativePath
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            $Source,
            $filePath,
            [ref] $tokens,
            [ref] $parseErrors
        )
        @($parseErrors).Count | Should -Be 0
        $ast
    }
}

Describe 'PSScriptAnalyzer documentation rule' {
    It 'is enabled together with the default analyzer rules' {
        $settings = Import-PowerShellDataFile -LiteralPath $script:settingsPath

        $settings.IncludeDefaultRules | Should -BeTrue
        @($settings.CustomRulePath) | Should -Contain './build/PSScriptAnalyzerRules/CopyGitHubRepo.AnalyzerRules.psm1'
    }

    It 'reports missing public command help' {
        $ast = ConvertTo-CgrDocumentationRuleTestAst `
            -RelativePath 'src/CopyGitHubRepo/Public/Invoke-CgrSample.ps1' `
            -Source 'function Invoke-CgrSample { param() }'

        $results = @(Measure-CgrDocumentation -ScriptBlockAst $ast)

        $results.Count | Should -Be 1
        $results[0].RuleName | Should -Be 'Measure-CgrDocumentation'
        $results[0].Message | Should -Match 'Public function.*requires comment-based help'
    }

    It 'accepts public command help with synopsis and description' {
        $source = @'
function Invoke-CgrSample {
    <#
    .SYNOPSIS
    Runs the sample operation.

    .DESCRIPTION
    Demonstrates a documented public command for analyzer-rule testing.
    #>
    param()
}
'@
        $ast = ConvertTo-CgrDocumentationRuleTestAst `
            -RelativePath 'src/CopyGitHubRepo/Public/Invoke-CgrSample.ps1' `
            -Source $source

        @(Measure-CgrDocumentation -ScriptBlockAst $ast).Count | Should -Be 0
    }

    It 'reports private functions missing from the maintainer inventory' {
        $ast = ConvertTo-CgrDocumentationRuleTestAst `
            -RelativePath 'src/CopyGitHubRepo/Private/Utility/Invoke-CgrUndocumentedSample.ps1' `
            -Source 'function Invoke-CgrUndocumentedSample { param() }'

        $results = @(Measure-CgrDocumentation -ScriptBlockAst $ast)

        $results.Message | Should -Match 'must be documented in docs/engineering/source-code-documentation.md'
    }

    It 'reports newly added operational scripts that are not classified' {
        $ast = ConvertTo-CgrDocumentationRuleTestAst `
            -RelativePath 'build/Invoke-CgrUndocumentedBuild.ps1' `
            -Source '[CmdletBinding()] param()'

        $results = @(Measure-CgrDocumentation -ScriptBlockAst $ast)

        $results.Count | Should -Be 1
        $results[0].Message | Should -Match 'must be classified in tests/SourceDocumentationPolicy.psd1'
    }
}
