BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:readme = Get-Content -LiteralPath (Join-Path $repositoryRoot 'README.md') -Raw
    $script:security = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/security/installation-security.md') -Raw
    $script:uninstallPath = Join-Path $repositoryRoot 'uninstall.ps1'
}

Describe 'Uninstall documentation contract' {
    It 'documents the interactive convenience bootstrap and deterministic local options' {
        Test-Path -LiteralPath $script:uninstallPath -PathType Leaf | Should -BeTrue
        $script:readme | Should -Match 'uninstall\.ps1 \| iex'
        $script:readme | Should -Match '-AllVersions'
        $script:readme | Should -Match '-WhatIf'
        $script:security | Should -Match 'interactive by default'
        $script:security | Should -Match '-Version 0\.1\.0'
        $script:security | Should -Match '-AllVersions'
        $script:security | Should -Match '-Confirm:\$false'
        $script:security | Should -Match 'does not require network access'
    }

    It 'keeps the mutable-main uninstall bootstrap inside the documented trust boundary' {
        $script:security | Should -Match 'uninstall bootstrap.*mutable `main`'
        $script:security | Should -Match 'same trust boundary'
    }
}
