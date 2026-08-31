BeforeAll {
    $script:repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:moduleRoot = Join-Path $script:repositoryRoot 'src/CopyGitHubRepo'
    $script:publicRoot = Join-Path $script:moduleRoot 'Public'
    $script:privateRoot = Join-Path $script:moduleRoot 'Private'
    $script:manifestPath = Join-Path $script:moduleRoot 'CopyGitHubRepo.psd1'
    $script:manifest = Import-PowerShellDataFile -LiteralPath $script:manifestPath
    $script:approvedVerbs = @(Get-Verb | Select-Object -ExpandProperty Verb)

    $script:sourceFiles = @(
        Get-ChildItem -LiteralPath $script:publicRoot, $script:privateRoot -Filter '*.ps1' -File -Recurse |
            Sort-Object FullName
    )

    function Get-ParsedPowerShellSource {
        param(
            [Parameter(Mandatory)]
            [System.IO.FileInfo] $File
        )

        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $File.FullName,
            [ref] $tokens,
            [ref] $parseErrors
        )

        [pscustomobject]@{
            File = $File
            Ast = $ast
            ParseErrors = @($parseErrors)
        }
    }

    $script:parsedSources = @(
        foreach ($sourceFile in $script:sourceFiles) {
            Get-ParsedPowerShellSource -File $sourceFile
        }
    )
}

Describe 'PowerShell source convention contracts' {
    It 'parses every governed public and private source file cleanly' {
        $parseFailures = @(
            foreach ($parsedSource in $script:parsedSources) {
                foreach ($parseError in $parsedSource.ParseErrors) {
                    '{0}:{1}:{2} {3}' -f $parsedSource.File.FullName, $parseError.Extent.StartLineNumber, $parseError.Extent.StartColumnNumber, $parseError.Message
                }
            }
        )

        $parseFailures | Should -BeNullOrEmpty
    }

    It 'requires PascalCase for explicitly declared parameters' {
        $violations = @(
            foreach ($parsedSource in $script:parsedSources) {
                $parameterAsts = @(
                    $parsedSource.Ast.FindAll({
                            param($node)
                            $node -is [System.Management.Automation.Language.ParameterAst]
                        }, $true)
                )

                foreach ($parameterAst in $parameterAsts) {
                    $parameterName = $parameterAst.Name.VariablePath.UserPath
                    if ($parameterName -cnotmatch '^[A-Z][A-Za-z0-9]*$') {
                        '{0}:{1} parameter ${2} must use PascalCase.' -f $parsedSource.File.FullName, $parameterAst.Extent.StartLineNumber, $parameterName
                    }
                }
            }
        )

        $violations | Should -BeNullOrEmpty
    }

    It 'requires private helper functions to use approved verbs and the Cgr noun prefix' {
        $violations = @(
            foreach ($parsedSource in $script:parsedSources | Where-Object { $_.File.FullName.StartsWith($script:privateRoot, [StringComparison]::OrdinalIgnoreCase) }) {
                $functionAsts = @(
                    $parsedSource.Ast.FindAll({
                            param($node)
                            $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                        }, $true)
                )

                foreach ($functionAst in $functionAsts) {
                    if ($functionAst.Name -notmatch '^(?<Verb>[^-]+)-(?<Noun>.+)$') {
                        '{0}:{1} private function {2} must use Verb-Noun naming.' -f $parsedSource.File.FullName, $functionAst.Extent.StartLineNumber, $functionAst.Name
                        continue
                    }

                    if ($Matches.Verb -notin $script:approvedVerbs) {
                        '{0}:{1} private function {2} uses unapproved verb {3}.' -f $parsedSource.File.FullName, $functionAst.Extent.StartLineNumber, $functionAst.Name, $Matches.Verb
                    }

                    if ($Matches.Noun -cnotmatch '^Cgr[A-Z0-9]') {
                        '{0}:{1} private function {2} must use the Cgr noun prefix.' -f $parsedSource.File.FullName, $functionAst.Extent.StartLineNumber, $functionAst.Name
                    }
                }
            }
        )

        $violations | Should -BeNullOrEmpty
    }

    It 'requires every exported function to have one matching public source file and approved public naming' {
        $exportedFunctions = @($script:manifest.FunctionsToExport)
        $publicFiles = @(Get-ChildItem -LiteralPath $script:publicRoot -Filter '*.ps1' -File)
        $publicFileCommands = @($publicFiles | ForEach-Object { $_.BaseName })
        $violations = @()

        foreach ($commandName in $exportedFunctions) {
            $matchingFiles = @($publicFiles | Where-Object { $_.BaseName -ceq $commandName })
            if ($matchingFiles.Count -ne 1) {
                $violations += "Exported command $commandName must have exactly one matching Public/$commandName.ps1 source file."
            }

            if ($commandName -notmatch '^(?<Verb>[^-]+)-(?<Noun>.+)$') {
                $violations += "Exported command $commandName must use Verb-Noun naming."
                continue
            }

            if ($Matches.Verb -notin $script:approvedVerbs) {
                $violations += "Exported command $commandName uses unapproved verb $($Matches.Verb)."
            }

            if ($Matches.Noun -cmatch '^Cgr') {
                $violations += "Exported command $commandName must not use the private Cgr noun prefix."
            }
        }

        foreach ($publicCommand in $publicFileCommands) {
            if ($publicCommand -cnotin $exportedFunctions) {
                $violations += "Public source file $publicCommand.ps1 is not listed in FunctionsToExport."
            }
        }

        $violations | Should -BeNullOrEmpty
    }

    It 'rejects tab indentation in governed PowerShell source' {
        $violations = @(
            foreach ($sourceFile in $script:sourceFiles) {
                $lineNumber = 0
                foreach ($line in Get-Content -LiteralPath $sourceFile.FullName) {
                    $lineNumber++
                    if ($line -match '^\s*\t') {
                        '{0}:{1} uses a tab in indentation; use spaces.' -f $sourceFile.FullName, $lineNumber
                    }
                }
            }
        )

        $violations | Should -BeNullOrEmpty
    }
}
