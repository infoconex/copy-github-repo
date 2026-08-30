$repositoryRootForDiscovery = Split-Path -Parent $PSScriptRoot
$modulePathForDiscovery = Join-Path $repositoryRootForDiscovery 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
$manifestForDiscovery = Import-PowerShellDataFile -Path $modulePathForDiscovery
$publicHelpCases = @($manifestForDiscovery.FunctionsToExport | Sort-Object | ForEach-Object { @{ CommandName = $_ } })

BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    $script:publicPath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/Public'
    $script:manifestData = Import-PowerShellDataFile -Path $script:modulePath
    $script:publicCommands = @($script:manifestData.FunctionsToExport | Sort-Object)

    Import-Module $script:modulePath -Force
}

Describe 'Public command help completeness' {
    It '<CommandName> publishes complete native PowerShell help' -ForEach $publicHelpCases {
        $help = Get-Help $CommandName -Full
        [string]::IsNullOrWhiteSpace([string] $help.Synopsis) | Should -BeFalse
        [string]::IsNullOrWhiteSpace([string] ($help.Description.Text -join ' ')) | Should -BeFalse
        @($help.Examples.Example).Count | Should -BeGreaterOrEqual 2
        @($help.RelatedLinks.NavigationLink).Count | Should -BeGreaterOrEqual 1
        [string]::IsNullOrWhiteSpace([string] $help.InputTypes.InputType.Type.Name) | Should -BeFalse
        [string]::IsNullOrWhiteSpace([string] $help.ReturnValues.ReturnValue.Type.Name) | Should -BeFalse
    }

    It '<CommandName> has a same-named public source file and documents every explicitly declared parameter' -ForEach $publicHelpCases {
        $sourcePath = Join-Path $script:publicPath "$CommandName.ps1"
        Test-Path -LiteralPath $sourcePath -PathType Leaf | Should -BeTrue -Because 'every manifest export must have reviewable source help'

        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref] $null, [ref] $parseErrors)
        @($parseErrors).Count | Should -Be 0

        $functionAst = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $CommandName }, $true)
        $functionAst | Should -Not -BeNullOrEmpty
        $declaredParameters = @($functionAst.Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }) | Sort-Object
        $help = Get-Help $CommandName -Full
        $helpParameters = @($help.Parameters.Parameter)
        $helpParameterNames = @($helpParameters | ForEach-Object { $_.Name })

        foreach ($parameterName in $declaredParameters) {
            $helpParameterNames | Should -Contain $parameterName
            $parameterHelp = @($helpParameters | Where-Object Name -EQ $parameterName)[0]
            $parameterHelp | Should -Not -BeNullOrEmpty
            [string]::IsNullOrWhiteSpace([string] ($parameterHelp.Description.Text -join ' ')) |
                Should -BeFalse -Because "$CommandName -$parameterName must have useful parameter help"
        }
    }

    It 'derives help coverage from every manifest export so new public commands cannot bypass documentation checks' {
        $sourceCommands = @(Get-ChildItem -LiteralPath $script:publicPath -Filter '*.ps1' -File | ForEach-Object BaseName | Sort-Object)
        ($script:publicCommands -join "`n") | Should -Be ($sourceCommands -join "`n")
        $script:publicCommands.Count | Should -BeGreaterThan 0
    }

    It 'documents the Get-GitHubRepository parameter-set contract in native help' {
        $command = Get-Command Get-GitHubRepository
        $command.DefaultParameterSet | Should -Be 'Search'
        @($command.ParameterSets.Name) | Should -Contain 'ByRepository'
        @($command.ParameterSets.Name) | Should -Contain 'Search'
        $helpText = (Get-Help Get-GitHubRepository -Full | Out-String)
        $helpText | Should -Match 'ByRepository'
        $helpText | Should -Match 'Search'
        $helpText | Should -Match 'read-only'
    }

    It 'documents copy defaults, immutable plan binding, and destructive safety semantics' {
        $help = Get-Help Copy-GitHubRepository -Full
        $helpText = (Get-Help Copy-GitHubRepository -Full | Out-String) -replace '\s+', ' '
        $restorePagesHelp = @($help.Parameters.Parameter | Where-Object Name -EQ 'RestorePages')[0].Description.Text -replace '\s+', ' '
        $actionsHelp = @($help.Parameters.Parameter | Where-Object Name -EQ 'EnableActionsAfterMigration')[0].Description.Text -replace '\s+', ' '

        $helpText | Should -Match 'Snapshot is the default'
        $helpText | Should -Match 'clean-publication|clean current-state|unrelated root commit'
        $helpText | Should -Match 'FullHistory.*preserv'
        $helpText | Should -Match 'immutable source-state evidence'
        $helpText | Should -Match 'SourceStateChangedSincePlanning'
        $helpText | Should -Match 'Force does not bypass'
        $helpText | Should -Match 'Non-interactive mutation requires -Force'
        $helpText | Should -Match 'never silently overwritten'
        $restorePagesHelp | Should -Match 'not yet implemented'
        $actionsHelp | Should -Match 'not yet implemented'
    }

    It 'documents wizard reviewed-plan execution, cancellation, and stale-plan replanning' {
        $helpText = (Get-Help Start-CopyGitHubRepositoryWizard -Full | Out-String) -replace '\s+', ' '
        $helpText | Should -Match 'PlanOnly'
        $helpText | Should -Match 'exact reviewed plan'
        $helpText | Should -Match 'source changes after plan review'
        $helpText | Should -Match 'cancellation'
        $helpText | Should -Match 'no-change'
        $helpText | Should -Match 'Copy-GitHubRepository'
    }

    It 'publishes examples through Get-Help -Examples for every manifest export' {
        foreach ($commandName in $script:publicCommands) {
            $examples = Get-Help $commandName -Examples
            @($examples.Examples.Example).Count | Should -BeGreaterOrEqual 2
            [string]::IsNullOrWhiteSpace([string] ($examples.Examples.Example.Code -join ' ')) | Should -BeFalse
        }
    }
}
