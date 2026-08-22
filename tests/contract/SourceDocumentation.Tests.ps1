$policyForDiscovery = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'SourceDocumentationPolicy.psd1')
$inlineHelpCases = @($policyForDiscovery.InlinePrivateHelpRequired | ForEach-Object { @{ FunctionName = $_ } })

BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:privatePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/Private'
    $script:documentationPath = Join-Path $repositoryRoot 'docs/engineering/source-code-documentation.md'
    $script:contributingPath = Join-Path $repositoryRoot 'CONTRIBUTING.md'
    $script:policyPath = Join-Path $PSScriptRoot 'SourceDocumentationPolicy.psd1'
    $script:documentation = Get-Content -LiteralPath $script:documentationPath -Raw
    $script:contributing = Get-Content -LiteralPath $script:contributingPath -Raw
    $script:policy = Import-PowerShellDataFile -Path $script:policyPath
    $script:privateFiles = @(
        Get-ChildItem -LiteralPath $script:privatePath -Filter '*.ps1' -File -Recurse |
            Sort-Object FullName
    )
}

Describe 'Source documentation policy' {
    It 'documents every private function and preserves the one-function-per-file boundary' {
        $privateFiles = @($script:privateFiles)
        $privateFiles.Count | Should -BeGreaterThan 0

        foreach ($file in $privateFiles) {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref] $tokens, [ref] $parseErrors)
            @($parseErrors).Count | Should -Be 0 -Because "$($file.Name) must remain valid PowerShell"

            $functions = @($ast.FindAll({
                        param($node)
                        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                    }, $true))
            $functions.Count | Should -Be 1 -Because "$($file.Name) should contain one private function"
            $functions[0].Name | Should -Be $file.BaseName -Because 'private function and file names must stay aligned'
            $script:documentation | Should -Match ([regex]::Escape("``$($functions[0].Name)``")) -Because "$($functions[0].Name) must be present in the maintainer inventory"
        }
    }

    It 'keeps the inline-help boundary list unique and limited to existing private functions' {
        $required = @($script:policy.InlinePrivateHelpRequired)
        $required.Count | Should -BeGreaterThan 0
        @($required | Sort-Object -Unique).Count | Should -Be $required.Count

        foreach ($functionName in $required) {
            @($script:privateFiles | Where-Object BaseName -eq $functionName).Count |
                Should -Be 1 -Because "$functionName is classified as an inline-help safety boundary"
        }
    }

    It '<FunctionName> carries attached comment-based help at the mutation or planning boundary' -ForEach $inlineHelpCases {
        $matchingFiles = @($script:privateFiles | Where-Object BaseName -eq $FunctionName)
        $matchingFiles.Count | Should -Be 1 -Because "$FunctionName should map to one private source file"
        $source = Get-Content -LiteralPath $matchingFiles[0].FullName -Raw
        $pattern = '(?ms)function\s+' + [regex]::Escape($FunctionName) + '\s*\{\s*<#.*?\.SYNOPSIS\b.*?\.DESCRIPTION\b.*?#>'
        $source | Should -Match $pattern -Because "$FunctionName is an explicitly classified safety/planning boundary"
    }

    It 'documents the module manifest and bootstrap files' {
        $moduleFiles = @($script:policy.ModuleFiles)
        @($moduleFiles | Sort-Object -Unique).Count | Should -Be $moduleFiles.Count

        foreach ($relativePath in $moduleFiles) {
            Test-Path -LiteralPath (Join-Path $repositoryRoot $relativePath) -PathType Leaf |
                Should -BeTrue -Because "$relativePath is part of the module documentation policy"
            $script:documentation | Should -Match ([regex]::Escape("``$relativePath``")) -Because "$relativePath must have maintainer-level purpose documentation"
        }
    }

    It 'automatically discovers every significant operational PowerShell script and requires explicit documentation' {
        $discoveredScripts = @(
            Get-ChildItem -LiteralPath $repositoryRoot -Filter '*.ps1' -File | ForEach-Object { $_.Name }
            Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'build') -Filter '*.ps1' -File | ForEach-Object { "build/$($_.Name)" }
            Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'tests/e2e') -Filter '*.ps1' -File | ForEach-Object { "tests/e2e/$($_.Name)" }
        ) | Sort-Object
        $declaredScripts = @($script:policy.OperationalScripts | Sort-Object)

        ($declaredScripts -join "`n") | Should -Be ($discoveredScripts -join "`n") -Because 'new root, build, or E2E scripts must be explicitly classified before the Quality Gate can pass'

        foreach ($relativePath in $declaredScripts) {
            $script:documentation | Should -Match ([regex]::Escape("``$relativePath``")) -Because "$relativePath must have maintainer-level purpose and risk documentation"
        }
    }

    It 'documents the policy for contributors without redundant file-history headers' {
        $script:documentation | Should -Match 'author, creation-date, last-modified, or change-history headers'
        $script:documentation | Should -Match 'Git is the source of truth'
        $script:documentation | Should -Match 'safety and failure semantics'
        $script:documentation | Should -Match 'Avoid comments that merely restate'
        $script:contributing | Should -Match 'docs/engineering/source-code-documentation\.md'
        $script:contributing | Should -Match 'tests/SourceDocumentationPolicy\.psd1'
        $script:contributing | Should -Match 'critical planning and Git/GitHub mutation boundaries'
    }
}
