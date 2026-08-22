BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:uninstallPath = Join-Path $repositoryRoot 'uninstall.ps1'
    $script:moduleGuid = 'c428210d-c7a4-49db-81d1-830606e16fa6'

    function Get-TestCopyGitHubRepoInstallation {
        param(
            [Parameter(Mandatory)] [string] $DestinationRoot,
            [Parameter(Mandatory)] [string] $Version,
            [string] $Guid = $script:moduleGuid
        )

        $versionPath = Join-Path $DestinationRoot "CopyGitHubRepo/$Version"
        New-Item -Path $versionPath -ItemType Directory -Force | Out-Null
        @"
@{
    RootModule = 'CopyGitHubRepo.psm1'
    ModuleVersion = '$Version'
    GUID = '$Guid'
    Author = 'infoconex'
    Description = 'Test installation.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @()
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
"@ | Set-Content -LiteralPath (Join-Path $versionPath 'CopyGitHubRepo.psd1') -Encoding utf8NoBOM
        "`$script:LoadedFrom = '$versionPath'" | Set-Content -LiteralPath (Join-Path $versionPath 'CopyGitHubRepo.psm1') -Encoding utf8NoBOM
        return $versionPath
    }
}

Describe 'CopyGitHubRepo uninstall script' {
    BeforeEach {
        $script:testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "copy-github-repo-uninstall-test-$([guid]::NewGuid().ToString('N'))"
        New-Item -Path $script:testRoot -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        Remove-Module CopyGitHubRepo -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Variable -Name CgrUninstallTestState -Scope Global -ErrorAction SilentlyContinue
    }

    It 'returns a no-change result when no installation exists' {
        $result = & $script:uninstallPath -DestinationRoot $script:testRoot -Confirm:$false
        $result.IsSuccessful | Should -BeTrue
        $result.WasChanged | Should -BeFalse
        $result.WasCancelled | Should -BeFalse
        @($result.DiscoveredVersions).Count | Should -Be 0
    }

    It 'interactively removes the only installed version after confirmation' {
        $versionPath = Get-TestCopyGitHubRepoInstallation -DestinationRoot $script:testRoot -Version '0.1.0'
        Mock Read-Host { 'y' }
        $result = & $script:uninstallPath -DestinationRoot $script:testRoot -Confirm:$false
        Test-Path -LiteralPath $versionPath | Should -BeFalse
        $result.WasChanged | Should -BeTrue
        $result.TargetedVersions | Should -Contain '0.1.0'
    }

    It 'defaults destructive interactive confirmation to no' {
        $versionPath = Get-TestCopyGitHubRepoInstallation -DestinationRoot $script:testRoot -Version '0.1.0'
        Mock Read-Host { '' }
        $result = & $script:uninstallPath -DestinationRoot $script:testRoot -Confirm:$false
        Test-Path -LiteralPath $versionPath | Should -BeTrue
        $result.WasChanged | Should -BeFalse
        $result.WasCancelled | Should -BeTrue
    }

    It 'lets the user select one version when multiple versions are installed' {
        $firstPath = Get-TestCopyGitHubRepoInstallation -DestinationRoot $script:testRoot -Version '0.1.0'
        $secondPath = Get-TestCopyGitHubRepoInstallation -DestinationRoot $script:testRoot -Version '0.2.0'
        Set-Variable -Name CgrUninstallTestState -Scope Global -Value ([pscustomobject] @{
                Responses = @('1', '2', 'y')
                Index = 0
            })
        Mock Read-Host {
            $state = Get-Variable -Name CgrUninstallTestState -Scope Global -ValueOnly
            $response = $state.Responses[$state.Index]
            $state.Index++
            return $response
        }
        $result = & $script:uninstallPath -DestinationRoot $script:testRoot -Confirm:$false
        Test-Path -LiteralPath $firstPath | Should -BeTrue
        Test-Path -LiteralPath $secondPath | Should -BeFalse
        $result.TargetedVersions | Should -Contain '0.2.0'
        $result.TargetedVersions | Should -Not -Contain '0.1.0'
    }

    It 'lets the user remove all validated versions after one final confirmation' {
        $firstPath = Get-TestCopyGitHubRepoInstallation -DestinationRoot $script:testRoot -Version '0.1.0'
        $secondPath = Get-TestCopyGitHubRepoInstallation -DestinationRoot $script:testRoot -Version '0.2.0'
        Set-Variable -Name CgrUninstallTestState -Scope Global -Value ([pscustomobject] @{
                Responses = @('2', 'y')
                Index = 0
            })
        Mock Read-Host {
            $state = Get-Variable -Name CgrUninstallTestState -Scope Global -ValueOnly
            $response = $state.Responses[$state.Index]
            $state.Index++
            return $response
        }
        $result = & $script:uninstallPath -DestinationRoot $script:testRoot -Confirm:$false
        Test-Path -LiteralPath $firstPath | Should -BeFalse
        Test-Path -LiteralPath $secondPath | Should -BeFalse
        @($result.RemovedPaths).Count | Should -Be 2
    }

    It 'defaults the multiple-version action prompt to cancel' {
        $firstPath = Get-TestCopyGitHubRepoInstallation -DestinationRoot $script:testRoot -Version '0.1.0'
        $secondPath = Get-TestCopyGitHubRepoInstallation -DestinationRoot $script:testRoot -Version '0.2.0'
        Mock Read-Host { '' }
        $result = & $script:uninstallPath -DestinationRoot $script:testRoot -Confirm:$false
        Test-Path -LiteralPath $firstPath | Should -BeTrue
        Test-Path -LiteralPath $secondPath | Should -BeTrue
        $result.WasCancelled | Should -BeTrue
    }

    It 'supports deterministic version-specific removal' {
        $firstPath = Get-TestCopyGitHubRepoInstallation -DestinationRoot $script:testRoot -Version '0.1.0'
        $secondPath = Get-TestCopyGitHubRepoInstallation -DestinationRoot $script:testRoot -Version '0.2.0'
        $result = & $script:uninstallPath -Version '0.1.0' -DestinationRoot $script:testRoot -Confirm:$false
        Test-Path -LiteralPath $firstPath | Should -BeFalse
        Test-Path -LiteralPath $secondPath | Should -BeTrue
        $result.TargetedVersions | Should -Contain '0.1.0'
    }

    It 'supports deterministic all-version removal' {
        $firstPath = Get-TestCopyGitHubRepoInstallation -DestinationRoot $script:testRoot -Version '0.1.0'
        $secondPath = Get-TestCopyGitHubRepoInstallation -DestinationRoot $script:testRoot -Version '0.2.0'
        $result = & $script:uninstallPath -AllVersions -DestinationRoot $script:testRoot -Confirm:$false
        Test-Path -LiteralPath $firstPath | Should -BeFalse
        Test-Path -LiteralPath $secondPath | Should -BeFalse
        $result.WasChanged | Should -BeTrue
    }

    It 'honors WhatIf without filesystem mutation' {
        $versionPath = Get-TestCopyGitHubRepoInstallation -DestinationRoot $script:testRoot -Version '0.1.0'
        $result = & $script:uninstallPath -Version '0.1.0' -DestinationRoot $script:testRoot -WhatIf
        Test-Path -LiteralPath $versionPath | Should -BeTrue
        $result.WasChanged | Should -BeFalse
        @($result.RemovedPaths).Count | Should -Be 0
    }

    It 'returns no-change for an explicitly requested version that is absent' {
        Get-TestCopyGitHubRepoInstallation -DestinationRoot $script:testRoot -Version '0.1.0' | Out-Null
        $result = & $script:uninstallPath -Version '0.2.0' -DestinationRoot $script:testRoot -Confirm:$false
        $result.WasChanged | Should -BeFalse
        @($result.TargetedVersions).Count | Should -Be 0
    }

    It 'unloads the targeted module before removing its files' {
        $versionPath = Get-TestCopyGitHubRepoInstallation -DestinationRoot $script:testRoot -Version '0.1.0'
        Import-Module (Join-Path $versionPath 'CopyGitHubRepo.psd1') -Force
        Get-Module CopyGitHubRepo | Should -Not -BeNullOrEmpty
        & $script:uninstallPath -Version '0.1.0' -DestinationRoot $script:testRoot -Confirm:$false | Out-Null
        Get-Module CopyGitHubRepo | Should -BeNullOrEmpty
        Test-Path -LiteralPath $versionPath | Should -BeFalse
    }

    It 'fails closed on a module identity mismatch' {
        $versionPath = Get-TestCopyGitHubRepoInstallation -DestinationRoot $script:testRoot -Version '0.1.0' -Guid '11111111-1111-1111-1111-111111111111'
        { & $script:uninstallPath -Version '0.1.0' -DestinationRoot $script:testRoot -Confirm:$false } | Should -Throw -ErrorId 'CopyGitHubRepo.InvalidInstalledModule*'
        Test-Path -LiteralPath $versionPath | Should -BeTrue
    }

    It 'does not remove sibling modules' {
        $versionPath = Get-TestCopyGitHubRepoInstallation -DestinationRoot $script:testRoot -Version '0.1.0'
        $siblingPath = Join-Path $script:testRoot 'SomeOtherModule/1.0.0'
        New-Item -Path $siblingPath -ItemType Directory -Force | Out-Null
        & $script:uninstallPath -Version '0.1.0' -DestinationRoot $script:testRoot -Confirm:$false | Out-Null
        Test-Path -LiteralPath $versionPath | Should -BeFalse
        Test-Path -LiteralPath $siblingPath | Should -BeTrue
    }

    It 'rejects an unexpected directory under the module root' {
        $versionPath = Get-TestCopyGitHubRepoInstallation -DestinationRoot $script:testRoot -Version '0.1.0'
        $unexpectedPath = Join-Path $script:testRoot 'CopyGitHubRepo/not-a-version'
        New-Item -Path $unexpectedPath -ItemType Directory -Force | Out-Null
        { & $script:uninstallPath -AllVersions -DestinationRoot $script:testRoot -Confirm:$false } | Should -Throw -ErrorId 'CopyGitHubRepo.UnsafeInstallationLayout*'
        Test-Path -LiteralPath $versionPath | Should -BeTrue
        Test-Path -LiteralPath $unexpectedPath | Should -BeTrue
    }
}
