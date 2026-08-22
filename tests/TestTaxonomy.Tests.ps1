BeforeAll {
    $script:testsRoot = $PSScriptRoot
    $script:repositoryRoot = Split-Path -Parent $script:testsRoot
    $script:taxonomyPath = Join-Path $script:testsRoot 'TestTaxonomy.psd1'
    $script:taxonomy = Import-PowerShellDataFile -LiteralPath $script:taxonomyPath
}

Describe 'Test taxonomy' {
    It 'maps each supported Pester category to its own tests subfolder' {
        $expected = @{
            Unit = 'tests/unit'
            Integration = 'tests/integration'
            Contract = 'tests/contract'
        }

        foreach ($category in $expected.Keys) {
            $script:taxonomy.Pester[$category] | Should -Be $expected[$category]
            Test-Path -LiteralPath (Join-Path $script:repositoryRoot $expected[$category]) -PathType Container | Should -BeTrue
        }
    }

    It 'keeps product Pester suites out of the tests infrastructure root' {
        $unexpected = @(
            Get-ChildItem -LiteralPath $script:testsRoot -Filter '*.Tests.ps1' -File |
                Where-Object Name -ne 'TestTaxonomy.Tests.ps1'
        )
        $unexpected.Count | Should -Be 0
    }

    It 'discovers at least one suite in every Pester category folder' {
        foreach ($category in @('Unit', 'Integration', 'Contract')) {
            $categoryRoot = Join-Path $script:repositoryRoot $script:taxonomy.Pester[$category]
            @(Get-ChildItem -LiteralPath $categoryRoot -Filter '*.Tests.ps1' -File).Count | Should -BeGreaterThan 0
        }
    }

    It 'keeps infrastructure suites explicit and outside product categories' {
        $script:taxonomy.Infrastructure | Should -Contain 'tests/TestTaxonomy.Tests.ps1'
        foreach ($relativePath in @($script:taxonomy.Infrastructure)) {
            Test-Path -LiteralPath (Join-Path $script:repositoryRoot $relativePath) -PathType Leaf | Should -BeTrue
        }
    }

    It 'classifies live GitHub end-to-end tests through tests/e2e' {
        $script:taxonomy.EndToEnd | Should -Be 'tests/e2e'
        $endToEndRoot = Join-Path $script:repositoryRoot $script:taxonomy.EndToEnd
        $discovered = @(
            Get-ChildItem -LiteralPath $endToEndRoot -Filter 'Invoke-*EndToEndTests.ps1' -File |
                Select-Object -ExpandProperty Name |
                Sort-Object
        )

        $discovered.Count | Should -BeGreaterThan 0
        $discovered | Should -Not -Contain 'Invoke-CleanSnapshotDemonstration.ps1'
    }

    It 'resolves every live end-to-end script to the repository module manifest' {
        $endToEndRoot = Join-Path $script:repositoryRoot $script:taxonomy.EndToEnd
        $moduleManifest = Join-Path $script:repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
        $expectedRootAssignment = '$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)'
        $expectedModuleAssignment = '$modulePath = Join-Path $repositoryRoot ''src/CopyGitHubRepo/CopyGitHubRepo.psd1'''

        Test-Path -LiteralPath $moduleManifest -PathType Leaf | Should -BeTrue

        foreach ($scriptPath in @(Get-ChildItem -LiteralPath $endToEndRoot -Filter 'Invoke-*EndToEndTests.ps1' -File)) {
            $scriptContent = Get-Content -LiteralPath $scriptPath.FullName -Raw
            $scriptContent | Should -Match ([regex]::Escape($expectedRootAssignment))
            $scriptContent | Should -Match ([regex]::Escape($expectedModuleAssignment))
            $scriptContent | Should -Not -Match ([regex]::Escape('$repositoryRoot = Split-Path -Parent $PSScriptRoot'))
        }
    }
}
