BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:releaseBuildPath = Join-Path $repositoryRoot 'build/New-ReleaseArtifact.ps1'
    $script:manifestPath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
}

Describe 'Uninstall release packaging' {
    It 'packages a working standalone uninstaller beside install.ps1' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "copy-github-repo-uninstall-package-test-$([guid]::NewGuid().ToString('N'))"
        $extractPath = Join-Path $tempRoot 'expanded'
        $installRoot = Join-Path $tempRoot 'modules'

        try {
            New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
            $manifest = Import-PowerShellDataFile -LiteralPath $script:manifestPath
            $version = [string] $manifest.ModuleVersion

            $artifact = & $script:releaseBuildPath -OutputDirectory $tempRoot
            Expand-Archive -LiteralPath $artifact.ArtifactPath -DestinationPath $extractPath -Force

            $installerPath = Join-Path $extractPath 'install.ps1'
            $uninstallerPath = Join-Path $extractPath 'uninstall.ps1'
            Test-Path -LiteralPath $installerPath -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath $uninstallerPath -PathType Leaf | Should -BeTrue

            & $installerPath -DestinationRoot $installRoot -Confirm:$false | Out-Null
            $installedVersionPath = Join-Path $installRoot "CopyGitHubRepo/$version"
            Test-Path -LiteralPath $installedVersionPath -PathType Container | Should -BeTrue

            $result = & $uninstallerPath -Version $version -DestinationRoot $installRoot -Confirm:$false
            $result.IsSuccessful | Should -BeTrue
            $result.WasChanged | Should -BeTrue
            Test-Path -LiteralPath $installedVersionPath | Should -BeFalse
        }
        finally {
            Remove-Module CopyGitHubRepo -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
