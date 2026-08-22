BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $root 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Wizard public contract' {
    It 'exports the wizard with complete help' {
        Get-Command Start-CopyGitHubRepositoryWizard | Should -Not -BeNullOrEmpty
        $help = Get-Help Start-CopyGitHubRepositoryWizard -Full
        [string]::IsNullOrWhiteSpace([string] $help.Synopsis) | Should -BeFalse
        @($help.Examples.Example).Count | Should -BeGreaterOrEqual 2
        [string]::IsNullOrWhiteSpace([string] $help.ReturnValues.ReturnValue.Type.Name) | Should -BeFalse
    }
}
