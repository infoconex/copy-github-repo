BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    $script:expectedVersion = [string] (Import-PowerShellDataFile $script:modulePath).ModuleVersion
    Import-Module $script:modulePath -Force
}

Describe 'CopyGitHubRepo version reporting' {
    It 'reports the loaded module version' {
        Start-CopyGitHubRepositoryWizard -Version | Should -BeExactly $script:expectedVersion
    }
}
