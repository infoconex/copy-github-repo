BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:referenceRoot = Join-Path $repositoryRoot 'docs/reference/commands'
    $manifestPath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $manifestPath -Force

    $script:publicCommands = @(
        'Copy-GitHubRepository',
        'Get-GitHubRepository',
        'Start-CopyGitHubRepositoryWizard',
        'Test-GitHubRepositoryMigration'
    )
    $script:commonParameterNames = @(
        'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction',
        'ProgressAction', 'ErrorVariable', 'WarningVariable', 'InformationVariable',
        'OutVariable', 'OutBuffer', 'PipelineVariable', 'WhatIf', 'Confirm'
    )
}

Describe 'Command reference documentation' {
    It 'has one reference page for every public command' {
        foreach ($commandName in $script:publicCommands) {
            Test-Path -LiteralPath (Join-Path $script:referenceRoot "$commandName.md") -PathType Leaf | Should -BeTrue
        }
        @(Get-ChildItem -LiteralPath $script:referenceRoot -Filter '*.md' -File | Where-Object Name -ne 'README.md').Count | Should -Be $script:publicCommands.Count
    }

    It 'links every command from the reference index' {
        $index = Get-Content -LiteralPath (Join-Path $script:referenceRoot 'README.md') -Raw
        foreach ($commandName in $script:publicCommands) {
            $index | Should -Match ([regex]::Escape("$commandName.md"))
        }
    }

    It 'documents every declared public parameter' {
        foreach ($commandName in $script:publicCommands) {
            $reference = Get-Content -LiteralPath (Join-Path $script:referenceRoot "$commandName.md") -Raw
            $reference | Should -Match '## Parameters'

            $declaredParameters = @(Get-Command $commandName -Module CopyGitHubRepo).Parameters.Keys |
                Where-Object { $_ -notin $script:commonParameterNames }

            foreach ($parameterName in $declaredParameters) {
                $parameterTableCell = '| `{0}` |' -f $parameterName
                $reference | Should -Match ([regex]::Escape($parameterTableCell))
            }
        }
    }

    It 'provides usage, output, failures, and examples for every command' {
        foreach ($commandName in $script:publicCommands) {
            $reference = Get-Content -LiteralPath (Join-Path $script:referenceRoot "$commandName.md") -Raw
            $reference | Should -Match '## When to use it'
            $reference | Should -Match '## Output'
            $reference | Should -Match '## Important failure conditions'
            $reference | Should -Match '## Examples'
            $reference | Should -Match '```powershell'
        }
    }

    It 'keeps the README focused on navigation and quick starts' {
        $readme = Get-Content -LiteralPath (Join-Path $repositoryRoot 'README.md') -Raw
        $readme | Should -Match 'docs/reference/commands/README\.md'
        $readme | Should -Match 'docs/product/architecture\.md'
        $readme | Should -Match 'docs/security/installation-security\.md'
        $readme | Should -Not -Match '### Same-name replacement'
        $readme | Should -Not -Match '## Install a pinned release'
    }

    It 'documents all four commands in the GitHub host boundary' {
        $hostSupport = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/user/host-support.md') -Raw
        foreach ($commandName in $script:publicCommands) {
            $formattedCommand = '`{0}`' -f $commandName
            $hostSupport | Should -Match ([regex]::Escape($formattedCommand))
        }
        $hostSupport | Should -Match 'GitHubHostNotSupported'
    }

    It 'keeps controlled end-to-end harnesses under tests/e2e' {
        $expectedHarnesses = @(
            'Invoke-SnapshotEndToEndTests.ps1',
            'Invoke-FullHistoryEndToEndTests.ps1',
            'Invoke-GitLfsEndToEndTests.ps1',
            'Invoke-RecoveryEndToEndTests.ps1',
            'Invoke-RepositorySettingsEndToEndTests.ps1',
            'Invoke-SameNameEndToEndTests.ps1',
            'Invoke-SameNameFullHistoryEndToEndTests.ps1'
        )
        foreach ($fileName in $expectedHarnesses) {
            Test-Path -LiteralPath (Join-Path $PSScriptRoot "e2e/$fileName") -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $repositoryRoot "build/$fileName") | Should -BeFalse
        }
    }
}
