BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:rulesPath = Join-Path $repositoryRoot 'build/PSScriptAnalyzerRules/CopyGitHubRepo.AnalyzerRules.psm1'
    $script:settingsPath = Join-Path $repositoryRoot 'PSScriptAnalyzerSettings.psd1'

    Import-Module PSScriptAnalyzer -ErrorAction Stop
    Import-Module $script:rulesPath -Force

    function ConvertTo-CgrSecurityRuleTestAst {
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

Describe 'PSScriptAnalyzer security rules' {
    It 'is loaded through the normal analyzer settings path' {
        $settings = Import-PowerShellDataFile -LiteralPath $script:settingsPath

        @($settings.CustomRulePath) | Should -Contain './build/PSScriptAnalyzerRules/CopyGitHubRepo.AnalyzerRules.psm1'
        $settings.IncludeDefaultRules | Should -BeTrue
    }

    It 'detects Invoke-Expression dynamic evaluation' {
        $ast = ConvertTo-CgrSecurityRuleTestAst `
            -RelativePath 'src/CopyGitHubRepo/Private/Utility/Invoke-CgrSample.ps1' `
            -Source 'Invoke-Expression $commandText'

        $results = @(Measure-CgrSecurity -ScriptBlockAst $ast)

        $results.Count | Should -Be 1
        $results[0].RuleName | Should -Be 'Measure-CgrSecurity'
        $results[0].Message | Should -Match 'Dynamic expression evaluation is prohibited'
    }

    It 'detects explicit shell interpretation' {
        $ast = ConvertTo-CgrSecurityRuleTestAst `
            -RelativePath 'build/Invoke-CgrSample.ps1' `
            -Source "bash -c 'echo unsafe'"

        $results = @(Measure-CgrSecurity -ScriptBlockAst $ast)

        $results.Count | Should -Be 1
        $results[0].Message | Should -Match 'Shell interpretation'
    }

    It 'detects direct Git and GitHub CLI invocation from module source' {
        $ast = ConvertTo-CgrSecurityRuleTestAst `
            -RelativePath 'src/CopyGitHubRepo/Private/Git/Invoke-CgrSample.ps1' `
            -Source 'git status; gh repo view owner/repo'

        $results = @(Measure-CgrSecurity -ScriptBlockAst $ast)

        $results.Count | Should -Be 2
        foreach ($result in $results) {
            $result.Message | Should -Match 'centralized process boundary'
        }
    }

    It 'accepts the approved native process boundary' {
        $ast = ConvertTo-CgrSecurityRuleTestAst `
            -RelativePath 'src/CopyGitHubRepo/Private/Git/Invoke-CgrSample.ps1' `
            -Source 'Invoke-CgrNativeCommand -FilePath $gitPath -ArgumentList @("status")'

        @(Measure-CgrSecurity -ScriptBlockAst $ast).Count | Should -Be 0
    }

    It 'allows direct native invocation only from the centralized process wrapper path' {
        $ast = ConvertTo-CgrSecurityRuleTestAst `
            -RelativePath 'src/CopyGitHubRepo/Private/Git/Invoke-CgrNativeCommand.ps1' `
            -Source 'git status'

        @(Measure-CgrSecurity -ScriptBlockAst $ast).Count | Should -Be 0
    }

    It 'detects direct diagnostic emission of secret-bearing variables' {
        $ast = ConvertTo-CgrSecurityRuleTestAst `
            -RelativePath 'src/CopyGitHubRepo/Private/Utility/Invoke-CgrSample.ps1' `
            -Source 'Write-Verbose $accessToken'

        $results = @(Measure-CgrSecurity -ScriptBlockAst $ast)

        $results.Count | Should -Be 1
        $results[0].Message | Should -Match 'must not be written directly to output or diagnostics'
    }

    It 'accepts non-sensitive diagnostic status text' {
        $ast = ConvertTo-CgrSecurityRuleTestAst `
            -RelativePath 'src/CopyGitHubRepo/Private/Utility/Invoke-CgrSample.ps1' `
            -Source "Write-Verbose 'GitHub authentication is configured.'"

        @(Measure-CgrSecurity -ScriptBlockAst $ast).Count | Should -Be 0
    }

    It 'does not scan test fixture source as production policy' {
        $ast = ConvertTo-CgrSecurityRuleTestAst `
            -RelativePath 'tests/Sample.Tests.ps1' `
            -Source 'Invoke-Expression $fixture'

        @(Measure-CgrSecurity -ScriptBlockAst $ast).Count | Should -Be 0
    }
}
