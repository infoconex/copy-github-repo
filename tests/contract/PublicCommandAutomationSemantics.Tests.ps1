BeforeAll {
    $script:repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:moduleRoot = Join-Path $script:repositoryRoot 'src/CopyGitHubRepo'
    $script:publicRoot = Join-Path $script:moduleRoot 'Public'
    $script:manifestPath = Join-Path $script:moduleRoot 'CopyGitHubRepo.psd1'
    $script:manifest = Import-PowerShellDataFile -LiteralPath $script:manifestPath
    $script:exportedCommands = @($script:manifest.FunctionsToExport)
    $script:stateChangingCommands = @{
        'Copy-GitHubRepository' = 'High'
        'Start-CopyGitHubRepositoryWizard' = 'Low'
    }

    function Get-PublicCommandAst {
        param(
            [Parameter(Mandatory)]
            [string] $CommandName
        )

        $path = Join-Path $script:publicRoot "$CommandName.ps1"
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $path,
            [ref] $tokens,
            [ref] $parseErrors
        )

        if (@($parseErrors).Count -gt 0) {
            throw "Unable to parse public command source '$path'."
        }

        $functionAst = $ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -ceq $CommandName
            }, $true)

        if ($null -eq $functionAst) {
            throw "Unable to find exported function '$CommandName' in '$path'."
        }

        return $functionAst
    }

    $script:commandAsts = @{}
    foreach ($commandName in $script:exportedCommands) {
        $script:commandAsts[$commandName] = Get-PublicCommandAst -CommandName $commandName
    }
}

Describe 'Public command automation semantic contracts' {
    It 'requires every manifest-exported function to use CmdletBinding' {
        $violations = @(
            foreach ($commandName in $script:exportedCommands) {
                $functionAst = $script:commandAsts[$commandName]
                $cmdletBindingAttribute = @(
                    $functionAst.Body.ParamBlock.Attributes |
                        Where-Object { $_.TypeName.Name -ceq 'CmdletBinding' }
                )

                if ($cmdletBindingAttribute.Count -ne 1) {
                    "$commandName must declare exactly one [CmdletBinding()] attribute."
                }
            }
        )

        $violations | Should -BeNullOrEmpty
    }

    It 'requires state-changing exported commands to use ShouldProcess with the expected ConfirmImpact' {
        $violations = @(
            foreach ($commandName in $script:stateChangingCommands.Keys) {
                $functionAst = $script:commandAsts[$commandName]
                if ($null -eq $functionAst) {
                    "$commandName is classified as state-changing but is not manifest-exported."
                    continue
                }

                $cmdletBindingAttribute = @(
                    $functionAst.Body.ParamBlock.Attributes |
                        Where-Object { $_.TypeName.Name -ceq 'CmdletBinding' }
                ) | Select-Object -First 1

                $attributeText = $cmdletBindingAttribute.Extent.Text
                if ($attributeText -notmatch '(?i)SupportsShouldProcess') {
                    "$commandName must enable SupportsShouldProcess."
                }

                $expectedConfirmImpact = $script:stateChangingCommands[$commandName]
                $confirmImpactPattern = "(?i)ConfirmImpact\s*=\s*'$([regex]::Escape($expectedConfirmImpact))'"
                if ($attributeText -notmatch $confirmImpactPattern) {
                    "$commandName must declare ConfirmImpact = '$expectedConfirmImpact'."
                }

                if ($functionAst.Extent.Text -notmatch '(?i)\.ShouldProcess\s*\(') {
                    "$commandName must call ShouldProcess() before mutation dispatch."
                }
            }
        )

        $violations | Should -BeNullOrEmpty
    }

    It 'keeps the wizard ShouldProcess decision in its execution guard' {
        $wizardText = $script:commandAsts['Start-CopyGitHubRepositoryWizard'].Extent.Text

        $wizardText | Should -Match '\$callerPSCmdlet\s*=\s*\$PSCmdlet'
        $wizardText | Should -Match '\$callerPSCmdlet\.ShouldProcess\s*\('
        $wizardText | Should -Match 'Invoke-CgrRepositoryCopyWizard\s+-HostName\s+\$resolvedHostName\s+-ExecutionGuard\s+\$executionGuard'
    }

    It 'keeps read-only exported commands outside the state-changing classification' {
        $readOnlyCommands = @(
            $script:exportedCommands |
                Where-Object { $_ -cnotin @($script:stateChangingCommands.Keys) }
        )

        $readOnlyCommands | Should -Contain 'Get-GitHubRepository'
        $readOnlyCommands | Should -Contain 'Test-GitHubRepositoryMigration'

        foreach ($commandName in $readOnlyCommands) {
            $functionAst = $script:commandAsts[$commandName]
            $cmdletBindingAttribute = @(
                $functionAst.Body.ParamBlock.Attributes |
                    Where-Object { $_.TypeName.Name -ceq 'CmdletBinding' }
            ) | Select-Object -First 1

            $cmdletBindingAttribute.Extent.Text | Should -Not -Match '(?i)SupportsShouldProcess' -Because "$commandName is read-only"
        }
    }

    It 'requires the copy command to expose a documented noninteractive automation path' {
        $copyAst = $script:commandAsts['Copy-GitHubRepository']
        $parameterNames = @(
            $copyAst.Body.ParamBlock.Parameters |
                ForEach-Object { $_.Name.VariablePath.UserPath }
        )

        $parameterNames | Should -Contain 'NonInteractive'
        $copyAst.Extent.Text | Should -Match '(?ms)\.PARAMETER\s+NonInteractive\b'
        $copyAst.Extent.Text | Should -Match '(?i)non-interactive mutation requires\s+-Force'
        $copyAst.Extent.Text | Should -Match '(?i)-Force and -Confirm:\$false do not bypass'
    }

    It 'documents the direct automation alternative for the interactive wizard' {
        $wizardAst = $script:commandAsts['Start-CopyGitHubRepositoryWizard']

        $wizardAst.Extent.Text | Should -Match '(?i)Use Copy-GitHubRepository directly when\s+structured execution output is required by automation'
    }
}
