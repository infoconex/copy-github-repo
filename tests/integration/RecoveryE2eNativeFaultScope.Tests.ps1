BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $root 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
    . (Join-Path $root 'tests/support/Invoke-RecoveryE2eScopedGitCommitTreeFault.ps1')
}

Describe 'Scoped real-Git recovery E2E fault injection' {
    It 'applies the invalid date to native commit-tree only and restores the original executor' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ("cgr-commit-fault-test-$([guid]::NewGuid().ToString('N'))")
        New-Item -ItemType Directory -Path $path -ErrorAction Stop | Out-Null
        try {
            & git -C $path init -b main | Out-Null
            $LASTEXITCODE | Should -Be 0
            Set-Content -LiteralPath (Join-Path $path 'fixture.txt') -Value 'Isolated local Git fixture' -Encoding utf8NoBOM
            & git -C $path add fixture.txt
            $LASTEXITCODE | Should -Be 0
            $tree = (& git -C $path write-tree | Select-Object -First 1)
            $LASTEXITCODE | Should -Be 0
            [string] $tree | Should -Match '^[0-9a-f]{40,64}$'

            $module = Get-Module CopyGitHubRepo
            $beforeExecutor = & $module { (Get-Item Function:Invoke-CgrNativeCommand).ScriptBlock.ToString() }
            $beforeAuthorDate = [Environment]::GetEnvironmentVariable('GIT_AUTHOR_DATE', 'Process')
            $beforeCommitterDate = [Environment]::GetEnvironmentVariable('GIT_COMMITTER_DATE', 'Process')

            $result = Invoke-RecoveryE2eScopedGitCommitTreeFault -Action {
                $ordinary = & $module {
                    param($localPath)
                    Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $localPath, 'rev-parse', '--is-inside-work-tree')
                } $path
                $fault = & $module {
                    param($localPath, $treeSha)
                    Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('-C', $localPath, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit-tree', $treeSha, '-m', 'Scoped fault')
                } $path $tree
                [pscustomobject] @{ Ordinary = $ordinary; CommitTree = $fault }
            }

            $result.OriginalError | Should -BeNullOrEmpty
            $result.ScopedNativeCommitTreeCalls | Should -Be 1
            @($result.Output).Count | Should -Be 1
            $result.Output[0].Ordinary.ExitCode | Should -Be 0
            $result.Output[0].Ordinary.Output | Should -Contain 'true'
            $result.Output[0].CommitTree.ExitCode | Should -Not -Be 0
            $result.Output[0].CommitTree.ErrorText | Should -Match 'invalid date format'
            [Environment]::GetEnvironmentVariable('GIT_AUTHOR_DATE', 'Process') | Should -Be $beforeAuthorDate
            [Environment]::GetEnvironmentVariable('GIT_COMMITTER_DATE', 'Process') | Should -Be $beforeCommitterDate
            (& $module { (Get-Item Function:Invoke-CgrNativeCommand).ScriptBlock.ToString() }) | Should -BeExactly $beforeExecutor
        }
        finally {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'restores the native executor after an unexpected error before commit-tree' {
        $module = Get-Module CopyGitHubRepo
        $beforeExecutor = & $module { (Get-Item Function:Invoke-CgrNativeCommand).ScriptBlock.ToString() }
        $result = Invoke-RecoveryE2eScopedGitCommitTreeFault -Action {
            $ordinary = & $module { Invoke-CgrNativeCommand -FilePath 'git' -ArgumentList @('--version') }
            if ($ordinary.ExitCode -ne 0) { throw 'Local Git version check failed.' }
            throw 'Unexpected pre-commit failure'
        }
        $result.ScopedNativeCommitTreeCalls | Should -Be 0
        $result.OriginalError.Exception.Message | Should -Be 'Unexpected pre-commit failure'
        (& $module { (Get-Item Function:Invoke-CgrNativeCommand).ScriptBlock.ToString() }) | Should -BeExactly $beforeExecutor
    }
}
