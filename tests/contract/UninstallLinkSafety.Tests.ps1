BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:uninstallPath = Join-Path $repositoryRoot 'uninstall.ps1'
    $script:uninstallSource = Get-Content -LiteralPath $script:uninstallPath -Raw
}

Describe 'Uninstall filesystem-link safety contract' {
    It 'does not reject a path solely because Windows marks it as a reparse point' {
        $script:uninstallSource | Should -Not -Match 'Attributes\s+-band\s+\[System\.IO\.FileAttributes\]::ReparsePoint'
    }

    It 'detects actual filesystem links by link metadata' {
        $script:uninstallSource | Should -Match '\.LinkType'
        $script:uninstallSource | Should -Match '\.Target'
        $script:uninstallSource | Should -Match 'Assert-CgrNotFileSystemLink'
    }

    It 'retains fail-closed handling for link-backed uninstall paths' {
        $script:uninstallSource | Should -Match 'CopyGitHubRepo\.UnsafeUninstallPath'
        $script:uninstallSource | Should -Match 'symbolic link or junction'
    }
}
