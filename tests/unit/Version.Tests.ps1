BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force
}

Describe 'CopyGitHubRepo version reporting' {
    It 'reports the loaded module version without starting the wizard' {
        InModuleScope CopyGitHubRepo {
            Mock New-CgrWizardActivitySink { throw 'Wizard activity must not start for -Version.' }
            Mock Invoke-CgrRepositoryCopyWizard { throw 'Wizard execution must not start for -Version.' }

            $manifestPath = Join-Path $PSScriptRoot '../../src/CopyGitHubRepo/CopyGitHubRepo.psd1'
            $expectedVersion = [string] (Import-PowerShellDataFile $manifestPath).ModuleVersion

            Start-CopyGitHubRepositoryWizard -Version | Should -BeExactly $expectedVersion

            Should -Invoke New-CgrWizardActivitySink -Times 0 -Exactly
            Should -Invoke Invoke-CgrRepositoryCopyWizard -Times 0 -Exactly
        }
    }
}
