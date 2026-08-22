BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:privateRoot = Join-Path $repositoryRoot 'src/CopyGitHubRepo/Private'
    $script:moduleScriptPath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psm1'
}

Describe 'Project source structure' {
    It 'keeps private implementation code in approved capability folders' {
        $expected = @(
            'Git'
            'GitHub'
            'Migration'
            'Replacement'
            'Repository'
            'Utility'
            'Wizard'
        ) | Sort-Object

        $actual = @(
            Get-ChildItem -LiteralPath $script:privateRoot -Directory |
                Select-Object -ExpandProperty Name |
                Sort-Object
        )

        $actual | Should -Be $expected
        @(Get-ChildItem -LiteralPath $script:privateRoot -File).Count | Should -Be 0
    }

    It 'loads private functions recursively in deterministic path order' {
        $content = Get-Content -LiteralPath $script:moduleScriptPath -Raw

        $content | Should -Match 'Get-ChildItem -LiteralPath \$privateFunctionPath -Filter ''\*\.ps1'' -File -Recurse'
        $content | Should -Match 'Sort-Object -Property FullName'
    }

    It 'keeps private script filenames unique across capability folders' {
        $duplicates = @(
            Get-ChildItem -LiteralPath $script:privateRoot -Filter '*.ps1' -File -Recurse |
                Group-Object -Property Name |
                Where-Object Count -gt 1
        )

        $duplicates.Count | Should -Be 0
    }
}
