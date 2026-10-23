BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repositoryRoot 'tests/support/Get-RecoveryE2eNewChildRecoveryReports.ps1')
}

Describe 'Recovery E2E migration-authored child report discovery' {
    BeforeEach {
        $script:reportDir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:prefix = 'infoconex-copy-github-repo-recovery-e2e-abcd123456-settingsfault-destination'
        $script:pattern = "$($script:prefix)-*.json"
    }

    It 'returns a stable empty report collection when the directory does not exist' {
        Set-StrictMode -Version Latest
        $result = Get-RecoveryE2eNewChildRecoveryReports -Directory $script:reportDir -FilePattern $script:pattern
        $result.Count | Should -Be 0
        $result.Files | Should -BeOfType 'System.Object[]'
        @($result.Files).Count | Should -Be 0
    }

    It 'keeps exactly one new child recovery report as an indexable array under StrictMode' {
        Set-StrictMode -Version Latest
        New-Item -LiteralPath $script:reportDir -ItemType Directory -Force | Out-Null
        $onePath = Join-Path $script:reportDir "$($script:prefix)-20261023T010839076Z.json"
        Set-Content -LiteralPath $onePath -Value '{"FailureStage":"RestoreSupportedSettings"}' -Encoding utf8NoBOM
        $result = Get-RecoveryE2eNewChildRecoveryReports -Directory $script:reportDir -FilePattern $script:pattern

        $result.Count | Should -Be 1
        $result.Files | Should -BeOfType 'System.Object[]'
        @($result.Files).Count | Should -Be 1
        $result.Files[0].FullName | Should -BeExactly $onePath
        (Get-Content -LiteralPath $result.Files[0].FullName -Raw | ConvertFrom-Json).FailureStage |
            Should -BeExactly 'RestoreSupportedSettings'
    }

    It 'counts multiple new reports rather than silently picking one or including old evidence' {
        Set-StrictMode -Version Latest
        New-Item -LiteralPath $script:reportDir -ItemType Directory -Force | Out-Null
        $previous = Join-Path $script:reportDir "$($script:prefix)-previous.json"
        $first = Join-Path $script:reportDir "$($script:prefix)-new1.json"
        $second = Join-Path $script:reportDir "$($script:prefix)-new2.json"
        $unrelated = Join-Path $script:reportDir 'unrelated-recovery.json'
        foreach ($path in @($previous, $first, $second, $unrelated)) {
            Set-Content -LiteralPath $path -Value '{}' -Encoding utf8NoBOM
        }

        $args = @{
            Directory = $script:reportDir
            FilePattern = $script:pattern
            PreviouslyObservedPaths = @($previous)
        }
        $result = Get-RecoveryE2eNewChildRecoveryReports @args
        $result.Count | Should -Be 2
        $result.Files | Should -BeOfType 'System.Object[]'
        @($result.Files).Count | Should -Be 2
        (@($result.Files.FullName) -contains $first) | Should -BeTrue
        (@($result.Files.FullName) -contains $second) | Should -BeTrue
        (@($result.Files.FullName) -contains $previous) | Should -BeFalse
        (@($result.Files.FullName) -contains $unrelated) | Should -BeFalse

        $args.PreviouslyObservedPaths = @($previous, $first, $second)
        $allPreviouslySeen = Get-RecoveryE2eNewChildRecoveryReports @args
        $allPreviouslySeen.Count | Should -Be 0
        @($allPreviouslySeen.Files).Count | Should -Be 0
    }
}
