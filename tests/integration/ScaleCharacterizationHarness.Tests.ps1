BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:fixtureGeneratorPath = Join-Path $repositoryRoot 'build/New-ScaleCharacterizationFixture.ps1'
    $script:measurementPath = Join-Path $repositoryRoot 'build/Measure-ScaleCharacterization.ps1'
}

Describe 'Scale characterization harness' {
    It 'creates and measures a small deterministic Git fixture without defining a performance gate' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "copy-github-repo-scale-test-$([guid]::NewGuid().ToString('N'))"
        $fixturePath = Join-Path $tempRoot 'fixture'
        $resultPath = Join-Path $tempRoot 'result.json'

        try {
            New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

            $fixture = & $script:fixtureGeneratorPath `
                -Path $fixturePath `
                -CommitCount 3 `
                -BranchCount 3 `
                -TagCount 4 `
                -TrackedFileCount 2 `
                -FileSizeKiB 1

            $fixture.CommitCount | Should -Be 3
            $fixture.BranchCount | Should -Be 3
            $fixture.TagCount | Should -Be 4
            $fixture.LfsFileCount | Should -Be 0
            $fixture.WorkingTreeBytes | Should -BeGreaterThan 0
            $fixture.GitDirectoryBytes | Should -BeGreaterThan 0

            $measurement = & $script:measurementPath `
                -FixturePath $fixturePath `
                -OutputPath $resultPath

            Test-Path -LiteralPath $resultPath | Should -BeTrue
            $measurement.CharacterizationKind | Should -Be 'LocalGitSubstrate'
            $measurement.Fixture.CommitCount | Should -Be 3
            $measurement.Fixture.BranchCount | Should -Be 3
            $measurement.Fixture.TagCount | Should -Be 4
            $measurement.Stages.SnapshotLocalClone.WorkspaceBytes | Should -BeGreaterThan 0
            $measurement.Stages.FullHistoryMirrorClone.WorkspaceBytes | Should -BeGreaterThan 0
            $measurement.Interpretation.IsReleaseSla | Should -BeFalse
            $measurement.Interpretation.IsBlockingCiEvidence | Should -BeFalse
            $measurement.Interpretation.IncludesGitHubNetworkOrApiLatency | Should -BeFalse

            $persisted = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
            $persisted.CharacterizationKind | Should -Be 'LocalGitSubstrate'
            $persisted.Interpretation.IsReleaseSla | Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
