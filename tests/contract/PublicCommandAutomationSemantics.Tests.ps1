BeforeAll {
    $script:repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:moduleRoot = Join-Path $script:repositoryRoot 'src/CopyGitHubRepo'
    $script:publicRoot = Join-Path $script:moduleRoot 'Public'
    $script:manifestPath = Join-Path $script:moduleRoot 'CopyGitHubRepo.psd1'
    $script:manifest = Import-PowerShellDataFile -LiteralPath $script:manifestPath
    $script:exportedCommands = @($script:manifest.FunctionsToExport)
    $script:commandContracts = @{
        'Copy-GitHubRepository' = @{
            Semantics = 'StateChanging'
            ConfirmImpact = 'High'
        }
        'Get-GitHubRepository' = @{
            Semantics = 'ReadOnly'
        }
        'Start-CopyGitHubRepositoryWizard' = @{
            Semantics = 'StateChanging'
            ConfirmImpact = 'Low'
        }
        'Test-GitHubRepositoryMigration' = @{
            Semantics = 'ReadOnly'
        }
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

    function Get-ShouldProcessInvocationAst {
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.Language.FunctionDefinitionAst] $FunctionAst
        )

        return @(
            $FunctionAst.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                    $node.Member.Extent.Text -ceq 'ShouldProcess'
                }, $true)
        )
    }

    $script:commandAsts = @{}
    foreach ($commandName in $script:exportedCommands) {
        $script:commandAsts[$commandName] = Get-PublicCommandAst -CommandName $commandName
    }
}

Describe 'Public command automation semantic contracts' {
    It 'requires an explicit exhaustive automation classification for every exported command' {
        $classifiedCommands = @($script:commandContracts.Keys)
        $violations = @(
            foreach ($commandName in $script:exportedCommands) {
                if ($commandName -cnotin $classifiedCommands) {
                    "$commandName is manifest-exported but has no explicit automation classification."
                }
            }

            foreach ($commandName in $classifiedCommands) {
                if ($commandName -cnotin $script:exportedCommands) {
                    "$commandName has an automation classification but is not manifest-exported."
                    continue
                }

                $semantics = $script:commandContracts[$commandName].Semantics
                if ($semantics -cnotin @('ReadOnly', 'StateChanging')) {
                    "$commandName has unsupported automation semantics '$semantics'."
                }
            }
        )

        $violations | Should -BeNullOrEmpty
    }

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
        $stateChangingCommands = @(
            $script:commandContracts.Keys |
                Where-Object { $script:commandContracts[$_].Semantics -ceq 'StateChanging' } |
                Sort-Object
        )
        $violations = @(
            foreach ($commandName in $stateChangingCommands) {
                $functionAst = $script:commandAsts[$commandName]
                $cmdletBindingAttributes = @(
                    $functionAst.Body.ParamBlock.Attributes |
                        Where-Object { $_.TypeName.Name -ceq 'CmdletBinding' }
                )

                if ($cmdletBindingAttributes.Count -ne 1) {
                    "$commandName must declare exactly one [CmdletBinding()] attribute before state-changing semantics can be verified."
                    continue
                }

                $attributeText = $cmdletBindingAttributes[0].Extent.Text
                if ($attributeText -notmatch '(?i)SupportsShouldProcess') {
                    "$commandName must enable SupportsShouldProcess."
                }

                $expectedConfirmImpact = $script:commandContracts[$commandName].ConfirmImpact
                $confirmImpactPattern = "(?i)ConfirmImpact\s*=\s*'$([regex]::Escape($expectedConfirmImpact))'"
                if ($attributeText -notmatch $confirmImpactPattern) {
                    "$commandName must declare ConfirmImpact = '$expectedConfirmImpact'."
                }

                $shouldProcessCalls = @(Get-ShouldProcessInvocationAst -FunctionAst $functionAst)
                if ($shouldProcessCalls.Count -eq 0) {
                    "$commandName must call ShouldProcess()."
                }
            }
        )

        $violations | Should -BeNullOrEmpty
    }

    It 'requires the copy command ShouldProcess decision to gate mutation dispatch' {
        $copyAst = $script:commandAsts['Copy-GitHubRepository']
        $shouldProcessCalls = @(Get-ShouldProcessInvocationAst -FunctionAst $copyAst)
        $mutationDispatch = $copyAst.Find({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -ceq 'Invoke-CgrApprovedMigrationPlan'
            }, $true)

        $shouldProcessCalls.Count | Should -Be 1
        $mutationDispatch | Should -Not -BeNullOrEmpty
        $shouldProcessCalls[0].Extent.StartOffset | Should -BeLessThan $mutationDispatch.Extent.StartOffset
        $copyAst.Extent.Text | Should -Match '(?ms)if\s*\(\s*-not\s+\$PSCmdlet\.ShouldProcess\s*\(\s*\$target,\s*\$action\s*\)\s*\)\s*\{\s*return\s+\$plan\s*\}'
    }

    It 'keeps the wizard ShouldProcess decision in its delegated execution guard' {
        $wizardAst = $script:commandAsts['Start-CopyGitHubRepositoryWizard']
        $wizardText = $wizardAst.Extent.Text
        $shouldProcessCalls = @(Get-ShouldProcessInvocationAst -FunctionAst $wizardAst)
        $wizardDispatch = $wizardAst.Find({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -ceq 'Invoke-CgrRepositoryCopyWizard'
            }, $true)

        $shouldProcessCalls.Count | Should -Be 1
        $wizardDispatch | Should -Not -BeNullOrEmpty
        $shouldProcessCalls[0].Expression.Extent.Text | Should -Be '$callerPSCmdlet'
        $shouldProcessCalls[0].Extent.StartOffset | Should -BeLessThan $wizardDispatch.Extent.StartOffset
        $wizardText | Should -Match '\$callerPSCmdlet\s*=\s*\$PSCmdlet'
        $wizardText | Should -Match '(?ms)\$executionGuard\s*=\s*\{.*?\$callerPSCmdlet\.ShouldProcess\s*\('
        $wizardText | Should -Match 'Invoke-CgrRepositoryCopyWizard\s+-HostName\s+\$resolvedHostName\s+-ExecutionGuard\s+\$executionGuard'
    }

    It 'keeps explicitly classified read-only commands outside ShouldProcess semantics' {
        $readOnlyCommands = @(
            $script:commandContracts.Keys |
                Where-Object { $script:commandContracts[$_].Semantics -ceq 'ReadOnly' } |
                Sort-Object
        )

        foreach ($commandName in $readOnlyCommands) {
            $functionAst = $script:commandAsts[$commandName]
            $cmdletBindingAttributes = @(
                $functionAst.Body.ParamBlock.Attributes |
                    Where-Object { $_.TypeName.Name -ceq 'CmdletBinding' }
            )

            $cmdletBindingAttributes.Count | Should -Be 1 -Because "$commandName must remain an advanced function"
            $cmdletBindingAttributes[0].Extent.Text | Should -Not -Match '(?i)SupportsShouldProcess' -Because "$commandName is explicitly classified read-only"
            @(Get-ShouldProcessInvocationAst -FunctionAst $functionAst) | Should -BeNullOrEmpty -Because "$commandName is explicitly classified read-only"
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
