BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:testProjectPath = Join-Path $repositoryRoot 'build/Test-Project.ps1'
    $script:testProject = Get-Content -LiteralPath $script:testProjectPath -Raw
    $script:contributingPath = Join-Path $repositoryRoot 'CONTRIBUTING.md'
    $script:contributing = Get-Content -LiteralPath $script:contributingPath -Raw
}

Describe 'Code coverage policy' {
    It 'enforces the measured cross-platform coverage baseline' {
        $match = [regex]::Match($script:testProject, '\$minimumCoveragePercent\s*=\s*([0-9.]+)')
        $match.Success | Should -BeTrue
        [double] $match.Groups[1].Value | Should -BeGreaterOrEqual 65.0
    }

    It 'documents coverage as a regression guard rather than a vanity metric' {
        $script:contributing | Should -Match '65% Pester instruction coverage'
        $script:contributing | Should -Match '65\.34%'
        $script:contributing | Should -Match 'Do not add low-value assertions solely to increase the percentage'
    }

    It 'keeps focused critical-path coverage suites in the repository' {
        $criticalSuites = @(
            'tests/unit/GitHubApiAdapters.Tests.ps1'
            'tests/unit/SnapshotPagination.Tests.ps1'
            'tests/unit/RepositoryPathBoundary.Tests.ps1'
            'tests/integration/StaleStateSafety.Tests.ps1'
            'tests/contract/PublicOutputContracts.Tests.ps1'
            'tests/integration/WizardMigrationIntegration.Tests.ps1'
        )

        foreach ($suite in $criticalSuites) {
            Test-Path -LiteralPath (Join-Path $repositoryRoot $suite) | Should -BeTrue
        }
    }
}
