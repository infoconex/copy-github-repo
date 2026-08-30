BeforeAll {
    $script:repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:executionRoot = Join-Path $script:repositoryRoot '.pester-execution'
    Import-Module PSScriptAnalyzer -ErrorAction Stop

    $script:requiredInformationRules = @(
        'PSAvoidUsingDoubleQuotesForConstantString'
        'PSAvoidUsingPositionalParameters'
        'PSUseCorrectCasing'
    )

    $script:informationSettings = @{
        Severity = @('Information')
        IncludeDefaultRules = $true
        IncludeRules = $script:requiredInformationRules
        Rules = @{
            PSAvoidUsingDoubleQuotesForConstantString = @{
                Enable = $true
            }

            PSUseCorrectCasing = @{
                Enable = $true
                CheckCommands = $true
                CheckKeyword = $true
                CheckOperator = $true
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
            Select-Object -ExpandProperty FullName
    )
}

Describe 'Required PSScriptAnalyzer Information policy' {
    It 'keeps the selected Information rules available in the pinned analyzer version' {
        $availableRules = @(Get-ScriptAnalyzerRule | Select-Object -ExpandProperty RuleName)

        foreach ($ruleName in $script:requiredInformationRules) {
            $availableRules | Should -Contain $ruleName
        }
    }

    It 'reports no findings for selectively promoted Information rules' {
        $findings = @(
            foreach ($powerShellFile in $script:governedPowerShellFiles) {
                Invoke-ScriptAnalyzer `
                    -Path $powerShellFile `
                    -Settings $script:informationSettings
            }
        )

        if ($findings.Count -gt 0) {
            $details = $findings |
                Sort-Object ScriptPath, Line, Column, RuleName |
                ForEach-Object {
                    '{0}:{1}:{2} {3}: {4}' -f $_.ScriptPath, $_.Line, $_.Column, $_.RuleName, $_.Message
                }

            $details -join [Environment]::NewLine | Write-Output
        }

        $findings | Should -BeNullOrEmpty
    }
}
