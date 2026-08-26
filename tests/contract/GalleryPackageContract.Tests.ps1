BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:manifestPath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    $script:manifestData = Import-PowerShellDataFile -Path $script:manifestPath
}

Describe 'PowerShell Gallery manifest contract' {
    It 'has a valid manifest' {
        Test-ModuleManifest -Path $script:manifestPath -ErrorAction Stop | Should -Not -BeNullOrEmpty
    }

    It 'uses product terminology suitable for Gallery discovery' {
        $script:manifestData.Description | Should -Match 'copying and migrating GitHub repositories'
        $script:manifestData.Description | Should -Match 'Snapshot'
        $script:manifestData.Description | Should -Match 'FullHistory'

        $tags = @($script:manifestData.PrivateData.PSData.Tags)
        $tags | Should -Contain 'GitHub'
        $tags | Should -Contain 'Git'
        $tags | Should -Contain 'Repository'
        $tags | Should -Contain 'Copy'
        $tags | Should -Contain 'Migration'
        $tags | Should -Contain 'Automation'
        $tags | Should -Contain 'DevOps'
        $tags | Should -Contain 'PowerShell'
        $tags | Should -Contain 'PSEdition_Core'
        $tags | Should -Contain 'Windows'
        $tags | Should -Contain 'Linux'
        $tags | Should -Contain 'MacOS'
    }

    It 'exports only the approved public function surface' {
        $actualFunctions = @($script:manifestData.FunctionsToExport | Sort-Object)
        $expectedFunctions = @(
            'Copy-GitHubRepository'
            'Get-GitHubRepository'
            'Start-CopyGitHubRepositoryWizard'
            'Test-GitHubRepositoryMigration'
        ) | Sort-Object

        ($actualFunctions -join "`n") | Should -Be ($expectedFunctions -join "`n")
        @($script:manifestData.CmdletsToExport).Count | Should -Be 0
        @($script:manifestData.AliasesToExport).Count | Should -Be 0
        @($script:manifestData.VariablesToExport).Count | Should -Be 0
    }

    It 'declares stable package identity and project metadata' {
        [string] $script:manifestData.ModuleVersion | Should -Match '^\d+\.\d+\.\d+$'
        [guid] $script:manifestData.GUID | Should -Not -Be ([guid]::Empty)
        $script:manifestData.PowerShellVersion | Should -Be '7.4'
        @($script:manifestData.CompatiblePSEditions) | Should -Contain 'Core'
        $script:manifestData.PrivateData.PSData.LicenseUri | Should -Be 'https://github.com/infoconex/copy-github-repo/blob/main/LICENSE'
        $script:manifestData.PrivateData.PSData.ProjectUri | Should -Be 'https://infoconex.github.io/copy-github-repo/'
        $script:manifestData.PrivateData.PSData.IconUri | Should -Be 'https://infoconex.github.io/copy-github-repo/assets/images/gallery-icon.png'
        $script:manifestData.PrivateData.PSData.ReleaseNotes | Should -Be 'https://github.com/infoconex/copy-github-repo/releases'
    }

    It 'declares every formatting file that the package requires' {
        @($script:manifestData.FormatsToProcess) | Should -Contain 'CopyGitHubRepo.format.ps1xml'
        foreach ($formatFile in @($script:manifestData.FormatsToProcess)) {
            Test-Path -LiteralPath (Join-Path (Split-Path -Parent $script:manifestPath) $formatFile) -PathType Leaf |
                Should -BeTrue
        }
    }
}
