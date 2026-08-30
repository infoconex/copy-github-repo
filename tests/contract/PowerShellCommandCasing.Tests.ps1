BeforeAll {
    $script:repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:executionRoot = Join-Path $script:repositoryRoot '.pester-execution'
    $script:inventoryPath = Join-Path $script:repositoryRoot 'tests/CommandCasing.psd1'
    $script:inventory = Import-PowerShellDataFile -LiteralPath $script:inventoryPath

    function Get-CgrParsedCommandData {
        param(
            [Parameter(Mandatory)]
            [string] $Text,

            [string] $Path = '<memory>'
        )

        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            $Text,
            $Path,
            [ref] $tokens,
            [ref] $parseErrors
        )

        [pscustomobject]@{
            Ast = $ast
            ParseErrors = @($parseErrors)
        }
    }

    function Get-CgrCommandCasingFinding {
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.Language.Ast] $Ast,

            [Parameter(Mandatory)]
            [System.Collections.Generic.Dictionary[string, string]] $CanonicalCommands,

            [Parameter(Mandatory)]
            [string] $Path
        )

        $commandAsts = @(
            $Ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst]
                }, $true)
        )

        foreach ($commandAst in $commandAsts) {
            $commandName = $commandAst.GetCommandName()
            if ([string]::IsNullOrWhiteSpace($commandName)) {
                continue
            }

            if (-not $CanonicalCommands.ContainsKey($commandName)) {
                [pscustomobject]@{
                    Kind = 'Unknown'
                    Path = $Path
                    Line = $commandAst.Extent.StartLineNumber
                    Actual = $commandName
                    Expected = $null
                }
                continue
            }

            $canonicalName = $CanonicalCommands[$commandName]
            if ($commandName -cne $canonicalName) {
                [pscustomobject]@{
                    Kind = 'Casing'
                    Path = $Path
                    Line = $commandAst.Extent.StartLineNumber
                    Actual = $commandName
                    Expected = $canonicalName
                }
            }
        }
    }

    $script:governedPowerShellFiles = @(
        Get-ChildItem -LiteralPath $script:repositoryRoot -Recurse -File |
            Where-Object {
                $_.Extension -in @('.ps1', '.psm1', '.psd1') -and
                -not $_.FullName.StartsWith(
                    $script:executionRoot + [IO.Path]::DirectorySeparatorChar,
                    [StringComparison]::OrdinalIgnoreCase
                )
            } |
            Sort-Object FullName
    )

    $script:parsedFiles = @(
        foreach ($powerShellFile in $script:governedPowerShellFiles) {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $powerShellFile.FullName,
                [ref] $tokens,
                [ref] $parseErrors
            )

            [pscustomobject]@{
                File = $powerShellFile
                Ast = $ast
                ParseErrors = @($parseErrors)
            }
        }
    )

    $script:canonicalCommands = [System.Collections.Generic.Dictionary[string, string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )

    foreach ($commandName in @($script:inventory.Commands)) {
        if ($script:canonicalCommands.ContainsKey($commandName)) {
            throw "Duplicate command casing inventory entry: $commandName"
        }

        $script:canonicalCommands.Add($commandName, $commandName)
    }

    foreach ($parsedFile in $script:parsedFiles) {
        $functionAsts = @(
            $parsedFile.Ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                }, $true)
        )

        foreach ($functionAst in $functionAsts) {
            $functionName = $functionAst.Name
            if ($script:canonicalCommands.ContainsKey($functionName)) {
                $existingName = $script:canonicalCommands[$functionName]
                if ($existingName -cne $functionName) {
                    throw "Conflicting canonical casing for command $functionName; existing casing is $existingName."
                }

                continue
            }

            $script:canonicalCommands.Add($functionName, $functionName)
        }
    }
}

Describe 'PowerShell command casing contract' {
    It 'accepts canonical casing for a governed command' {
        $parsed = Get-CgrParsedCommandData -Text 'Get-ChildItem -Path .'
        $findings = @(
            Get-CgrCommandCasingFinding `
                -Ast $parsed.Ast `
                -CanonicalCommands $script:canonicalCommands `
                -Path '<positive>'
        )

        $parsed.ParseErrors | Should -BeNullOrEmpty
        $findings | Should -BeNullOrEmpty
    }

    It 'rejects deliberately mis-cased governed command names' {
        $parsed = Get-CgrParsedCommandData -Text 'get-childitem -Path .'
        $findings = @(
            Get-CgrCommandCasingFinding `
                -Ast $parsed.Ast `
                -CanonicalCommands $script:canonicalCommands `
                -Path '<negative>'
        )

        $parsed.ParseErrors | Should -BeNullOrEmpty
        $findings.Count | Should -Be 1
        $findings[0].Kind | Should -Be 'Casing'
        $findings[0].Actual | Should -BeExactly 'get-childitem'
        $findings[0].Expected | Should -BeExactly 'Get-ChildItem'
    }

    It 'ignores dynamic invocations whose command name is not statically knowable' {
        $parsed = Get-CgrParsedCommandData -Text '$commandName = ''Get-ChildItem''; & $commandName -Path .'
        $findings = @(
            Get-CgrCommandCasingFinding `
                -Ast $parsed.Ast `
                -CanonicalCommands $script:canonicalCommands `
                -Path '<dynamic>'
        )

        $parsed.ParseErrors | Should -BeNullOrEmpty
        $findings | Should -BeNullOrEmpty
    }

    It 'uses canonical casing for every statically-known command invocation in governed PowerShell files' {
        $parseFailures = @(
            foreach ($parsedFile in $script:parsedFiles) {
                foreach ($parseError in $parsedFile.ParseErrors) {
                    '{0}:{1}:{2} {3}' -f $parsedFile.File.FullName, $parseError.Extent.StartLineNumber, $parseError.Extent.StartColumnNumber, $parseError.Message
                }
            }
        )
        $parseFailures | Should -BeNullOrEmpty

        $findings = @(
            foreach ($parsedFile in $script:parsedFiles) {
                Get-CgrCommandCasingFinding `
                    -Ast $parsedFile.Ast `
                    -CanonicalCommands $script:canonicalCommands `
                    -Path $parsedFile.File.FullName
            }
        )

        $unknownCommands = @(
            $findings |
                Where-Object Kind -EQ 'Unknown' |
                Select-Object -ExpandProperty Actual -Unique |
                Sort-Object
        )

        if ($unknownCommands.Count -gt 0) {
            throw ('Unknown literal commands require canonical entries in tests/CommandCasing.psd1: {0}' -f ($unknownCommands -join ', '))
        }

        $casingFindings = @($findings | Where-Object Kind -EQ 'Casing')
        if ($casingFindings.Count -gt 0) {
            $details = $casingFindings |
                Sort-Object Actual, Path, Line |
                ForEach-Object {
                    '{0}:{1} command {2} must use canonical casing {3}.' -f $_.Path, $_.Line, $_.Actual, $_.Expected
                }

            $details -join [Environment]::NewLine | Write-Output
        }

        $casingFindings | Should -BeNullOrEmpty
    }
}
